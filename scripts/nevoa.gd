extends Node2D
## Fumaça tóxica da Morte Súbita: sobe do chão e machuca quem estiver dentro.

var partida: Node
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if partida != null and partida.morte_subita:
		queue_redraw()


func _draw() -> void:
	if partida == null or not partida.morte_subita:
		return
	var topo: float = partida.nivel_nevoa
	var larg := float(GeradorArena.LARGURA)
	var base := float(GeradorArena.ALTURA)
	if topo >= base:
		return
	draw_rect(Rect2(0, topo + 4, larg, base - topo), Color(0.36, 0.72, 0.25, 0.42))
	# Borda ondulada
	var pontos := PackedVector2Array()
	for x in range(0, int(larg) + 8, 8):
		pontos.append(Vector2(x, topo + 2.0 * sin(_t * 3.0 + x * 0.15)))
	pontos.append(Vector2(larg, topo + 4))
	pontos.append(Vector2(0, topo + 4))
	draw_colored_polygon(pontos, Color(0.65, 0.94, 0.44, 0.55))
	# Bolhas
	for i in 14:
		var bx := fmod(i * 53.0 + _t * 9.0 * (1 + i % 3), larg)
		var by := topo + 10.0 + fmod(i * 37.0 + _t * 14.0, maxf(base - topo, 1.0))
		draw_rect(Rect2(bx, by, 2, 2), Color(0.8, 1.0, 0.6, 0.5))
