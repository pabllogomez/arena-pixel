class_name Minion
extends CharacterBody2D
## Criatura controlada pela IA. Usada para:
##  - lacaios do Rei (equipe do Rei, caçam qualquer inimigo pela arena);
##  - monstros neutros (equipe 0, patrulham e atacam quem chegar perto).
## Quem dá o golpe final ganha a experiência (lacaios dão XP ao seu Rei).

const GRAVIDADE := 700.0
const FORCA_PULO := 295.0
const ALCANCE_ATAQUE := 14.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var sensor_chao: RayCast2D = $SensorChao

var equipe := 0
var dono = null
var partida: Node
var textura: Texture2D
var vida_max := 20.0
var vida := 20.0
var dano := 5.0
var velocidade := 40.0
var visao := 70.0
var xp_valor := 3
var intervalo_ataque := 0.9
## Defensivo: só persegue quem o atacou ou quem chegou bem perto
var defensivo := false
var _provocado := false
const VISAO_DEFENSIVA := 22.0
## Quem mata um monstro recupera esta fração da vida máxima
const CURA_POR_ABATE := 0.08
## Lacaios do Rei também arremessam lanças (0 = não arremessa)
var alcance_arremesso := 0.0
var _cd_arremesso := 1.0
var vivo := true
var cooldown_porta := 0.0

var _dir := 1.0
var _cd := 0.6
var _pulo_cd := 0.0
var _descer := 0.0
var _t := 0.0
var _flash := 0.0
var _seguidor: SeguidorCaminho   # só lacaios do Rei usam caminhos
var _t_caminho := 0.0


func configurar(p: Node, p_equipe: int, p_dono, tex: Texture2D, p_vida: float, p_dano: float,
		p_velocidade: float, p_visao: float, p_xp: int) -> void:
	partida = p
	equipe = p_equipe
	dono = p_dono
	textura = tex
	vida_max = p_vida
	vida = p_vida
	dano = p_dano
	velocidade = p_velocidade
	visao = p_visao
	xp_valor = p_xp
	_dir = -1.0 if randf() < 0.5 else 1.0


func _ready() -> void:
	add_to_group("alvo")
	add_to_group("viajante")
	sprite.texture = textura


func _physics_process(delta: float) -> void:
	if not vivo:
		return
	_t += delta
	_cd -= delta
	_pulo_cd -= delta
	_cd_arremesso -= delta

	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVIDADE * delta, 360.0)

	var alvo = _procurar_alvo()
	if alvo != null and alcance_arremesso > 0.0 and _cd_arremesso <= 0.0:
		_tentar_arremessar(alvo)
	var mover := _dir
	_passo_caminho = {}
	if alvo != null and dono != null and _seguir_caminho(alvo, delta):
		pass  # lacaio indo até o alvo por um caminho
	elif alvo != null:
		var dif: Vector2 = alvo.global_position - global_position
		if absf(dif.x) > 4.0:
			_dir = signf(dif.x)
		mover = _dir
		if absf(dif.x) <= ALCANCE_ATAQUE and absf(dif.y) <= 14.0:
			mover = 0.0
			if _cd <= 0.0:
				_atacar(alvo)
		elif is_on_floor():
			if dif.y < -24.0 and absf(dif.x) < 72.0 and _pulo_cd <= 0.0:
				_pular()
			elif dif.y > 24.0 and absf(dif.x) < 56.0 and _descer <= 0.0:
				_descer = 0.3
				set_collision_mask_value(5, false)
	elif is_on_floor() and not sensor_chao.is_colliding():
		_dir *= -1.0  # patrulha: vira na beirada
		mover = _dir

	if is_on_floor() and is_on_wall():
		if alvo != null and _pulo_cd <= 0.0:
			_pular()
		elif alvo == null:
			_dir *= -1.0
			mover = _dir

	if _descer > 0.0:
		_descer -= delta
		if _descer <= 0.0:
			set_collision_mask_value(5, true)

	if _passo_caminho.size() > 0:
		mover = _passo_caminho["eixo"]
		if _passo_caminho["pular"] and is_on_floor() and _pulo_cd <= 0.0:
			_pular()
		if _passo_caminho["descer"] and is_on_floor() and _descer <= 0.0:
			_descer = 0.3
			set_collision_mask_value(5, false)
		if mover != 0.0:
			_dir = mover
	velocity.x = mover * velocidade
	move_and_slide()

	sensor_chao.position.x = 6.0 * _dir
	sprite.flip_h = _dir < 0.0
	sprite.frame = int(_t * 5.0) % 2 if absf(velocity.x) > 1.0 else 0
	if _flash > 0.0:
		_flash -= delta
	sprite.modulate = Color(1, 0.35, 0.35) if _flash > 0.0 else Color.WHITE
	queue_redraw()


