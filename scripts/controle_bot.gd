class_name ControleBot
extends Controle
## Jogador controlado pela máquina, com 3 dificuldades.
##
## A cada "tempo de reação" o bot decide o que fazer (caçar monstros,
## atacar o oponente ou fugir) e calcula um caminho pela Navegacao. Entre
## uma decisão e outra, ele segue o caminho e se posiciona para o ataque
## automático acertar.

enum Dificuldade { FACIL, NORMAL, DIFICIL }

const NOMES := ["FÁCIL", "NORMAL", "DIFÍCIL"]
const PARAMS := {
	Dificuldade.FACIL: {"reacao": 0.5, "erro": 0.2, "portas": false, "foge": false, "melhor_melhoria": 0.0},
	Dificuldade.NORMAL: {"reacao": 0.25, "erro": 0.07, "portas": true, "foge": true, "melhor_melhoria": 0.7},
	Dificuldade.DIFICIL: {"reacao": 0.1, "erro": 0.02, "portas": true, "foge": true, "melhor_melhoria": 1.0},
}
## Preferência de melhorias por tipo de ataque (da melhor para a pior)
const PREFERENCIAS := {
	ClasseDados.TipoAtaque.FLECHA: ["multi", "forca", "frenesi", "disparo", "alcance", "agilidade", "vigor"],
	ClasseDados.TipoAtaque.CORPO_A_CORPO: ["sangue", "forca", "vigor", "frenesi", "agilidade", "alcance"],
	ClasseDados.TipoAtaque.MAGIA: ["forca", "explosao", "disparo", "frenesi", "vigor", "alcance", "agilidade"],
	ClasseDados.TipoAtaque.INVOCAR: ["exercito", "frenesi", "forca", "vigor", "agilidade"],
}

var dificuldade: Dificuldade
var partida: Node
var p: Dictionary

var _seguidor: SeguidorCaminho
var _alvo = null
var _modo := "cacar_monstro"
var _t_decisao := 0.0
var _t_escolha := 0.0
var _distraido := 0.0


func _init(dif: Dificuldade, p_partida: Node) -> void:
	dificuldade = dif
	partida = p_partida
	p = PARAMS[dif]


func nome() -> String:
	return "CPU"


func atualizar(l, delta: float) -> void:
	pulo_apertou = false
	pulo_soltou = false
	descer_apertou = false
	opcao = -1
	eixo = 0.0
	if _seguidor == null:
		_seguidor = SeguidorCaminho.new(partida.nav)
		_seguidor.usar_portas = p["portas"]

	_t_decisao -= delta
	if _t_decisao <= 0.0 or (_seguidor.replanejar and l.is_on_floor()):
		_t_decisao = p["reacao"] * randf_range(0.8, 1.3)
		_decidir(l)

	_mover(l, delta)
	_escolher_melhoria(l, delta)


# ------------------------------------------------------------------ Decisão

func _decidir(l) -> void:
	var nav: Navegacao = partida.nav
	var meu_no := nav.no_de_posicao(l.position)
	if meu_no == Navegacao.INVALIDO:
		return  # no ar: decide quando pousar

	var inimigo = partida.oponente(l)
	var vida: float = l.vida / l.vida_max
	_alvo = null
	_modo = "cacar_monstro"

	var monstro_perto = _monstro_perigoso(l)
	if l.eh_recruta and vida < 0.35 and monstro_perto != null:
		_modo = "fugir_monstro"  # Recruta ferido espera regenerar
	elif p["foge"] and vida < 0.3 and inimigo.vivo and not inimigo.eh_recruta \
			and l.position.distance_to(inimigo.position) < 130.0 and not partida.morte_subita:
		_modo = "fugir"
	elif l.atk_tipo() == ClasseDados.TipoAtaque.INVOCAR and inimigo.vivo \
			and l.position.distance_to(inimigo.position) < 90.0:
		_modo = "fugir"  # o Rei deixa os lacaios lutarem
	elif not l.eh_recruta and inimigo.vivo and _vale_atacar(l, inimigo):
		_modo = "atacar"
		_alvo = inimigo

	# Normal/Difícil: aproveitam itens que aparecem perto
	if _modo == "cacar_monstro" and dificuldade != Dificuldade.FACIL:
		var item = _item_perto(l)
		if item != null:
			_modo = "item"
			_seguidor.ir_para(meu_no, nav.no_mais_proximo(item.position))
			_alvo = null
			return
	if _modo == "cacar_monstro":
		_alvo = _monstro_mais_perto(l, meu_no)
		if _alvo == null and inimigo.vivo:
			_alvo = inimigo
			_modo = "atacar"

	# Bots mais fracos se distraem de vez em quando
	if _distraido > 0.0:
		_distraido -= p["reacao"]
		return
	if randf() < p["erro"]:
		_distraido = 1.0
		var nos := nav.nos.keys()
		_seguidor.ir_para(meu_no, nos.pick_random())
		return

	var destino := Navegacao.INVALIDO
	if _modo == "fugir":
		destino = _no_longe_de(inimigo.position, nav)
	elif _modo == "fugir_monstro":
		destino = _no_longe_de(monstro_perto.position, nav)
	elif _alvo != null:
		destino = nav.no_mais_proximo(_alvo.position)
		if l.atk_tipo() == ClasseDados.TipoAtaque.INVOCAR:
			destino = _no_perto_de(_alvo.position, 60.0, nav)
	if destino != Navegacao.INVALIDO:
		_seguidor.ir_para(meu_no, destino)


