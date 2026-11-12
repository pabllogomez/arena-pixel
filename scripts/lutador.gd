class_name Lutador
extends CharacterBody2D
## Personagem de um jogador (humano ou bot). Começa como Recruta, ganha uma
## classe sorteada no nível 2 e melhorias nos níveis seguintes. Anda, pula e
## ataca sozinho quando um inimigo entra no alcance.

signal morreu(lutador: Lutador)

const GRAVIDADE := 700.0
const QUEDA_MAX := 360.0
const TEMPO_COYOTE := 0.1
const TEMPO_BUFFER := 0.12
## XP que o Recruta precisa para ganhar a classe (~3 monstros iniciais)
const XP_PARA_CLASSE := 16
## Regeneração fora de combate: depois de REGEN_ESPERA s sem tomar dano,
## recupera REGEN_TAXA da vida máxima por segundo.
const REGEN_ESPERA := 5.0
const REGEN_TAXA := 0.03
## Rei com lacaios vivos leva só esta fração do dano de projéteis
const GUARDA_REAL := 0.7
const QUADROS := {
	"parado": [0, 1],
	"correr": [2, 3, 4, 5],
	"pulo": [6],
	"queda": [7],
}

@onready var sprite: Sprite2D = $Sprite2D

var numero := 1
var equipe := 1
var dados: ClasseDados
var partida: Node
var controle: Controle
var eh_recruta := true

# Atributos atuais (começam iguais aos da classe e crescem com as melhorias)
var vida_max := 100.0
var vida := 100.0
var velocidade := 80.0
var forca_pulo := 290.0
var dano := 10.0
var alcance := 100.0
var intervalo := 1.0
var velocidade_projetil := 200.0
var max_lacaios := 0
var mult_lacaio := 1.0
var flechas_extra := 0
var roubo_vida := 0.0
var raio_explosao := 0.0
## Ids das melhorias escolhidas (para reaplicar quando a Bola troca a classe)
var historico: Array[String] = []

## Classe cujo ataque está sendo usado (normalmente a própria; o item
## "ataque trocado" empresta o de outra por alguns segundos)
var ataque: ClasseDados

# Efeitos de item (duram EFEITO_DURACAO segundos; só um por vez)
const EFEITO_DURACAO := 10.0
const NOMES_EFEITO := {"pequeno": "ENCOLHEU", "grande": "GIGANTE", "gravidade": "GRAVIDADE INVERTIDA", "ataque": "ATAQUE TROCADO"}
var efeito := ""
var efeito_t := 0.0
var escala := 1.0
var gravidade_invertida := false
var mult_dano_efeito := 1.0
var mult_vel_efeito := 1.0
var mult_empurrao := 1.0

var nivel := 1
var xp := 0
## Fila de escolhas de melhoria pendentes; cada item é [opção1, opção2].
var escolhas: Array = []

var vivo := true
## Fica false durante a contagem regressiva e depois do fim da partida.
var ativo := false
var cooldown_porta := 0.0

var _cd_ataque := 0.6
var _coyote := 0.0
var _buffer := 0.0
var _descer := 0.0
var _anim := "parado"
var _anim_t := 0.0
var _flash := 0.0
var _sem_dano := 0.0


func configurar(n: int, d: ClasseDados, p: Node, c: Controle) -> void:
	numero = n
	equipe = n
	partida = p
	controle = c
	_aplicar_classe(d)


func _aplicar_classe(d: ClasseDados) -> void:
	var proporcao := vida / vida_max if dados != null else 1.0
	dados = d
	ataque = d
	vida_max = d.vida_max
	vida = vida_max * proporcao
	velocidade = d.velocidade
	forca_pulo = d.forca_pulo
	dano = d.dano
	alcance = d.alcance
	intervalo = d.intervalo_ataque
	velocidade_projetil = d.velocidade_projetil
	max_lacaios = d.max_lacaios
	if sprite != null:
		sprite.texture = d.textura_p1 if numero == 1 else d.textura_p2


func receber_classe(d: ClasseDados) -> void:
	## Recruta vira uma classe (chamado pela partida no nível 2).
	eh_recruta = false
	_aplicar_classe(d)
	curar(vida_max * 0.25)
	_cd_ataque = 0.4


