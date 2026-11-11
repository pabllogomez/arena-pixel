extends Control
## Controles na tela para celular/tablet (jogador 1).
##
## Aparecem automaticamente no navegador de celular, ou assim que a tela é
## tocada. Cada botão "aperta" a mesma ação do teclado (p1_esquerda,
## p1_pular...), então o jogo não precisa saber se o comando veio do toque.
## Suporta vários dedos ao mesmo tempo e deslizar o dedo entre ← e →.

## "menu", "jogo" ou "fim" (calculado a partir da partida atual)
var modo := "menu"
## Partida em andamento (o main.gd preenche; null no menu)
var partida: Node

## índice do dedo -> nome do botão que ele está apertando
var _dedos := {}

const COR_BOTAO := Color(1, 1, 1, 0.18)
const COR_APERTADO := Color(1, 1, 1, 0.4)
const COR_SIMBOLO := Color(1, 1, 1, 0.75)


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	if OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile"):
		Jogo.toque = true


func _process(_delta: float) -> void:
	var novo := "menu"
	if partida != null and is_instance_valid(partida):
		novo = "fim" if partida.fim else "jogo"
	if novo != modo:
		soltar_tudo()
		modo = novo
	queue_redraw()


# ------------------------------------------------------------------ Botões

func _botoes() -> Dictionary:
	## nome -> {"area": Rect2 (ou círculo), "acao": String}
	var b := {}
	if modo == "jogo":
		b["esquerda"] = {"centro": Vector2(30, 182), "raio": 21.0, "acao": "p1_esquerda", "seta": Vector2.LEFT}
		b["direita"] = {"centro": Vector2(78, 182), "raio": 21.0, "acao": "p1_direita", "seta": Vector2.RIGHT}
		b["descer"] = {"centro": Vector2(54, 146), "raio": 14.0, "acao": "p1_descer", "seta": Vector2.DOWN}
		b["pular"] = {"centro": Vector2(350, 176), "raio": 26.0, "acao": "p1_pular", "seta": Vector2.UP}
		b["sair"] = {"rect": Rect2(170, 196, 44, 16), "acao": "menu_voltar", "simbolo": "MENU"}
		if partida != null and partida.jogadores.has(1):
			var l = partida.jogadores[1]
			if not l.escolhas.is_empty() and l.vivo:
				# Mesmas posições das linhas do painel de escolha no HUD
				b["opcao1"] = {"rect": Rect2(3, 37, 156, 10), "acao": "p1_opcao1"}
				b["opcao2"] = {"rect": Rect2(3, 47, 156, 10), "acao": "p1_opcao2"}
	elif modo == "fim":
		var c := get_viewport().get_visible_rect().size / 2.0
		b["revanche"] = {"rect": Rect2(c.x - 92, c.y + 32, 88, 18), "acao": "menu_ok", "simbolo": "REVANCHE"}
		b["menu"] = {"rect": Rect2(c.x + 4, c.y + 32, 88, 18), "acao": "menu_voltar", "simbolo": "MENU"}
	return b


func _botao_em(pos: Vector2) -> String:
	var botoes := _botoes()
	for nome in botoes:
		var b: Dictionary = botoes[nome]
		if b.has("rect"):
			var r: Rect2 = b["rect"]
			if r.grow(4).has_point(pos):
				return nome
		elif pos.distance_to(b["centro"]) <= b["raio"] + 6.0:
			return nome
	return ""


# ------------------------------------------------------------------ Tela cheia

func _rect_tela_cheia() -> Rect2:
	## Ao lado do cronômetro na partida; no canto superior direito no menu.
	if modo == "menu":
		return Rect2(get_viewport().get_visible_rect().size.x - 20, 4, 16, 16)
	return Rect2(220, 1, 15, 15)


func alternar_tela_cheia() -> void:
	var cheia := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if cheia:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		# No Android, também tenta travar a tela na horizontal
		if OS.has_feature("web"):
			JavaScriptBridge.eval("try { screen.orientation.lock('landscape').catch(function(){}); } catch (e) {}")


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if not Jogo.toque:
			Jogo.toque = true
	# Botão de tela cheia (o toque também chega aqui como clique) e tecla F
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _rect_tela_cheia().grow(4).has_point(event.position):
			alternar_tela_cheia()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		alternar_tela_cheia()
		return
	if event is InputEventScreenTouch and _rect_tela_cheia().grow(4).has_point(event.position):
		return  # não aperta nenhum botão de jogo por baixo
	if modo == "menu":
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_trocar(t.index, _botao_em(t.position))
		else:
			_trocar(t.index, "")
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		var atual: String = _dedos.get(d.index, "")
		var novo := _botao_em(d.position)
		# Deslizar só troca entre botões de movimento (não dispara pulo sem querer)
		if novo != atual and (novo in ["esquerda", "direita", "descer"] or novo == ""):
			if atual in ["esquerda", "direita", "descer", ""]:
				_trocar(d.index, novo)


