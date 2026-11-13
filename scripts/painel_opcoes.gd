extends Control
## Painel de opções, usado na pausa (com "Continuar" e "Voltar ao menu
## inicial") e no item "OPÇÕES" do menu inicial (com "Voltar").
## Botões grandes para o toque; no teclado: W/S ou setas + Espaço/Enter, Esc fecha.

signal continuar
signal sair_para_menu

## true na pausa; false no menu inicial
var na_pausa := true

var _sel := 0
var _tutorial: Control = null
var _quadros := 0  # ignora o teclado no 1º quadro (a tecla que abriu o painel)
const LARG := 190.0
const ALT_ITEM := 18.0
const ESPACO := 3.0


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
	itens.append(["impacto", "Tremor e clarões: " + ("LIGADOS" if Jogo.impacto else "DESLIGADOS")])
	if Jogo.toque:
		itens.append(["botoes", "Botões na tela: " + ("LIGADOS" if Jogo.botoes_tela else "DESLIGADOS")])
		itens.append(["como_jogar", "COMO JOGAR"])
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
		"impacto":
			Jogo.definir_impacto(not Jogo.impacto)
		"botoes":
			Jogo.definir_botoes_tela(not Jogo.botoes_tela)
		"como_jogar":
			_tutorial = preload("res://scripts/tutorial.gd").new()
			add_child(_tutorial)
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
	if _quadros < 2 or (_tutorial != null and is_instance_valid(_tutorial)):
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
	draw_rect(Rect2(Vector2.ZERO, size), Color(UI.TINTA, 0.7 if na_pausa else 0.88))
	var itens := _itens()
	var primeiro := _rect_item(0)
	var ultimo := _rect_item(itens.size() - 1)
	# Quadro em volta de tudo, com o título numa plaquinha em cima
	var quadro := Rect2(primeiro.position.x - 14.0, primeiro.position.y - 26.0, LARG + 28.0, ultimo.end.y - primeiro.position.y + 36.0)
	UI.moldura(self, quadro, Color("23263a"))
	var titulo := "PAUSADO" if na_pausa else "OPÇÕES"
	var placa := Rect2(size.x / 2.0 - 44.0, quadro.position.y - 9.0, 88, 22)
	UI.moldura(self, placa, UI.TINTA, UI.OURO, UI.BRANCO)
	UI.texto(self, placa.get_center(), titulo, UI.M, UI.OURO)
	for i in itens.size():
		UI.botao(self, _rect_item(i), itens[i][1], i == _sel, itens[i][0] == "continuar", UI.P, _quadros / 60.0)