func trocar_classe(d: ClasseDados) -> void:
	## Bola de troca: nova classe mantendo nível, vida proporcional e melhorias
	## (a melhoria especial da classe antiga vira a especial da nova).
	var proporcao := vida / vida_max
	_encerrar_efeito()
	flechas_extra = 0
	roubo_vida = 0.0
	raio_explosao = 0.0
	mult_lacaio = 1.0
	_aplicar_classe(d)
	var especial_novo: String = Melhorias.ESPECIAIS[d.tipo_ataque]["id"]
	var novos: Array[String] = []
	for id in historico:
		var novo_id: String = especial_novo if Melhorias.e_especial(id) else id
		Melhorias.aplicar(self, Melhorias.por_id(novo_id), false)
		novos.append(novo_id)
	historico = novos
	vida = vida_max * proporcao


# ------------------------------------------------------------------ Ataque atual

func atk_tipo() -> ClasseDados.TipoAtaque:
	return ataque.tipo_ataque


func _emprestado() -> bool:
	return ataque != dados


func atk_dano() -> float:
	return (ataque.dano if _emprestado() else dano) * mult_dano_efeito


func atk_alcance() -> float:
	return ataque.alcance if _emprestado() else alcance


func atk_intervalo() -> float:
	return ataque.intervalo_ataque if _emprestado() else intervalo


func atk_vel_projetil() -> float:
	return ataque.velocidade_projetil if _emprestado() else velocidade_projetil


func atk_max_lacaios() -> int:
	return 2 if _emprestado() else max_lacaios


# ------------------------------------------------------------------ Efeitos de item

func aplicar_efeito(nome: String) -> void:
	_encerrar_efeito()
	efeito = nome
	efeito_t = EFEITO_DURACAO
	match nome:
		"pequeno":
			escala = 0.6
			mult_vel_efeito = 1.2
			mult_dano_efeito = 0.75
		"grande":
			escala = 1.5
			mult_vel_efeito = 0.85
			mult_dano_efeito = 1.3
			mult_empurrao = 1.6
		"gravidade":
			gravidade_invertida = true
			velocity.y = -80.0
		"ataque":
			# Ataque sorteado, diferente do próprio
			var opcoes: Array[ClasseDados] = []
			for i in Jogo.CLASSES.size():
				var c := Jogo.dados_classe(i)
				if c.tipo_ataque != dados.tipo_ataque:
					opcoes.append(c)
			ataque = opcoes.pick_random()
			_cd_ataque = 0.2
	_atualizar_visual_efeito()


func _encerrar_efeito() -> void:
	if gravidade_invertida:
		velocity.y = 0.0
	efeito = ""
	efeito_t = 0.0
	escala = 1.0
	gravidade_invertida = false
	mult_dano_efeito = 1.0
	mult_vel_efeito = 1.0
	mult_empurrao = 1.0
	if dados != null:
		ataque = dados
	_atualizar_visual_efeito()


func _atualizar_visual_efeito() -> void:
	if sprite == null:
		return
	sprite.scale = Vector2.ONE * escala
	sprite.flip_v = gravidade_invertida
	# Mantém os pés no chão (ou no teto) quando o tamanho muda
	sprite.position.y = (8.0 - 8.0 * escala) * (-1.0 if gravidade_invertida else 1.0)


func nome_efeito() -> String:
	if efeito == "ataque":
		return "ATAQUE DE " + ataque.nome.to_upper()
	return NOMES_EFEITO.get(efeito, "")


func nome_jogador() -> String:
	## "VOCÊ" e "CPU" no modo solo; "P1" e "P2" no multijogador.
	if partida != null and partida.rede != "":
		return "VOCÊ" if numero == Rede.numero_local() else "AMIGO"
	if controle is ControleBot:
		return "CPU"
	return "VOCÊ" if Jogo.solo else "P%d" % numero


func _ready() -> void:
	add_to_group("alvo")
	add_to_group("viajante")
	sprite.texture = dados.textura_p1 if numero == 1 else dados.textura_p2
	sprite.flip_h = numero == 2


