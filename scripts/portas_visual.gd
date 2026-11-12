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
			_desenhar_corrente(porta, r)
		# Moldura colorida nas bordas do vão
		if porta["tipo"] == "teto":
			draw_rect(Rect2(r.position.x - 2, r.position.y, 2, r.size.y), cor)
			draw_rect(Rect2(r.end.x, r.position.y, 2, r.size.y), cor)
		else:
			draw_rect(Rect2(r.position.x, r.position.y - 2, r.size.x, 2), cor)
			draw_rect(Rect2(r.position.x, r.end.y, r.size.x, 2), cor)


func _desenhar_corrente(porta: Dictionary, r: Rect2) -> void:
	## Pixels sendo puxados para dentro do túnel: mostra que a porta está aberta.
	var normal: Vector2 = porta["normal"]
	var lado := Vector2(-normal.y, normal.x)
	var fundo := absf(r.size.x * normal.x) + absf(r.size.y * normal.y)
	var largura := absf(r.size.x * lado.x) + absf(r.size.y * lado.y)
	var centro := r.get_center()
	for i in 7:
		var u := fmod(_t * 0.55 + i * 0.143, 1.0)  # 0 = boca da porta, 1 = fundo do túnel
		var abre := (largura / 2.0 - 2.0) * (1.0 - u)
		var p := centro + normal * (0.5 - u) * fundo + lado * sin(i * 2.4 + _t * 2.0) * abre
		if u > 0.85 and int(_t * 20.0 + i) % 2 == 0:
			continue
		var cor := Color("73eff7") if i % 2 == 0 else Color("41a6f6")
		draw_rect(Rect2(p.floor(), Vector2.ONE), Color(cor, 0.9 - 0.5 * u))
