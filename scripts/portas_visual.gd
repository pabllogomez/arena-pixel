extends Node2D
## Desenha as portas da arena. Todas iguais: ninguém sabe para onde cada uma
## leva até entrar. Na Morte Súbita elas aparecem fechadas (riscadas).

var portas: Array = []:
	set(valor):
		portas = valor
		queue_redraw()
var fechadas := false

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var pulso := 0.35 + 0.1 * sin(_t * 2.0)
	for porta in portas:
		var r: Rect2 = porta["abertura"]
		var cor := Color(0.42, 0.40, 0.46)  # moldura de pedra, igual para todas
		if fechadas:
			cor = Color(cor, 0.5)
			draw_line(r.position, r.end, Color("b13e53"), 2.0)
			draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color("b13e53"), 2.0)
		else:
			draw_rect(r, Color(0.02, 0.02, 0.04, pulso + 0.3))  # escuridão do túnel
		# Moldura colorida nas bordas do vão
		if porta["tipo"] == "teto":
			draw_rect(Rect2(r.position.x - 2, r.position.y, 2, r.size.y), cor)
			draw_rect(Rect2(r.end.x, r.position.y, 2, r.size.y), cor)
		else:
			draw_rect(Rect2(r.position.x, r.position.y - 2, r.size.x, 2), cor)
			draw_rect(Rect2(r.position.x, r.end.y, r.size.x, 2), cor)
