extends Node2D
## Uma partida 1x1: monta a arena procedural, cria os jogadores (humanos ou
## bots), teleporta quem entra nas portas, gera monstros que evoluem com o
## nível dos jogadores, controla o cronômetro e a Morte Súbita e decide o
## vencedor.

signal revanche
signal voltar

const CENA_LUTADOR := preload("res://scenes/lutador.tscn")
const CENA_MINION := preload("res://scenes/minion.tscn")
const TEX_GOSMA: Array[Texture2D] = [
	preload("res://assets/sprites/gosma_1.png"),
	preload("res://assets/sprites/gosma_2.png"),
	preload("res://assets/sprites/gosma_3.png"),
	preload("res://assets/sprites/gosma_4.png"),
]
const TEX_LACAIO := {
	1: preload("res://assets/sprites/lacaio_1.png"),
	2: preload("res://assets/sprites/lacaio_2.png"),
}
const TEX_CORTE := preload("res://assets/sprites/corte.png")
const TEX_BRILHO := preload("res://assets/sprites/brilho.png")

const TAM := GeradorArena.TAM
const ATLAS_PAREDE := Vector2i(0, 0)
const ATLAS_PLATAFORMA := Vector2i(1, 0)
const ATLAS_CHAO := Vector2i(2, 0)

## Vida dos monstros de nível 1 (cresce 35% por nível)
const VIDA_MONSTRO := 48.0
## Dano dos monstros de nível 1 (cresce 20% por nível)
const DANO_MONSTRO := 4.0
## Dano entre jogadores (fração do dano normal)
const PVP_BASE := 0.4
## Recruta atacando jogador
const PVP_RECRUTA_ATACA := 0.25
## Jogador com classe atacando Recruta
const PVP_CONTRA_RECRUTA := 1.0 / 3.0

# Morte Súbita
const NEVOA_VELOCIDADE := 3.0      # pixels por segundo
const NEVOA_DANO := 4.0            # a cada NEVOA_INTERVALO
const NEVOA_INTERVALO := 0.5
const MORTE_SUBITA_DEGRAU := 15.0  # segundos entre aumentos de dano PvP
const MORTE_SUBITA_AUMENTO := 0.3

@onready var tiles: TileMapLayer = $Mundo/Tiles
@onready var desenho_portas: Node2D = $Mundo/Portas
@onready var nevoa_visual: Node2D = $Mundo/Nevoa
@onready var entidades: Node2D = $Mundo/Entidades
@onready var hud: Control = $HUD/Painel

var mapa: Dictionary
var nav: Navegacao
var portas: Array = []
var portas_abertas := true
var jogadores := {}
var contagem := 3.0
var tempo_restante := 180.0
var morte_subita := false
var tempo_morte_subita := 0.0
var nivel_nevoa := float(GeradorArena.ALTURA)
var vencedor := 0   ## 0 = empate
var fim := false
var anuncio := ""
var anuncio_cor := Color.WHITE
var anuncio_t := 0.0

var _t_monstro := 0.0
var _tremor := 0.0
var _t_nevoa := 0.0
var _t_fim := 0.0
var _vida_no_quadro := {}


func iniciar(config: Dictionary) -> void:
	## config: {"semente": int, "tempo": float, "bots": {1: dif, 2: dif}}
	##   dificuldade -1 = humano; 0, 1, 2 = bot fácil, normal, difícil.
	var rng := RandomNumberGenerator.new()
	rng.seed = config.get("semente", randi())
	tempo_restante = config.get("tempo", Jogo.TEMPO_PARTIDA)
	mapa = GeradorArena.gerar(rng)
	nav = mapa["nav"]
	portas = mapa["portas"]
	_montar_tiles(mapa["grade"])
	desenho_portas.portas = portas
	nevoa_visual.partida = self
	hud.partida = self

	var bots: Dictionary = config.get("bots", {1: -1, 2: -1})
	for n in [1, 2]:
		var dif: int = bots.get(n, -1)
		var c: Controle = ControleHumano.new(n) if dif < 0 else ControleBot.new(dif, self)
		var l: Lutador = CENA_LUTADOR.instantiate()
		l.configurar(n, Jogo.dados_recruta(), self, c)
		l.position = mapa["inicio"][n]
		l.morreu.connect(_ao_morrer)
		entidades.add_child(l)
		jogadores[n] = l

	for i in 2:
		_criar_monstro()


func _montar_tiles(g: Array) -> void:
	tiles.clear()
	for y in GeradorArena.LINHAS:
		for x in GeradorArena.COLUNAS:
			match g[y][x]:
				GeradorArena.SOLIDO:
					var topo_livre: bool = y > 0 and g[y - 1][x] != GeradorArena.SOLIDO
					tiles.set_cell(Vector2i(x, y), 0, ATLAS_CHAO if topo_livre else ATLAS_PAREDE)
				GeradorArena.PLATAFORMA:
					tiles.set_cell(Vector2i(x, y), 0, ATLAS_PLATAFORMA)


