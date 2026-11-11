extends Node2D
## Desenha as portas da arena. Portas com a mesma cor estão conectadas.

var portas: Array = []:
	set(valor):
		portas = valor
		queue_redraw()

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var pulso := 0.25 + 0.15 * sin(_t * 4.0)
	for porta in portas:
		var r: Rect2 = porta["abertura"]
		var cor: Color = porta["cor"]
		draw_rect(r, Color(cor, pulso))
		# Moldura colorida nas bordas do vão
		if porta["tipo"] == "teto":
			draw_rect(Rect2(r.position.x - 2, r.position.y, 2, r.size.y), cor)
			draw_rect(Rect2(r.end.x, r.position.y, 2, r.size.y), cor)
		else:
			draw_rect(Rect2(r.position.x, r.position.y - 2, r.size.x, 2), cor)
			draw_rect(Rect2(r.position.x, r.end.y, r.size.x, 2), cor)
