extends Control
## Painel de opções, usado na pausa (com "Continuar" e "Voltar ao menu
## inicial") e no item "OPÇÕES" do menu inicial (com "Voltar").
## Botões grandes para o toque; no teclado: W/S ou setas + Espaço/Enter, Esc fecha.

signal continuar
signal sair_para_menu

## true na pausa; false no menu inicial
var na_pausa := true

var _sel := 0
var _quadros := 0  # ignora o teclado no 1º quadro (a tecla que abriu o painel)
const LARG := 190.0
const ALT_ITEM := 22.0
const ESPACO := 4.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP


func _itens() -> Array:
	var cheia := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	var itens: Array = []
	if na_pausa:
		itens.append(["continuar", "CONTINUAR"])
	itens.append(["tela_cheia", "Tela cheia: " + ("LIGADA" if cheia else "DESLIGADA")])
	itens.append(["som", "Som: " + ("LIGADO" if Jogo.som else "DESLIGADO")])
	itens.append(["luz", "Iluminação: " + ("LIGADA" if Jogo.iluminacao else "DESLIGADA")])
	itens.append(["menu", "VOLTAR AO MENU INICIAL" if na_pausa else "VOLTAR"])
	return itens


func _rect_item(i: int) -> Rect2:
	var n := _itens().size()
	var alt_total := n * ALT_ITEM + (n - 1) * ESPACO
	var y0 := size.y / 2.0 - alt_total / 2.0 + 12.0
	return Rect2(size.x / 2.0 - LARG / 2.0, y0 + i * (ALT_ITEM + ESPACO), LARG, ALT_ITEM)


func _acionar(id: String) -> void:
	Jogo.tocar("pulo")
	match id:
		"continuar":
			continuar.emit()
		"tela_cheia":
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				if OS.has_feature("web"):
					JavaScriptBridge.eval("try { screen.orientation.lock('landscape').catch(function(){}); } catch (e) {}")
		"som":
			Jogo.definir_som(not Jogo.som)
		"luz":
			Jogo.definir_iluminacao(not Jogo.iluminacao)
		"menu":
			if na_pausa:
				sair_para_menu.emit()
			else:
				continuar.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var itens := _itens()
		for i in itens.size():
			if _rect_item(i).grow(2).has_point(event.position):
				_sel = i
				_acionar(itens[i][0])
				accept_event()
				return


func _process(_delta: float) -> void:
	_quadros += 1
	queue_redraw()
	if _quadros < 2:
		return
	var itens := _itens()
	if Input.is_action_just_pressed("menu_cima"):
		_sel = wrapi(_sel - 1, 0, itens.size())
	elif Input.is_action_just_pressed("menu_baixo"):
		_sel = wrapi(_sel + 1, 0, itens.size())
	elif Input.is_action_just_pressed("menu_ok"):
		_acionar(itens[_sel][0])
	elif Input.is_action_just_pressed("menu_voltar") or Input.is_action_just_pressed("pausar"):
		continuar.emit()
	queue_redraw()


func _draw() -> void:
	var fonte := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6 if na_pausa else 0.9))
	var itens := _itens()
	var topo := _rect_item(0).position.y - 26.0
	var titulo := "PAUSADO" if na_pausa else "OPÇÕES"
	_texto(fonte, Vector2(size.x / 2.0, topo + 8.0), titulo, 16, Color("ffcd75"))
	for i in itens.size():
		var r := _rect_item(i)
		var sel := i == _sel
		var destaque: bool = itens[i][0] in ["continuar"]
		var fundo := Color("333c57") if sel else Color(0.12, 0.12, 0.17, 0.95)
		if destaque:
			fundo = Color("38b764") if sel else Color("257179")
		draw_rect(r, fundo)
		draw_rect(r, Color(1, 1, 1, 0.5 if sel else 0.15), false, 1.0)
		_texto(fonte, r.get_center(), itens[i][1], 10, Color.WHITE)


func _texto(fonte: Font, pos: Vector2, texto: String, tam: int, cor: Color) -> void:
	var larg := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	draw_string(fonte, pos + Vector2(-larg / 2.0, tam / 3.0), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)