func _physics_process(delta: float) -> void:
	if not vivo:
		return

	if efeito != "":
		efeito_t -= delta
		if efeito_t <= 0.0:
			_encerrar_efeito()
	# Gravidade (pode estar invertida pelo item). A gravidade extra da classe
	# (ex.: Orc) vale só na descida: sobe como os outros, cai mais pesado.
	var sentido := -1.0 if gravidade_invertida else 1.0
	up_direction = Vector2.DOWN if gravidade_invertida else Vector2.UP
	if not is_on_floor():
		var caindo := velocity.y * sentido > 0.0
		var g := GRAVIDADE * (dados.mult_gravidade if caindo else 1.0)
		velocity.y = clampf(velocity.y + g * sentido * delta, -QUEDA_MAX, QUEDA_MAX)
		_coyote -= delta
	else:
		_coyote = TEMPO_COYOTE

	var dir := 0.0
	if ativo:
		controle.atualizar(self, delta)
		dir = controle.eixo
		_buffer -= delta
		if controle.pulo_apertou:
			_buffer = TEMPO_BUFFER
		if _buffer > 0.0 and _coyote > 0.0:
			velocity.y = -forca_pulo * sentido
			_buffer = 0.0
			_coyote = 0.0
			Jogo.tocar("pulo")
		if controle.pulo_soltou and velocity.y * sentido < 0.0:
			velocity.y *= 0.5
		if controle.descer_apertou and is_on_floor() and not gravidade_invertida:
			_atravessar_plataforma()
		_ler_escolhas()

	if _descer > 0.0:
		_descer -= delta
		if _descer <= 0.0:
			set_collision_mask_value(5, true)

	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * velocidade * mult_vel_efeito, dados.aceleracao * delta)
		sprite.flip_h = dir < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, dados.atrito * delta)

	var estava_no_ar := not is_on_floor()
	var queda := velocity.y * sentido
	move_and_slide()
	if estava_no_ar and is_on_floor() and queda > 200.0 and dados.pouso_pesado:
		partida.tremer(clampf(queda / 150.0, 1.0, 2.5))
		partida.criar_poeira(position + Vector2(0, 8))
	_animar(delta)

	if ativo:
		_cd_ataque -= delta
		if _cd_ataque <= 0.0:
			_tentar_atacar()

	_sem_dano += delta
	if _sem_dano > REGEN_ESPERA and vida < vida_max and not partida.morte_subita:
		curar(vida_max * REGEN_TAXA * delta)

	if _flash > 0.0:
		_flash -= delta
	sprite.modulate = Color(1, 0.35, 0.35) if _flash > 0.0 else Color.WHITE
	queue_redraw()


func _atravessar_plataforma() -> void:
	_descer = 0.25
	set_collision_mask_value(5, false)
	velocity.y = 40.0


# ------------------------------------------------------------------ Combate

func _tentar_atacar() -> void:
	if atk_tipo() == ClasseDados.TipoAtaque.INVOCAR:
		if partida.contar_lacaios(self) < atk_max_lacaios():
			partida.criar_lacaio(self)
			_cd_ataque = atk_intervalo()
		else:
			_cd_ataque = 0.3
		return

	var alvo = _escolher_alvo()
	if alvo == null:
		_cd_ataque = 0.05
		return
	_cd_ataque = atk_intervalo()
	var dir_alvo: Vector2 = (alvo.global_position - global_position).normalized()
	if absf(velocity.x) < 5.0:
		sprite.flip_h = dir_alvo.x < 0.0
	_investida(dir_alvo.x)

	match atk_tipo():
		ClasseDados.TipoAtaque.FLECHA:
			var n := 1 + (0 if _emprestado() else flechas_extra)
			for i in n:
				var ang := (i - (n - 1) / 2.0) * 0.12
				# Flechas extras (melhoria "Chuva") causam 60% do dano
				var d := atk_dano() * (1.0 if i == 0 else 0.6)
				partida.criar_projetil(self, global_position, dir_alvo.rotated(ang) * atk_vel_projetil(),
						d, atk_alcance() * 1.5, false)
			Jogo.tocar("flecha")
		ClasseDados.TipoAtaque.CORPO_A_CORPO:
			_golpear(dir_alvo.x)
		ClasseDados.TipoAtaque.MAGIA:
			partida.criar_projetil(self, global_position + dir_alvo * 4.0, dir_alvo * atk_vel_projetil(),
					atk_dano(), atk_alcance() * 1.3, true)
			Jogo.tocar("magia")


