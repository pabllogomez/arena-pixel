class_name Lutador
extends CharacterBody2D
## Personagem controlado por um jogador. Anda, pula e ataca sozinho
## quando um inimigo entra no alcance.

signal morreu(lutador: Lutador)

const GRAVIDADE := 700.0
const QUEDA_MAX := 360.0
const ACELERACAO := 1000.0
const ATRITO := 1200.0
const TEMPO_COYOTE := 0.1
const TEMPO_BUFFER := 0.12
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

# Atributos atuais (começam iguais aos da classe e crescem com as melhorias)
var vida_max := 100.0
var vida := 100.0
var velocidade := 80.0
var forca_pulo := 290.0
var dano := 10.0
var alcance := 100.0
var intervalo := 1.0
var max_lacaios := 0
var mult_lacaio := 1.0
var flechas_extra := 0
var roubo_vida := 0.0
var raio_explosao := 0.0

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


func configurar(n: int, d: ClasseDados, p: Node) -> void:
	numero = n
	equipe = n
	dados = d
	partida = p
	vida_max = d.vida_max
	vida = vida_max
	velocidade = d.velocidade
	forca_pulo = d.forca_pulo
	dano = d.dano
	alcance = d.alcance
	intervalo = d.intervalo_ataque
	max_lacaios = d.max_lacaios


func _ready() -> void:
	add_to_group("alvo")
	add_to_group("viajante")
	sprite.texture = dados.textura_p1 if numero == 1 else dados.textura_p2
	sprite.flip_h = numero == 2


func _a(nome: String) -> String:
	return Jogo.acao(numero, nome)


func _physics_process(delta: float) -> void:
	if not vivo:
		return

	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVIDADE * delta, QUEDA_MAX)
		_coyote -= delta
	else:
		_coyote = TEMPO_COYOTE

	var dir := 0.0
	if ativo:
		dir = Input.get_axis(_a("esquerda"), _a("direita"))
		_buffer -= delta
		if Input.is_action_just_pressed(_a("pular")):
			_buffer = TEMPO_BUFFER
		if _buffer > 0.0 and _coyote > 0.0:
			velocity.y = -forca_pulo
			_buffer = 0.0
			_coyote = 0.0
			Jogo.tocar("pulo")
		if Input.is_action_just_released(_a("pular")) and velocity.y < 0.0:
			velocity.y *= 0.5
		if Input.is_action_just_pressed(_a("descer")) and is_on_floor():
			_atravessar_plataforma()
		_ler_escolhas()

	if _descer > 0.0:
		_descer -= delta
		if _descer <= 0.0:
			set_collision_mask_value(5, true)

	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * velocidade, ACELERACAO * delta)
		sprite.flip_h = dir < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, ATRITO * delta)

	move_and_slide()
	_animar(delta)

	if ativo:
		_cd_ataque -= delta
		if _cd_ataque <= 0.0:
			_tentar_atacar()

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
	if dados.tipo_ataque == ClasseDados.TipoAtaque.INVOCAR:
		if partida.contar_lacaios(self) < max_lacaios:
			partida.criar_lacaio(self)
			_cd_ataque = intervalo
		else:
			_cd_ataque = 0.3
		return

	var alvo = _escolher_alvo()
	if alvo == null:
		_cd_ataque = 0.05
		return
	_cd_ataque = intervalo
	var dir_alvo: Vector2 = (alvo.global_position - global_position).normalized()
	if absf(velocity.x) < 5.0:
		sprite.flip_h = dir_alvo.x < 0.0
	_investida(dir_alvo.x)

	match dados.tipo_ataque:
		ClasseDados.TipoAtaque.FLECHA:
			var n := 1 + flechas_extra
			for i in n:
				var ang := (i - (n - 1) / 2.0) * 0.12
				partida.criar_projetil(self, global_position, dir_alvo.rotated(ang) * dados.velocidade_projetil,
						dano, alcance * 1.5, false)
			Jogo.tocar("flecha")
		ClasseDados.TipoAtaque.CORPO_A_CORPO:
			_golpear(dir_alvo.x)
		ClasseDados.TipoAtaque.MAGIA:
			partida.criar_projetil(self, global_position + dir_alvo * 4.0, dir_alvo * dados.velocidade_projetil,
					dano, alcance * 1.3, true)
			Jogo.tocar("magia")


