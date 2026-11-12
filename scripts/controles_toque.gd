extends Control
## Controles na tela para celular/tablet (jogador 1).
##
## Aparecem automaticamente no navegador de celular, ou assim que a tela é
## tocada. Cada comando "aperta" a mesma ação do teclado (p1_esquerda,
## p1_pular...), então o jogo não precisa saber se o comando veio do toque.
##
## Lado esquerdo: joystick flutuante. Aparece onde o dedo encostar; para os
## lados anda (mais longe = mais rápido), para baixo desce da plataforma.
## Lado direito: botão de pular. Suporta vários dedos ao mesmo tempo.

## "menu", "jogo", "pausa" ou "fim" (calculado a partir da partida atual)
var modo := "menu"
## Partida em andamento (o main.gd preenche; null no menu)
var partida: Node

## índice do dedo -> nome do botão que ele está apertando
var _dedos := {}

const JOY_RAIO := 22.0
const JOY_ZONA_MORTA := 0.2
const JOY_DESCER := 0.6   ## quanto puxar para baixo para descer

## Joystick: dedo que o controla (-1 = nenhum), centro e posição da bolinha
var _joy_dedo := -1
var _joy_centro := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _joy_descendo := false

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
		if partida.fim:
			novo = "fim"
		elif partida.pausado or partida.escolhendo:
			novo = "pausa"
		else:
			novo = "jogo"
	if novo != modo:
		soltar_tudo()
		modo = novo
	queue_redraw()


# ------------------------------------------------------------------ Botões

func _botoes() -> Dictionary:
	## nome -> {"area": Rect2 (ou círculo), "acao": String}
	var b := {}
	if modo == "jogo":
		var tela := get_viewport().get_visible_rect().size
		b["pular"] = {"centro": Vector2(tela.x - 40, tela.y - 46), "raio": 28.0, "acao": "p1_pular", "seta": Vector2.UP}
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

func _rect_pausa() -> Rect2:
	## Botão de pausa ao lado do cronômetro (só durante a partida).
	var tela := get_viewport().get_visible_rect().size
	return Rect2(tela.x / 2.0 + 28, 1, 17, 15)


func _na_pausa(pos: Vector2) -> bool:
	return modo == "jogo" and _rect_pausa().grow(3).has_point(pos)


func _sobre_cartas(pos: Vector2) -> bool:
	## Toque numa carta de melhoria não deve criar o joystick.
	if partida == null or not is_instance_valid(partida):
		return false
	var hud = partida.hud
	if not hud.mostra_cartas(1):
		return false
	for r in hud.rects_cartas(1):
		if (r as Rect2).has_point(pos):
			return true
	return false


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
	# Botão de pausa (o toque também chega aqui como clique)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _na_pausa(event.position):
			partida.pausar()
			get_viewport().set_input_as_handled()
			return
	# Atalhos de teclado: F tela cheia, M som, I iluminação
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F:
				alternar_tela_cheia()
			KEY_M:
				Jogo.definir_som(not Jogo.som)
			KEY_I:
				Jogo.definir_iluminacao(not Jogo.iluminacao)
	if event is InputEventScreenTouch and (_na_pausa(event.position) or _sobre_cartas(event.position)):
		return  # deixa o clique chegar ao botão/carta
	if modo == "menu" or modo == "pausa":
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var nome := _botao_em(t.position)
			if nome != "":
				_trocar(t.index, nome)
			elif modo == "jogo" and _joy_dedo < 0 and t.position.x < get_viewport().get_visible_rect().size.x * 0.5:
				_joy_dedo = t.index
				_joy_centro = t.position
				_joy_pos = t.position
				get_viewport().set_input_as_handled()
		elif t.index == _joy_dedo:
			_soltar_joystick()
		else:
			_trocar(t.index, "")
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _joy_dedo:
			_mover_joystick(d.position)


# ------------------------------------------------------------------ Joystick