func oponente(l: Lutador) -> Lutador:
	return jogadores[2 if l.numero == 1 else 1]


# ------------------------------------------------------------------ Laço principal

func _process(delta: float) -> void:
	if contagem > -1.0:
		var antes := contagem
		contagem -= delta
		if antes > 0.0 and contagem <= 0.0:
			for l in jogadores.values():
				l.ativo = true
	if anuncio_t > 0.0:
		anuncio_t -= delta
	# Tremor de tela (pouso pesado do Orc)
	var mundo: Node2D = $Mundo
	if _tremor > 0.05:
		mundo.position = Vector2(0, 8) + Vector2(randf_range(-1, 1), randf_range(-1, 1)).round() * _tremor
		_tremor = move_toward(_tremor, 0.0, delta * 10.0)
	else:
		mundo.position = Vector2(0, 8)

	if fim:
		_t_fim += delta
		if _t_fim > 1.0 and (Input.is_action_just_pressed("p1_pular") or Input.is_action_just_pressed("menu_ok")):
			revanche.emit()
	if Input.is_action_just_pressed("menu_voltar"):
		voltar.emit()


func _physics_process(delta: float) -> void:
	for n in jogadores:
		_vida_no_quadro[n] = jogadores[n].vida
	if portas_abertas:
		_atravessar_portas(delta)
	_resgatar_fugitivos()
	if fim or contagem > 0.0:
		return

	if not morte_subita:
		tempo_restante -= delta
		if tempo_restante <= 0.0:
			tempo_restante = 0.0
			_iniciar_morte_subita()
		_t_monstro += delta
		var nivel := nivel_monstros()
		var intervalo := maxf(3.5, 6.0 - 0.4 * (nivel - 1))
		var maximo := 4 if nivel < 4 else 5
		if _t_monstro >= intervalo:
			_t_monstro = 0.0
			if _contar_equipe(0) < maximo:
				_criar_monstro()
	else:
		_atualizar_morte_subita(delta)


# ------------------------------------------------------------------ Regras de dano

func mult_pvp(atacante: Lutador, alvo: Lutador) -> float:
	var m := PVP_BASE
	if morte_subita:
		m = 1.0 + MORTE_SUBITA_AUMENTO * floorf(tempo_morte_subita / MORTE_SUBITA_DEGRAU)
	if atacante.eh_recruta:
		m *= PVP_RECRUTA_ATACA
	elif alvo.eh_recruta:
		m *= PVP_CONTRA_RECRUTA
	return m


# ------------------------------------------------------------------ Classes

func sortear_classe(l: Lutador) -> void:
	## Sorteia uma classe sem repetir a do oponente.
	var outro := oponente(l)
	var opcoes: Array[ClasseDados] = []
	for i in Jogo.CLASSES.size():
		var candidata := Jogo.dados_classe(i)
		if outro.eh_recruta or outro.dados.nome != candidata.nome:
			opcoes.append(candidata)
	var d: ClasseDados = opcoes.pick_random()
	l.receber_classe(d)
	criar_brilho(l.position)
	criar_brilho(l.position + Vector2(0, -6))
	mostrar_anuncio("%s VIROU %s!" % [l.nome_jogador(), d.nome.to_upper()], Jogo.COR_TIME[l.numero])


func mostrar_anuncio(texto: String, cor: Color, duracao := 2.0) -> void:
	anuncio = texto
	anuncio_cor = cor
	anuncio_t = duracao


# ------------------------------------------------------------------ Portas

func _atravessar_portas(delta: float) -> void:
	for v in get_tree().get_nodes_in_group("viajante"):
		if v.cooldown_porta > 0.0:
			v.cooldown_porta -= delta
			continue
		var p: Vector2 = v.position
		for porta in portas:
			var gatilho: Rect2 = porta["gatilho"]
			var normal: Vector2 = porta["normal"]
			if gatilho.has_point(p) and v.velocity.dot(normal) <= 0.0:
				_teleportar(v, porta, portas[porta["par"]])
				break


