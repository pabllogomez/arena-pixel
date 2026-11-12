class_name Item
extends Node2D
## Item no mapa. Dois tipos:
##   "efeito" - orbe com "?" parado (flutuando); todos iguais por fora. O efeito
##              (encolher, gigante, gravidade invertida, ataque trocado) só é
##              sorteado na hora em que alguém pega.
##   "bola"   - bola com ↻ que voa por caminhos aleatórios, atravessando paredes;
##              quem encostar troca de classe.

const TEX_ITEM := preload("res://assets/sprites/item.png")
const TEX_BOLA := preload("res://assets/sprites/bola.png")
const EFEITOS := ["pequeno", "grande", "gravidade", "ataque"]
const RAIO_PEGAR := 12.0
const VELOCIDADE_BOLA := 45.0

var tipo := "efeito"
var duracao := 25.0
var velocity := Vector2.ZERO

var _t := 0.0
var _base := Vector2.ZERO
var _destino := Vector2.ZERO
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("item")
	_sprite = Sprite2D.new()
	_sprite.texture = TEX_BOLA if tipo == "bola" else TEX_ITEM
	_sprite.hframes = 2
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_sprite.material = m
	add_child(_sprite)
	_base = position
	_destino = position
	_t = randf() * 3.0


func chave_visual() -> String:
	return "bola" if tipo == "bola" else "item"


func _physics_process(delta: float) -> void:
	_t += delta
	duracao -= delta
	_sprite.frame = int(_t * 4.0) % 2
	# Pisca nos últimos segundos antes de sumir
	_sprite.visible = duracao > 3.0 or int(_t * 10.0) % 2 == 0
	if duracao <= 0.0:
		queue_free()
		return
	if tipo == "bola":
		_voar(delta)
	else:
		position = _base + Vector2(0, roundf(sin(_t * 3.0) * 2.0))


func _voar(delta: float) -> void:
	# Escolhe pontos aleatórios na arena e vai até eles, fazendo curvas suaves
	if position.distance_to(_destino) < 8.0:
		_destino = Vector2(randf_range(24.0, GeradorArena.LARGURA - 24.0),
				randf_range(24.0, GeradorArena.ALTURA - 32.0))
	var desejada := (_destino - position).normalized() * VELOCIDADE_BOLA
	velocity = velocity.lerp(desejada, 2.0 * delta)
	position += velocity * delta
	_sprite.rotation += delta * 3.0


func tocando(l: Lutador) -> bool:
	return l.vivo and l.hitbox().grow(RAIO_PEGAR * 0.5).has_point(position)