var _passo_caminho := {}


func _seguir_caminho(alvo, delta: float) -> bool:
	## Lacaios usam a navegação para caçar alvos longe ou em outro andar.
	## Retorna false quando o alvo está perto (aí o ataque normal assume).
	_passo_caminho = {}
	var dif: Vector2 = alvo.global_position - global_position
	if absf(dif.y) <= 14.0 and absf(dif.x) <= 48.0:
		return false
	if _seguidor == null:
		_seguidor = SeguidorCaminho.new(partida.nav)
	_t_caminho -= delta
	if (_t_caminho <= 0.0 or _seguidor.replanejar) and is_on_floor():
		_t_caminho = 0.5
		var nav: Navegacao = partida.nav
		var meu_no := nav.no_de_posicao(position)
		if meu_no != Navegacao.INVALIDO:
			_seguidor.ir_para(meu_no, nav.no_mais_proximo(alvo.position))
	if _seguidor.chegou():
		return false
	_passo_caminho = _seguidor.passo(self, delta)
	return true


func _procurar_alvo():
	var melhor = null
	var melhor_d := visao if (not defensivo or _provocado) else VISAO_DEFENSIVA
	for a in get_tree().get_nodes_in_group("alvo"):
		if a == self or not Jogo.hostis(self, a) or not a.esta_vivo():
			continue
		var d: float = global_position.distance_to(a.global_position)
		if d < melhor_d:
			melhor_d = d
			melhor = a
	return melhor


func _tentar_arremessar(alvo) -> void:
	## De longe (mas não colado), arremessa uma lança se a linha estiver livre.
	var d: float = global_position.distance_to(alvo.global_position)
	if d < 24.0 or d > alcance_arremesso:
		return
	var consulta := PhysicsRayQueryParameters2D.create(global_position, alvo.global_position, 1)
	if not get_world_2d().direct_space_state.intersect_ray(consulta).is_empty():
		return
	_cd_arremesso = intervalo_ataque * 1.6
	_dir = signf(alvo.global_position.x - global_position.x)
	partida.criar_lanca(self, alvo)


func _pular() -> void:
	velocity.y = -FORCA_PULO
	_pulo_cd = 0.6


func _atacar(alvo) -> void:
	_cd = intervalo_ataque
	alvo.receber_dano(dano, _origem())
	var tw := create_tween()
	tw.tween_property(sprite, "position:x", _dir * 3.0, 0.05)
	tw.tween_property(sprite, "position:x", 0.0, 0.1)


func _origem():
	## Quem leva o crédito pelos golpes deste minion.
	if dono != null and is_instance_valid(dono):
		return dono
	return self


func receber_dano(qtd: float, origem) -> void:
	if not vivo:
		return
	vida -= qtd
	_flash = 0.12
	_provocado = true
	Jogo.tocar("acerto")
	if vida <= 0.0:
		_morrer(origem)


func ganhar_xp(_qtd: int) -> void:
	pass  # monstros neutros não evoluem


func _morrer(origem) -> void:
	vivo = false
	remove_from_group("alvo")
	remove_from_group("viajante")
	if origem != null and is_instance_valid(origem) and origem != self:
		var xp_antes: int = origem.xp if origem is Lutador else 0
		var nivel_antes: int = origem.nivel if origem is Lutador else 0
		origem.ganhar_xp(xp_valor)
		if origem is Lutador and equipe == 0:
			origem.curar(origem.vida_max * CURA_POR_ABATE)
		if origem is Lutador:
			var ganho := xp_valor
			if origem.nivel == nivel_antes:
				ganho = origem.xp - xp_antes
			partida.mostrar_texto(global_position + Vector2(0, -10), "+%d XP" % ganho, Color("a7f070"))
	$CollisionShape2D.set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector2(1.4, 0.3), 0.1)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)


func esta_vivo() -> bool:
	return vivo


func hitbox() -> Rect2:
	return Rect2(global_position + Vector2(-5, -2), Vector2(10, 10))


func _draw() -> void:
	if not vivo or vida >= vida_max:
		return
	draw_rect(Rect2(-6, -9, 12, 3), Color("1a1c2c"))
	draw_rect(Rect2(-5, -8, 10.0 * vida / vida_max, 1), Jogo.COR_TIME[equipe])