func _monstro_perigoso(l):
	## Monstro mais próximo a menos de 80 px (ou null).
	var melhor = null
	var melhor_d := 80.0
	for a in l.get_tree().get_nodes_in_group("alvo"):
		if a.equipe == 0 and a.esta_vivo():
			var d: float = l.position.distance_to(a.position)
			if d < melhor_d:
				melhor_d = d
				melhor = a
	return melhor


func _item_perto(l):
	var melhor = null
	var melhor_d := 120.0
	for it in l.get_tree().get_nodes_in_group("item"):
		var d: float = l.position.distance_to(it.position)
		if d < melhor_d:
			melhor_d = d
			melhor = it
	return melhor


func _vale_atacar(l, inimigo) -> bool:
	if partida.morte_subita or partida.tempo_restante < 45.0:
		return true
	var d: float = l.position.distance_to(inimigo.position)
	# Bots normal/difícil farmam monstros no começo para evoluir, a não ser
	# que o inimigo chegue perto ou esteja muito ferido.
	if dificuldade != Dificuldade.FACIL and l.nivel < 4 and partida.tempo_restante > 100.0:
		var ferido: bool = inimigo.vida / inimigo.vida_max < 0.35 and d < 160.0
		if d > 60.0 and not ferido:
			return false
	match dificuldade:
		Dificuldade.FACIL:
			return d < 120.0
		Dificuldade.NORMAL:
			if inimigo.eh_recruta:
				return d < 160.0
			return l.vida / l.vida_max >= inimigo.vida / inimigo.vida_max * 0.8 or l.nivel > inimigo.nivel
		_:
			var meu_poder: float = l.vida * (1.0 + 0.25 * l.nivel)
			var poder_dele: float = inimigo.vida * (1.0 + 0.25 * inimigo.nivel)
			if inimigo.eh_recruta:
				poder_dele *= 0.4
			return meu_poder >= poder_dele * 0.9


func _monstro_mais_perto(l, meu_no: Vector2i):
	var nav: Navegacao = partida.nav
	var dist := nav.distancias(meu_no, p["portas"])
	var melhor = null
	var melhor_d := INF
	for a in l.get_tree().get_nodes_in_group("alvo"):
		if a.equipe != 0 or not a.esta_vivo():
			continue
		var no := nav.no_mais_proximo(a.position)
		var d: float = dist.get(no, 999) + l.position.distance_to(a.position) / 64.0
		if d < melhor_d:
			melhor_d = d
			melhor = a
	return melhor


func _no_longe_de(pos: Vector2, nav: Navegacao) -> Vector2i:
	var melhor := Navegacao.INVALIDO
	var melhor_d := -1.0
	var nos := nav.nos.keys()
	for i in 16:
		var no: Vector2i = nos.pick_random()
		var d := Navegacao.centro(no).distance_to(pos)
		if d > melhor_d:
			melhor_d = d
			melhor = no
	return melhor


func _no_perto_de(pos: Vector2, raio: float, nav: Navegacao) -> Vector2i:
	var nos := nav.nos.keys()
	for i in 24:
		var no: Vector2i = nos.pick_random()
		var d := Navegacao.centro(no).distance_to(pos)
		if d > raio * 0.5 and d < raio * 1.5:
			return no
	return nav.no_mais_proximo(pos)


# ------------------------------------------------------------------ Movimento

func _mover(l, delta: float) -> void:
	# Posicionamento de combate tem prioridade sobre o caminho
	if _alvo != null and is_instance_valid(_alvo) and _alvo.esta_vivo() and _modo != "fugir":
		var dif: Vector2 = _alvo.position - l.position
		var d := dif.length()
		match l.atk_tipo():
			ClasseDados.TipoAtaque.FLECHA, ClasseDados.TipoAtaque.MAGIA:
				if _alvo is Lutador and d < l.atk_alcance() * 0.4 and absf(dif.y) < 24.0:
					eixo = -signf(dif.x)  # recua para não apanhar de perto
					if l.is_on_wall() and l.is_on_floor():
						pulo_apertou = true
					return
				if d < l.atk_alcance() * 0.8 and absf(dif.y) < 40.0 and l._linha_livre(_alvo.global_position):
					return  # parado: o ataque automático cuida do resto
			ClasseDados.TipoAtaque.CORPO_A_CORPO:
				if absf(dif.x) < l.atk_alcance() * 0.6 and absf(dif.y) < 14.0:
					return

	var r := _seguidor.passo(l, delta)
	eixo = r["eixo"]
	pulo_apertou = r["pular"]
	descer_apertou = r["descer"]
	# Sem caminho (ou já chegou): vai direto na direção do alvo
	if _seguidor.chegou() and _alvo != null and is_instance_valid(_alvo) and _modo != "fugir":
		var dx: float = _alvo.position.x - l.position.x
		eixo = signf(dx) if absf(dx) > 6.0 else 0.0


func _escolher_melhoria(l, delta: float) -> void:
	if l.escolhas.is_empty():
		_t_escolha = 0.0
		return
	_t_escolha += delta
	if _t_escolha < p["reacao"] * 4.0:
		return
	_t_escolha = 0.0
	var par: Array = l.escolhas[0]
	opcao = randi() % 2
	if randf() < p["melhor_melhoria"]:
		var pref: Array = PREFERENCIAS[l.dados.tipo_ataque]
		var a: int = pref.find(par[0]["id"])
		var b: int = pref.find(par[1]["id"])
		a = 99 if a < 0 else a
		b = 99 if b < 0 else b
		opcao = 0 if a <= b else 1