func _resgatar_fugitivos() -> void:
	## Segurança: quem estiver fora da arena (ou preso no vão de uma porta
	## fechada) volta para dentro, na saída da porta mais próxima.
	var area := Rect2(TAM * 0.5, TAM * 0.5, GeradorArena.LARGURA - TAM, GeradorArena.ALTURA - TAM)
	for v in get_tree().get_nodes_in_group("viajante"):
		var p: Vector2 = v.position
		if area.has_point(p):
			continue
		if portas_abertas and p.x > -48 and p.x < GeradorArena.LARGURA + 48 and p.y > -64 and p.y < GeradorArena.ALTURA:
			continue  # atravessando uma porta aberta: normal
		if v is Projetil:
			v.queue_free()
			continue
		var melhor: Vector2 = mapa["inicio"][1]
		for porta in portas:
			var saida: Vector2 = porta["saida"]
			if saida.distance_to(p) < melhor.distance_to(p):
				melhor = saida
		v.position = melhor
		v.velocity = Vector2.ZERO


func _teleportar(v, de: Dictionary, para: Dictionary) -> void:
	var vel: Vector2 = v.velocity
	var normal: Vector2 = para["normal"]
	if v is Projetil:
		v.velocity = normal * vel.length()
	elif para["tipo"] == "teto":
		v.velocity = Vector2(0.0, 40.0)
	else:
		var vy := -80.0 if de["tipo"] == "teto" else minf(vel.y, 0.0)
		v.velocity = Vector2(normal.x * maxf(absf(vel.x), 60.0), vy)
	criar_brilho(v.position)
	v.position = para["saida"]
	v.cooldown_porta = 0.2
	if v is Lutador:
		criar_brilho(v.position)
		Jogo.tocar("porta")


func _fechar_portas() -> void:
	portas_abertas = false
	nav.portas_abertas = false
	var g: Array = mapa["grade"]
	for porta in portas:
		for c in porta["celulas"]:
			g[c.y][c.x] = GeradorArena.SOLIDO
	_montar_tiles(g)
	desenho_portas.fechadas = true


# ------------------------------------------------------------------ Morte Súbita

func _iniciar_morte_subita() -> void:
	morte_subita = true
	tempo_morte_subita = 0.0
	_fechar_portas()
	for l in jogadores.values():
		if l.vivo and l.eh_recruta:
			sortear_classe(l)
	mostrar_anuncio("MORTE SÚBITA!", Color("b13e53"), 2.5)
	Jogo.tocar("morte")


func _atualizar_morte_subita(delta: float) -> void:
	tempo_morte_subita += delta
	nivel_nevoa = maxf(nivel_nevoa - NEVOA_VELOCIDADE * delta, -16.0)
	_t_nevoa += delta
	if _t_nevoa < NEVOA_INTERVALO:
		return
	_t_nevoa = 0.0
	for a in get_tree().get_nodes_in_group("alvo"):
		if a.esta_vivo() and a.position.y + 6.0 > nivel_nevoa:
			a.receber_dano(NEVOA_DANO, null)


# ------------------------------------------------------------------ Monstros

func nivel_monstros() -> int:
	## Média dos níveis dos jogadores (arredondada para baixo). Usar a média,
	## e não o maior nível, evita que quem ficou para trás não consiga mais
	## matar monstros.
	var soma := 0
	for l in jogadores.values():
		soma += l.nivel
	return maxi(1, soma / maxi(jogadores.size(), 1))


func _criar_monstro() -> void:
	var pontos: Array = mapa["pontos_monstro"]
	if pontos.is_empty():
		return
	# Evita nascer em cima de um jogador
	var pos: Vector2 = pontos.pick_random()
	for tentativa in 8:
		var longe := true
		for l in jogadores.values():
			if l.position.distance_to(pos) < 48.0:
				longe = false
		if longe:
			break
		pos = pontos.pick_random()

	var n := nivel_monstros() - 1
	var faixa := clampi(1 + n / 2, 1, 4)  # níveis 1, 2-3, 4-5, 6+
	var m: Minion = CENA_MINION.instantiate()
	m.configurar(self, 0, null, TEX_GOSMA[faixa - 1],
			VIDA_MONSTRO * pow(1.35, n),     # vida
			DANO_MONSTRO * pow(1.2, n),      # dano
			minf(30.0 * (1.0 + 0.08 * n), 60.0),  # velocidade
			minf(70.0 + 15.0 * n, 170.0),    # visão
			4 + 2 * n)                       # XP
	m.intervalo_ataque = maxf(0.9 * pow(0.93, n), 0.5)
	m.position = pos
	entidades.add_child(m)
	criar_brilho(m.position)


# ------------------------------------------------------------------ Criação de entidades

func criar_projetil(dono: Lutador, pos: Vector2, vel: Vector2, dano: float, alcance: float, magia: bool) -> void:
	var p := Projetil.new()
	p.partida = self
	p.dono = dono
	p.equipe = dono.equipe
	p.position = pos
	p.velocity = vel
	p.dano = dano
	p.alcance_max = alcance
	p.magia = magia
	p.dano_min = dono.dados.dano_minimo_magia
	p.raio_explosao = dono.raio_explosao
	entidades.add_child(p)


