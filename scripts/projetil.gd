class_name Projetil
extends Node2D
## Flecha ou orbe mágico. Também atravessa as portas da arena.
## Orbes perdem força conforme viajam: acertar de perto dói mais.

const TEX_FLECHA := preload("res://assets/sprites/flecha.png")
const TEX_ORBE := preload("res://assets/sprites/orbe.png")

var velocity := Vector2.ZERO
var equipe := 0
var dono = null
var partida: Node
var dano := 5.0
var alcance_max := 200.0
var magia := false
var dano_min := 0.25
var raio_explosao := 0.0
var cooldown_porta := 0.0

var _percorrido := 0.0
var _t := 0.0
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("viajante")
	_sprite = Sprite2D.new()
	if magia:
		_sprite.texture = TEX_ORBE
		_sprite.hframes = 2
	else:
		_sprite.texture = TEX_FLECHA
	add_child(_sprite)


func _fracao() -> float:
	return clampf(_percorrido / alcance_max, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	_t += delta
	var passo := velocity * delta
	var consulta := PhysicsRayQueryParameters2D.create(global_position, global_position + passo, 1)
	if not get_world_2d().direct_space_state.intersect_ray(consulta).is_empty():
		queue_free()
		return
	position += passo
	_percorrido += passo.length()

	if magia:
		_sprite.frame = int(_t * 10.0) % 2
		_sprite.scale = Vector2.ONE * lerpf(1.25, 0.55, _fracao())
	else:
		rotation = velocity.angle()

	for a in get_tree().get_nodes_in_group("alvo"):
		if Jogo.hostis(self, a) and a.esta_vivo() and a.hitbox().grow(2.0).has_point(global_position):
			_acertar(a)
			return

	if _percorrido >= alcance_max:
		queue_free()


func _acertar(alvo) -> void:
	var d := dano
	if magia:
		d = dano * lerpf(1.0, dano_min, _fracao())
	_ferir(alvo, d)
	if raio_explosao > 0.0:
		for a in get_tree().get_nodes_in_group("alvo"):
			if a != alvo and Jogo.hostis(self, a) and a.esta_vivo() \
					and a.global_position.distance_to(global_position) <= raio_explosao:
				_ferir(a, d * 0.5)
		partida.criar_brilho(global_position)
	queue_free()


func _ferir(alvo, qtd: float) -> void:
	if dono != null and is_instance_valid(dono):
		dono.causar_dano(alvo, qtd)
	else:
		alvo.receber_dano(qtd, null)
