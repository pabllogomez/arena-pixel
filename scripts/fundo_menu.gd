extends Control
## Fundo das telas de menu: a masmorra no escuro, com tochas acesas, brasas
## subindo e poeira no ar. Fica atrás de quem o adiciona como filho.

const TEX_FUNDO := preload("res://assets/sprites/fundo.png")
const TEX_TOCHA := preload("res://assets/sprites/tocha.png")
## Posição das tochas no desenho de 480x270
const TOCHAS := [Vector2(56, 78), Vector2(424, 78), Vector2(112, 182), Vector2(368, 182)]

var _t := 0.0
var _particulas: Particulas


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	show_behind_parent = true
	_particulas = Particulas.new()
	add_child(_particulas)


func _origem() -> Vector2:
	return ((size - Vector2(480, 270)) / 2.0).round()


func poeira(pos: Vector2) -> void:
	## Poeirinha (usada quando as letras do título caem no lugar).
	_particulas.fx("pouso", pos, 200.0)


func _process(delta: float) -> void:
	_t += delta
	var o := _origem()
	for p in TOCHAS:
		if randf() < delta * 3.0:
			_particulas.fx("brasa", o + p + Vector2(0, -5))
	# Poeira parada no ar, bem devagar
	if randf() < delta * 4.0:
		_particulas.emitir(Vector2(randf() * size.x, randf() * size.y), Vector2(randf_range(-4.0, 4.0), randf_range(-5.0, 1.0)),
				randf_range(2.0, 4.0), Particulas.POEIRA, 1)
	queue_redraw()


func _draw() -> void:
	var o := _origem()
	draw_rect(Rect2(Vector2.ZERO, size), Color("12111a"))
	draw_texture(TEX_FUNDO, o, Color(0.36, 0.34, 0.44))
	# Clarão das tochas em degraus (discos feitos de faixas, sem curva lisa)
	for i in TOCHAS.size():
		var p: Vector2 = o + TOCHAS[i]
		var tremula := 1.0 + 0.08 * sin(_t * 9.0 + i * 1.7) + 0.05 * sin(_t * 23.0 + i)
		for raio in [46.0, 34.0, 22.0]:
			_disco(p + Vector2(0, -4), roundf(raio * tremula), Color(1.0, 0.55, 0.25, 0.055))
		var quadro := int(_t * 8.0 + i) % 4
		draw_texture_rect_region(TEX_TOCHA, Rect2(p - Vector2(4, 8), Vector2(8, 16)), Rect2(quadro * 8, 0, 8, 16))
	# Escurece em cima e embaixo, em faixas
	for i in 4:
		var alt := 14.0 * (4 - i)
		draw_rect(Rect2(0, 0, size.x, alt), Color(0.04, 0.03, 0.07, 0.22))
		draw_rect(Rect2(0, size.y - alt, size.x, alt), Color(0.04, 0.03, 0.07, 0.22))


func _disco(c: Vector2, raio: float, cor: Color) -> void:
	var y := -raio
	while y < raio:
		var meia := roundf(sqrt(maxf(raio * raio - (y + 1.0) * (y + 1.0), 0.0)) / 2.0) * 2.0
		draw_rect(Rect2(c.x - meia, c.y + y, meia * 2.0, 2.0), cor)
		y += 2.0