func _trocar(dedo: int, nome: String) -> void:
	var anterior: String = _dedos.get(dedo, "")
	if anterior == nome:
		return
	var botoes := _botoes()
	if anterior != "":
		_dedos.erase(dedo)
		if not _algum_dedo_em(anterior):
			Input.action_release(_acao_de(anterior))
	if nome != "" and botoes.has(nome):
		_dedos[dedo] = nome
		Input.action_press(botoes[nome]["acao"])
	get_viewport().set_input_as_handled()


func _algum_dedo_em(nome: String) -> bool:
	return nome in _dedos.values()


func _acao_de(nome: String) -> String:
	var mapa := {
		"esquerda": "p1_esquerda", "direita": "p1_direita", "descer": "p1_descer", "pular": "p1_pular",
		"sair": "menu_voltar", "opcao1": "p1_opcao1", "opcao2": "p1_opcao2",
		"revanche": "menu_ok", "menu": "menu_voltar",
	}
	return mapa.get(nome, "")


func soltar_tudo() -> void:
	for dedo in _dedos.keys():
		Input.action_release(_acao_de(_dedos[dedo]))
	_dedos.clear()


# ------------------------------------------------------------------ Desenho

func _draw() -> void:
	_desenhar_tela_cheia()
	if not Jogo.toque:
		return
	var fonte := ThemeDB.fallback_font
	var tela := get_viewport().get_visible_rect().size
	var janela := DisplayServer.window_get_size()
	if janela.y > janela.x:
		draw_rect(Rect2(Vector2.ZERO, tela), Color(0.07, 0.07, 0.12, 0.95))
		_texto(fonte, tela / 2.0 + Vector2(0, -8), "Gire o celular", 16, Color("ffcd75"))
		_texto(fonte, tela / 2.0 + Vector2(0, 10), "para jogar na horizontal", 8, Color.WHITE)
		return
	var botoes := _botoes()
	var apertados := _dedos.values()
	for nome in botoes:
		var b: Dictionary = botoes[nome]
		var cor := COR_APERTADO if nome in apertados else COR_BOTAO
		if b.has("rect"):
			if not b.has("simbolo"):
				continue  # áreas invisíveis (opções do HUD)
			var r: Rect2 = b["rect"]
			draw_rect(r, Color(0, 0, 0, 0.5))
			draw_rect(r, cor * 2.0, false, 1.0)
			_texto(fonte, r.get_center(), b["simbolo"], 8, COR_SIMBOLO)
		else:
			var c: Vector2 = b["centro"]
			var raio: float = b["raio"]
			draw_circle(c, raio, cor)
			draw_arc(c, raio, 0.0, TAU, 32, Color(1, 1, 1, 0.35), 1.0)
			var d: Vector2 = b["seta"]
			var t := raio * 0.45
			var lado := Vector2(-d.y, d.x)
			draw_colored_polygon(PackedVector2Array([c + d * t, c - d * t * 0.7 + lado * t, c - d * t * 0.7 - lado * t]), COR_SIMBOLO)


func _desenhar_tela_cheia() -> void:
	var r := _rect_tela_cheia()
	var cheia := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	draw_rect(r, Color(0, 0, 0, 0.55))
	var cor := Color(1, 1, 1, 0.8)
	var t := 3.0 if r.size.x < 16.0 else 4.0
	var m := 3.0
	# Quatro cantos: apontando para fora (entrar) ou para dentro (sair)
	for canto in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var c: Vector2 = canto
		var p: Vector2 = r.position + Vector2(m, m) + c * (r.size - Vector2(m, m) * 2.0)
		var dx := (1.0 if c.x == 0 else -1.0) * (-1.0 if cheia else 1.0)
		var dy := (1.0 if c.y == 0 else -1.0) * (-1.0 if cheia else 1.0)
		draw_line(p, p + Vector2(dx * t, 0), cor, 1.0)
		draw_line(p, p + Vector2(0, dy * t), cor, 1.0)


func _texto(fonte: Font, pos: Vector2, texto: String, tam: int, cor: Color) -> void:
	var larg := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	draw_string(fonte, pos + Vector2(-larg / 2.0, tam / 3.0), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)