func _escolher_alvo():
	## Inimigo mais próximo dentro do alcance. Com classe, o jogador inimigo
	## tem prioridade; o Recruta prefere monstros.
	var melhor = null
	var melhor_d := INF
	var corpo_a_corpo := atk_tipo() == ClasseDados.TipoAtaque.CORPO_A_CORPO
	var alc := atk_alcance()
	for a in get_tree().get_nodes_in_group("alvo"):
		if a == self or not Jogo.hostis(self, a) or not a.esta_vivo():
			continue
		var dif: Vector2 = a.global_position - global_position
		var d := dif.length()
		if d > alc + (6.0 if corpo_a_corpo else 0.0):
			continue
		if corpo_a_corpo and absf(dif.y) > 18.0:
			continue
		if not corpo_a_corpo and not _linha_livre(a.global_position):
			continue
		if a is Lutador:
			d *= 3.0 if eh_recruta else 0.6
		if d < melhor_d:
			melhor_d = d
			melhor = a
	return melhor


func _linha_livre(destino: Vector2) -> bool:
	var consulta := PhysicsRayQueryParameters2D.create(global_position, destino, 1)
	return get_world_2d().direct_space_state.intersect_ray(consulta).is_empty()


func _golpear(lado: float) -> void:
	var s := signf(lado) if lado != 0.0 else (-1.0 if sprite.flip_h else 1.0)
	for a in get_tree().get_nodes_in_group("alvo"):
		if a == self or not Jogo.hostis(self, a) or not a.esta_vivo():
			continue
		var dif: Vector2 = a.global_position - global_position
		if absf(dif.y) <= 18.0 * escala and dif.x * s >= -6.0 and absf(dif.x) <= atk_alcance() * escala + 6.0:
			causar_dano(a, atk_dano())
			# O Orc arremessa lacaios para longe (abre caminho até o Rei)
			if a is Minion and a.dono != null and dados.resistencia_lacaios > 0.0:
				a.velocity = Vector2(s * 200.0, -140.0)
	partida.criar_corte(global_position + Vector2(s * 12.0, 0.0), s < 0.0)
	Jogo.tocar("espada")


func causar_dano(alvo, qtd: float, fonte := "") -> void:
	alvo.receber_dano(qtd, self, fonte)
	if roubo_vida > 0.0:
		curar(qtd * roubo_vida)


func _investida(lado: float) -> void:
	var tw := create_tween()
	tw.tween_property(sprite, "position:x", signf(lado) * 2.0, 0.05)
	tw.tween_property(sprite, "position:x", 0.0, 0.1)


func receber_dano(qtd: float, origem, fonte := "") -> void:
	## fonte: "" (golpe), "projetil" ou "lacaio"
	if not vivo:
		return
	var origem_valida: bool = origem != null and is_instance_valid(origem)
	if fonte == "lacaio":
		qtd *= 1.0 - dados.resistencia_lacaios  # Orc: pele grossa contra lacaios
	# Guarda real: com lacaios vivos, o Rei leva menos dano de projéteis
	if fonte == "projetil" and dados.tipo_ataque == ClasseDados.TipoAtaque.INVOCAR and partida.contar_lacaios(self) > 0:
		qtd *= GUARDA_REAL
	# Dano entre jogadores passa pelas regras da partida (Recruta, PvP, morte súbita)
	if origem_valida and origem is Lutador and origem != self:
		qtd *= partida.mult_pvp(origem, self)
	if qtd <= 0.0:
		return
	vida -= qtd
	_sem_dano = 0.0
	_flash = 0.12
	Jogo.tocar("acerto")
	var texto := str(roundi(qtd)) if qtd >= 1.0 else "%.1f" % qtd
	partida.mostrar_texto(global_position + Vector2(0, -12), texto, Color("ffcd75"))
	if origem_valida:
		var empurrao := 70.0 * (1.0 - dados.resistencia_empurrao)
		if origem is Lutador:
			empurrao *= origem.mult_empurrao
		velocity.x += signf(global_position.x - origem.global_position.x) * empurrao
	if vida <= 0.0:
		vida = 0.0
		_morrer()


