extends Control
## Menu inicial: modo de jogo (1 ou 2 jogadores) e dificuldade do bot.

signal jogar

const MODOS := ["1 JOGADOR", "2 JOGADORES"]
const DIFICULDADES := ["FÁCIL", "NORMAL", "DIFÍCIL"]

var _tela := "modo"  # "modo" ou "dificuldade"
var _sel := 0
var _t := 0.0
var _texturas: Array[Texture2D] = []


func _ready() -> void:
	_sel = 0 if Jogo.solo else 1
	for c in Jogo.CLASSES:
		_texturas.append(load("res://assets/sprites/%s_1.png" % c))


func _gui_input(event: InputEvent) -> void:
	# Toque ou clique: escolhe a opção tocada (o toque vira clique automaticamente)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = event.position
		if _tela == "dificuldade" and Rect2(4, 4, 60, 18).has_point(pos):
			_tela = "modo"
			_sel = 0
			return
		var opcoes := MODOS if _tela == "modo" else DIFICULDADES
		for i in opcoes.size():
			if Rect2(size.x / 2.0 - 80, 104.0 + i * 18.0 - 9, 160, 18).has_point(pos):
				_sel = i
				_confirmar()


func _confirmar() -> void:
	Jogo.tocar("nivel")
	if _tela == "modo":
		Jogo.solo = _sel == 0
		if Jogo.solo:
			_tela = "dificuldade"
			_sel = Jogo.dificuldade
		else:
			jogar.emit()
	else:
		Jogo.dificuldade = _sel
		jogar.emit()


func _process(delta: float) -> void:
	_t += delta
	var opcoes := MODOS if _tela == "modo" else DIFICULDADES
	if Input.is_action_just_pressed("menu_cima"):
		_sel = wrapi(_sel - 1, 0, opcoes.size())
		Jogo.tocar("pulo")
	elif Input.is_action_just_pressed("menu_baixo"):
		_sel = wrapi(_sel + 1, 0, opcoes.size())
		Jogo.tocar("pulo")
	elif Input.is_action_just_pressed("menu_ok"):
		_confirmar()
	elif Input.is_action_just_pressed("menu_voltar") and _tela == "dificuldade":
		_tela = "modo"
		_sel = 0
	queue_redraw()


func _draw() -> void:
	var fonte := ThemeDB.fallback_font
	var cx := size.x / 2.0
	draw_rect(Rect2(Vector2.ZERO, size), Color("1a1c2c"))
	_centro(fonte, Vector2(cx, 22), "ARENA PIXEL", 24, Color("ffcd75"))
	_centro(fonte, Vector2(cx, 38), "Comece como Recruta. Cace monstros. Ganhe uma classe. Vença!", 8, Color("94b0c2"))

	# Classes que podem ser sorteadas
	var n := _texturas.size()
	for i in n:
		var x := cx + (i - (n - 1) / 2.0) * 40.0
		var quadro := 2 + int(_t * 8.0 + i) % 4
		draw_texture_rect_region(_texturas[i], Rect2(x - 12, 48, 24, 24), Rect2(quadro * 16, 0, 16, 16))

	var titulo := "MODO DE JOGO" if _tela == "modo" else "DIFICULDADE DA MÁQUINA"
	_centro(fonte, Vector2(cx, 88), titulo, 8, Color("566c86"))
	var opcoes := MODOS if _tela == "modo" else DIFICULDADES
	for i in opcoes.size():
		var y := 104.0 + i * 18.0
		var sel := i == _sel
		if sel:
			draw_rect(Rect2(cx - 70, y - 8, 140, 16), Color("333c57"))
			_centro(fonte, Vector2(cx - 60, y), ">", 12, Color("ffcd75"))
		_centro(fonte, Vector2(cx, y), opcoes[i], 12, Color.WHITE if sel else Color("94b0c2"))

	if _tela == "dificuldade":
		_centro(fonte, Vector2(30, 12), "< voltar", 8, Color("94b0c2"))
	if Jogo.toque:
		_centro(fonte, Vector2(cx, 166), "Toque em uma opção", 8, Color("566c86"))
		_centro(fonte, Vector2(cx, 184), "Joystick: dedo na esquerda · pulo na direita · toque nas melhorias", 8, Color("41a6f6"))
		_centro(fonte, Vector2(cx, 208), "O ataque é automático. Partidas de 3 minutos + Morte Súbita.", 8, Color("566c86"))
		return
	var ajuda := "W/S ou ↑/↓ escolher  ·  Espaço/Enter confirmar"
	if _tela == "dificuldade":
		ajuda += "  ·  Esc voltar"
	_centro(fonte, Vector2(cx, 166), ajuda, 8, Color("566c86"))
	_centro(fonte, Vector2(cx, 184), "P1: A/D andar · W/Espaço pular · S descer · Q/E melhorias", 8, Color("41a6f6"))
	if _tela == "modo" and _sel == 1:
		_centro(fonte, Vector2(cx, 196), "P2: ←/→ andar · ↑/0 pular · ↓ descer · 1/2 melhorias", 8, Color("ef7d57"))
	_centro(fonte, Vector2(cx, 208), "O ataque é automático. Partidas de 3 minutos + Morte Súbita.", 8, Color("566c86"))


func _centro(fonte: Font, pos: Vector2, texto: String, tam: int, cor: Color) -> void:
	var larg := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	draw_string(fonte, pos + Vector2(-larg / 2.0, tam / 3.0), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)