func criar_lacaio(rei: Lutador) -> void:
	var m: Minion = CENA_MINION.instantiate()
	m.configurar(self, rei.equipe, rei, TEX_LACAIO[rei.equipe],
			rei.dados.vida_lacaio * rei.mult_lacaio, rei.dano * rei.mult_lacaio,
			rei.dados.velocidade_lacaio, 2000.0, 2)
	m.intervalo_ataque = 1.2
	m.alcance_arremesso = 90.0
	m.position = rei.position
	entidades.add_child(m)
	criar_brilho(m.position)
	Jogo.tocar("invocar")


func criar_lanca(lacaio: Minion, alvo) -> void:
	## Lança arremessada por um lacaio: mais fraca e lenta que as flechas.
	var p := Projetil.new()
	p.partida = self
	p.dono = lacaio.dono
	p.equipe = lacaio.equipe
	p.position = lacaio.position
	p.velocity = (alvo.global_position - lacaio.global_position).normalized() * 130.0
	p.dano = lacaio.dano * 0.6
	p.alcance_max = 110.0
	entidades.add_child(p)
	Jogo.tocar("flecha")


func contar_lacaios(rei: Lutador) -> int:
	var n := 0
	for a in get_tree().get_nodes_in_group("alvo"):
		if a is Minion and a.dono == rei:
			n += 1
	return n


func _contar_equipe(equipe: int) -> int:
	var n := 0
	for a in get_tree().get_nodes_in_group("alvo"):
		if a.equipe == equipe:
			n += 1
	return n


func criar_corte(pos: Vector2, espelhar: bool) -> void:
	var s := Sprite2D.new()
	s.texture = TEX_CORTE
	s.hframes = 2
	s.flip_h = espelhar
	s.position = pos
	entidades.add_child(s)
	var tw := s.create_tween()
	tw.tween_interval(0.06)
	tw.tween_callback(func() -> void: s.frame = 1)
	tw.tween_interval(0.08)
	tw.tween_callback(s.queue_free)


func tremer(forca: float) -> void:
	_tremor = maxf(_tremor, forca)


func criar_poeira(pos: Vector2) -> void:
	Jogo.tocar("pouso")
	for lado in [-1.0, 1.0]:
		for i in 3:
			var s := Sprite2D.new()
			s.texture = TEX_BRILHO
			s.hframes = 3
			s.scale = Vector2.ONE * 0.4
			s.modulate = Color(0.75, 0.7, 0.6, 0.8)
			s.position = pos + Vector2(lado * 3.0, -2.0)
			entidades.add_child(s)
			var tw := s.create_tween()
			tw.tween_property(s, "position", s.position + Vector2(lado * (8.0 + i * 5.0), -3.0 - i * 2.0), 0.3)
			tw.parallel().tween_property(s, "modulate:a", 0.0, 0.3)
			tw.tween_callback(s.queue_free)


func criar_brilho(pos: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = TEX_BRILHO
	s.hframes = 3
	s.position = pos
	entidades.add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "frame", 2, 0.2)
	tw.tween_callback(s.queue_free)


func mostrar_texto(pos: Vector2, texto: String, cor: Color) -> void:
	var l := Label.new()
	l.text = texto
	var ls := LabelSettings.new()
	ls.font_size = 8
	ls.font_color = cor
	ls.outline_size = 3
	ls.outline_color = Color("1a1c2c")
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(80, 12)
	l.position = pos - Vector2(40, 6)
	l.z_index = 10
	entidades.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 12.0, 0.6)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.3)
	tw.tween_callback(l.queue_free)


# ------------------------------------------------------------------ Fim de partida

func _ao_morrer(_l: Lutador) -> void:
	if not fim:
		call_deferred("_decidir_vencedor")


func _decidir_vencedor() -> void:
	if fim:
		return
	var vivos: Array = jogadores.values().filter(func(j): return j.vivo)
	if vivos.size() == 1:
		vencedor = vivos[0].numero
	elif vivos.is_empty():
		# Os dois caíram juntos: vence quem tinha mais vida antes do golpe final
		var v1: float = _vida_no_quadro.get(1, 0.0)
		var v2: float = _vida_no_quadro.get(2, 0.0)
		vencedor = 1 if v1 > v2 else (2 if v2 > v1 else 0)
	else:
		return
	fim = true
	for j in jogadores.values():
		j.ativo = false
	Engine.time_scale = 0.35
	await get_tree().create_timer(0.5, true, false, true).timeout
	Engine.time_scale = 1.0
	Jogo.tocar("vitoria")


func _exit_tree() -> void:
	Engine.time_scale = 1.0