func curar(qtd: float) -> void:
	vida = minf(vida + qtd, vida_max)


func _morrer() -> void:
	vivo = false
	ativo = false
	remove_from_group("viajante")
	Jogo.tocar("morte")
	sprite.frame = 7
	var tw := create_tween()
	tw.tween_property(sprite, "rotation", PI * 0.5 * (-1.0 if sprite.flip_h else 1.0), 0.3)
	tw.parallel().tween_property(sprite, "position:y", 4.0, 0.3)
	tw.tween_property(sprite, "modulate:a", 0.3, 0.6)
	queue_redraw()
	morreu.emit(self)


func esta_vivo() -> bool:
	return vivo


func hitbox() -> Rect2:
	# Acompanha o tamanho do item (o corpo que colide com as paredes não muda)
	var tam := Vector2(10, 14) * escala
	if gravidade_invertida:
		return Rect2(global_position + Vector2(-tam.x / 2.0, -8.0), tam)
	return Rect2(global_position + Vector2(-tam.x / 2.0, 8.0 - tam.y), tam)


# ------------------------------------------------------------------ Experiência

func xp_para_proximo() -> int:
	if eh_recruta:
		return XP_PARA_CLASSE
	return 4 + nivel * 2


func ganhar_xp(qtd: int) -> void:
	if not vivo:
		return
	# Quem está atrás em nível ganha 50% a mais (ajuda a alcançar o oponente)
	var outro: Lutador = partida.oponente(self)
	if outro.nivel > nivel:
		qtd = ceili(qtd * 1.5)
	xp += qtd
	while xp >= xp_para_proximo():
		xp -= xp_para_proximo()
		nivel += 1
		curar(vida_max * 0.15)
		Jogo.tocar("nivel")
		if eh_recruta:
			partida.sortear_classe(self)
		else:
			escolhas.append(Melhorias.sortear(self))
			partida.mostrar_texto(global_position + Vector2(0, -20), "NÍVEL %d!" % nivel, Color("a7f070"))


func _ler_escolhas() -> void:
	if controle.opcao >= 0:
		escolher_melhoria(controle.opcao)


func escolher_melhoria(op: int) -> void:
	if escolhas.is_empty():
		return
	var par: Array = escolhas.pop_front()
	var m: Dictionary = par[op]
	Melhorias.aplicar(self, m)
	partida.mostrar_texto(global_position + Vector2(0, -20), m["nome"], Color.WHITE)


# ------------------------------------------------------------------ Visual

func _animar(delta: float) -> void:
	var nova := "parado"
	if not is_on_floor():
		nova = "pulo" if velocity.y < 0.0 else "queda"
	elif absf(velocity.x) > 10.0:
		nova = "correr"
	if nova != _anim:
		_anim = nova
		_anim_t = 0.0
	_anim_t += delta
	var quadros: Array = QUADROS[_anim]
	var fps := 10.0 if _anim == "correr" else 2.0
	sprite.frame = quadros[int(_anim_t * fps) % quadros.size()]


func _draw() -> void:
	if not vivo:
		return
	var cor: Color = Jogo.COR_TIME[equipe]
	# Rótulo ("VOCÊ", "CPU", "P1"...), seta e barra de vida acima da cabeça
	var fonte := ThemeDB.fallback_font
	var rotulo := nome_jogador()
	var larg := fonte.get_string_size(rotulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	var acima := maxf(0.0, (escala - 1.0) * 16.0)  # sobe o rótulo quando está gigante
	draw_set_transform(Vector2(0, -acima))
	var pos := Vector2(-larg / 2.0, -21)
	draw_string_outline(fonte, pos, rotulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, 3, Color("1a1c2c"))
	draw_string(fonte, pos, rotulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, cor)
	draw_colored_polygon(PackedVector2Array([Vector2(-3, -19), Vector2(3, -19), Vector2(0, -16)]), cor)
	draw_rect(Rect2(-8, -14, 16, 3), Color("1a1c2c"))
	draw_rect(Rect2(-7, -13, 14.0 * vida / vida_max, 1), cor)