func _escolher_alvo():
	## Inimigo mais próximo dentro do alcance (jogador inimigo tem prioridade).
	var melhor = null
	var melhor_d := INF
	var corpo_a_corpo := dados.tipo_ataque == ClasseDados.TipoAtaque.CORPO_A_CORPO
	for a in get_tree().get_nodes_in_group("alvo"):
		if a == self or not Jogo.hostis(self, a) or not a.esta_vivo():
			continue
		var dif: Vector2 = a.global_position - global_position
		var d := dif.length()
		if d > alcance + (6.0 if corpo_a_corpo else 0.0):
			continue
		if corpo_a_corpo and absf(dif.y) > 18.0:
			continue
		if not corpo_a_corpo and not _linha_livre(a.global_position):
			continue
		if a is Lutador:
			d *= 0.6
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
		if absf(dif.y) <= 18.0 and dif.x * s >= -6.0 and absf(dif.x) <= alcance + 6.0:
			causar_dano(a, dano)
	partida.criar_corte(global_position + Vector2(s * 12.0, 0.0), s < 0.0)
	Jogo.tocar("espada")


func causar_dano(alvo, qtd: float) -> void:
	alvo.receber_dano(qtd, self)
	if roubo_vida > 0.0:
		curar(qtd * roubo_vida)


func _investida(lado: float) -> void:
	var tw := create_tween()
	tw.tween_property(sprite, "position:x", signf(lado) * 2.0, 0.05)
	tw.tween_property(sprite, "position:x", 0.0, 0.1)


func receber_dano(qtd: float, origem) -> void:
	if not vivo:
		return
	vida -= qtd
	_flash = 0.12
	Jogo.tocar("acerto")
	partida.mostrar_texto(global_position + Vector2(0, -12), str(roundi(qtd)), Color("ffcd75"))
	if origem != null and is_instance_valid(origem):
		velocity.x += signf(global_position.x - origem.global_position.x) * 70.0
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
	return Rect2(global_position + Vector2(-5, -6), Vector2(10, 14))


# ------------------------------------------------------------------ Experiência

func xp_para_proximo() -> int:
	return 5 + nivel * 3


func ganhar_xp(qtd: int) -> void:
	if not vivo:
		return
	xp += qtd
	while xp >= xp_para_proximo():
		xp -= xp_para_proximo()
		nivel += 1
		curar(vida_max * 0.15)
		escolhas.append(Melhorias.sortear(self))
		Jogo.tocar("nivel")
		partida.mostrar_texto(global_position + Vector2(0, -20), "NÍVEL %d!" % nivel, Color("a7f070"))


func _ler_escolhas() -> void:
	if escolhas.is_empty():
		return
	var op := -1
	if Input.is_action_just_pressed(_a("opcao1")):
		op = 0
	elif Input.is_action_just_pressed(_a("opcao2")):
		op = 1
	if op >= 0:
		var par: Array = escolhas.pop_front()
		Melhorias.aplicar(self, par[op])
		partida.mostrar_texto(global_position + Vector2(0, -20), par[op]["nome"], Color.WHITE)


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
	# Marcador do jogador e barra de vida acima da cabeça
	draw_colored_polygon(PackedVector2Array([Vector2(-3, -19), Vector2(3, -19), Vector2(0, -16)]), cor)
	draw_rect(Rect2(-8, -14, 16, 3), Color("1a1c2c"))
	draw_rect(Rect2(-7, -13, 14.0 * vida / vida_max, 1), cor)