func _mover_joystick(pos: Vector2) -> void:
	var desvio := pos - _joy_centro
	# Se o dedo for muito longe, a base acompanha (não precisa voltar ao centro)
	if desvio.length() > JOY_RAIO * 1.6:
		_joy_centro += desvio.normalized() * (desvio.length() - JOY_RAIO * 1.6)
		desvio = pos - _joy_centro
	desvio = desvio.limit_length(JOY_RAIO)
	_joy_pos = _joy_centro + desvio
	var x := desvio.x / JOY_RAIO
	var y := desvio.y / JOY_RAIO
	# Andar: força proporcional à distância (fora da zona morta)
	var forca := clampf((absf(x) - JOY_ZONA_MORTA) / (0.7 - JOY_ZONA_MORTA), 0.0, 1.0)
	if forca > 0.0:
		forca = maxf(forca, 0.35)
	Input.action_release("p1_esquerda")
	Input.action_release("p1_direita")
	if forca > 0.0:
		Input.action_press("p1_direita" if x > 0.0 else "p1_esquerda", forca)
	# Descer: puxar para baixo (sem estar andando muito para o lado)
	var descer := y > JOY_DESCER and absf(x) < 0.75
	if descer != _joy_descendo:
		_joy_descendo = descer
		if descer:
			Input.action_press("p1_descer")
		else:
			Input.action_release("p1_descer")
	get_viewport().set_input_as_handled()


func _soltar_joystick() -> void:
	if _joy_dedo >= 0:
		Input.action_release("p1_esquerda")
		Input.action_release("p1_direita")
		Input.action_release("p1_descer")
	_joy_dedo = -1
	_joy_descendo = false


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
		"pular": "p1_pular",
		"revanche": "menu_ok", "menu": "menu_voltar",
	}
	return mapa.get(nome, "")


func soltar_tudo() -> void:
	for dedo in _dedos.keys():
		Input.action_release(_acao_de(_dedos[dedo]))
	_dedos.clear()
	_soltar_joystick()


# ------------------------------------------------------------------ Desenho

func _draw() -> void:
	if modo == "jogo":
		_desenhar_botao_pausa()
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
	if modo == "jogo":
		_desenhar_joystick()
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


func _desenhar_joystick() -> void:
	if _joy_dedo < 0:
		# Dica fraca de onde fica o controle
		var c := Vector2(60, get_viewport().get_visible_rect().size.y - 48)
		draw_arc(c, JOY_RAIO, 0.0, TAU, 32, Color(1, 1, 1, 0.12), 1.0)
		draw_circle(c, 9.0, Color(1, 1, 1, 0.08))
		return
	draw_circle(_joy_centro, JOY_RAIO, Color(1, 1, 1, 0.12))
	draw_arc(_joy_centro, JOY_RAIO, 0.0, TAU, 32, Color(1, 1, 1, 0.35), 1.0)
	# Marca de "descer" embaixo da base
	var baixo := _joy_centro + Vector2(0, JOY_RAIO - 5)
	var cor_baixo := Color(1, 1, 1, 0.7 if _joy_descendo else 0.25)
	draw_colored_polygon(PackedVector2Array([baixo + Vector2(-3, -2), baixo + Vector2(3, -2), baixo + Vector2(0, 2)]), cor_baixo)
	draw_circle(_joy_pos, 10.0, Color(1, 1, 1, 0.45))


func _desenhar_botao_pausa() -> void:
	var r := _rect_pausa()
	draw_rect(r, Color(0, 0, 0, 0.6))
	draw_rect(r, Color(1, 1, 1, 0.3), false, 1.0)
	var c := r.get_center()
	draw_rect(Rect2(c + Vector2(-4, -4), Vector2(3, 8)), Color(1, 1, 1, 0.85))
	draw_rect(Rect2(c + Vector2(1, -4), Vector2(3, 8)), Color(1, 1, 1, 0.85))


func _texto(fonte: Font, pos: Vector2, texto: String, tam: int, cor: Color) -> void:
	var larg := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	draw_string(fonte, pos + Vector2(-larg / 2.0, tam / 3.0), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)
