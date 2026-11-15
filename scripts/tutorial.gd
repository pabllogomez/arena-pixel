extends Control
## Tutorial dos controles de toque: aparece antes da primeira partida no
## celular (e em OPÇÕES > COMO JOGAR). Um toque fecha.
##   metade esquerda: arrastar o dedo anda (puxar para baixo desce)
##   metade direita: tocar pula

signal fechado

## Em rede o tutorial não segura o jogo: some sozinho quando a contagem acaba
var partida: Node

var _t := 0.0
var _tex: Texture2D


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_tex = Jogo.dados_recruta().textura_p1


func _fechar() -> void:
	if is_queued_for_deletion():
		return
	Jogo.tocar("nivel")
	fechado.emit()
	queue_free()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _t > 0.4:
		accept_event()
		_fechar()


func _process(delta: float) -> void:
	_t += delta / maxf(Engine.time_scale, 0.05)
	if _t > 0.4 and (Input.is_action_just_pressed("menu_ok") or Input.is_action_just_pressed("menu_voltar")):
		_fechar()
	elif partida != null and is_instance_valid(partida) and partida.rede != "" and partida.contagem <= 0.0:
		_fechar()
	queue_redraw()


func _dedo(c: Vector2, apertado: bool) -> void:
	## Marca de dedo: disco em degraus com um anel em volta quando encosta.
	c = c.round()
	var cor := Color(UI.BRANCO, 0.9 if apertado else 0.45)
	for dy in range(-4, 5):
		var meia := roundf(sqrt(20.0 - dy * dy))
		draw_rect(Rect2(c.x - meia, c.y + dy, meia * 2.0, 1), cor)
	if apertado:
		for i in 12:
			var p := c + Vector2.from_angle(TAU * i / 12.0) * 9.0
			draw_rect(Rect2(p.round(), Vector2.ONE), UI.OURO)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(UI.TINTA, 0.94))
	var cx := roundf(size.x / 2.0)
	var cy := roundf(size.y / 2.0)
	UI.texto(self, Vector2(cx, cy - 112), "COMO JOGAR", UI.G, UI.OURO)
	# Linha pontilhada separando as duas metades
	var y := cy - 86.0
	while y < cy + 70.0:
		draw_rect(Rect2(cx, y, 1, 3), UI.BORDA)
		y += 6.0

	# ---- Metade esquerda: arrastar anda
	var ex := roundf(size.x * 0.25)
	UI.texto(self, Vector2(ex, cy - 74), "LADO ESQUERDO", UI.P, UI.BORDA)
	UI.texto(self, Vector2(ex, cy - 56), "ARRASTE", UI.M, Color("41a6f6"))
	UI.texto(self, Vector2(ex, cy - 40), "o dedo para andar", UI.P, UI.LUZ)
	var vai := sin(_t * 2.4)
	var chao := cy + 4.0
	draw_rect(Rect2(ex - 70, chao, 140, 1), UI.BORDA)
	var px := ex + roundf(vai * 46.0)
	var quadro: int = Lutador.quadro_de("correr", _t)
	var tq := float(Lutador.TAM_QUADRO)
	var destino := Rect2(px - tq / 2.0, chao - tq, tq, tq)
	if cos(_t * 2.4) < 0.0:
		destino = Rect2(px + tq / 2.0, chao - tq, -tq, tq)
	draw_texture_rect_region(_tex, destino, Rect2(quadro * Lutador.TAM_QUADRO, 0, Lutador.TAM_QUADRO, Lutador.TAM_QUADRO))
	# O dedo arrastando embaixo, com setas para os lados
	var dy0 := cy + 30.0
	UI.seta(self, Vector2(ex - 34, dy0), -1.0, UI.BORDA)
	UI.seta(self, Vector2(ex + 34, dy0), 1.0, UI.BORDA)
	draw_rect(Rect2(ex - 26, dy0, 52, 1), UI.APAGADO)
	_dedo(Vector2(ex + vai * 22.0, dy0), true)
	UI.texto(self, Vector2(ex, cy + 54), "Puxe para baixo: desce da plataforma", UI.P, UI.BORDA)

	# ---- Metade direita: tocar pula
	var dx := roundf(size.x * 0.75)
	UI.texto(self, Vector2(dx, cy - 74), "LADO DIREITO", UI.P, UI.BORDA)
	UI.texto(self, Vector2(dx, cy - 56), "TOQUE", UI.M, Color("ef7d57"))
	UI.texto(self, Vector2(dx, cy - 40), "em qualquer ponto para pular", UI.P, UI.LUZ)
	draw_rect(Rect2(dx - 70, chao, 140, 1), UI.BORDA)
	var ciclo := fmod(_t, 1.2)
	var no_ar := ciclo < 0.6
	var altura := 0.0
	if no_ar:
		var u := ciclo / 0.6
		altura = roundf(4.0 * 26.0 * u * (1.0 - u))
	var q: int = Lutador.QUADROS["parado"][0]
	if no_ar:
		q = Lutador.QUADROS["pulo"][0] if ciclo < 0.3 else Lutador.QUADROS["queda"][0]
	draw_texture_rect_region(_tex, Rect2(dx - Lutador.TAM_QUADRO / 2.0, chao - Lutador.TAM_QUADRO - altura, Lutador.TAM_QUADRO, Lutador.TAM_QUADRO),
			Rect2(q * Lutador.TAM_QUADRO, 0, Lutador.TAM_QUADRO, Lutador.TAM_QUADRO))
	_dedo(Vector2(dx, dy0), ciclo < 0.18)
	UI.texto(self, Vector2(dx, cy + 54), "Segure para pular mais alto", UI.P, UI.BORDA)
	UI.texto(self, Vector2(dx, cy + 66), "Arraste rápido para o lado: dash", UI.P, UI.BORDA)

	# ---- Rodapé
	UI.texto(self, Vector2(cx, cy + 84), "O ataque é automático. As melhorias aparecem em cartas: toque na carta.", UI.P, UI.LUZ)
	if Jogo.tem_controle():
		UI.texto(self, Vector2(cx, cy + 96), "Controle: A pula, B dash, LB/RB melhorias", UI.P, UI.OURO)
	if int(_t * 2.0) % 2 == 0 or _t < 0.4:
		UI.texto(self, Vector2(cx, cy + 108), "TOQUE PARA COMEÇAR" if partida != null else "TOQUE PARA FECHAR", UI.M, UI.VERDE)
