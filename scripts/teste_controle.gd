extends Control
## Tela "TESTE DO CONTROLE" (OPÇÕES): mostra cada controle conectado (nome, GUID e
## se foi reconhecido ou corrigido automaticamente) e, ao vivo, o último botão ou
## eixo recebido e o que o jogo entende dele. B ou Esc fecha.

signal fechado

const BOTOES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "Analógico esq. (clique)", JOY_BUTTON_RIGHT_STICK: "Analógico dir. (clique)",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "Direcional cima", JOY_BUTTON_DPAD_DOWN: "Direcional baixo",
	JOY_BUTTON_DPAD_LEFT: "Direcional esquerda", JOY_BUTTON_DPAD_RIGHT: "Direcional direita",
}
const EIXOS := {
	JOY_AXIS_LEFT_X: "Analógico esq. X", JOY_AXIS_LEFT_Y: "Analógico esq. Y",
	JOY_AXIS_RIGHT_X: "Analógico dir. X", JOY_AXIS_RIGHT_Y: "Analógico dir. Y",
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
}
## Ações do jogo que valem a pena mostrar: [ação, o que significa]
const ACOES := [
	["p1_opcao1", "escolher melhoria 1"], ["p1_opcao2", "escolher melhoria 2"],
	["p2_opcao1", "melhoria 1 (jogador 2)"], ["p2_opcao2", "melhoria 2 (jogador 2)"],
	["menu_ok", "confirmar (menu)"], ["menu_voltar", "voltar (menu)"], ["pausar", "pausar"],
	["menu_cima", "cima (menu)"], ["menu_baixo", "baixo (menu)"],
	["p1_pular", "pular"], ["p1_dash", "dash"], ["p1_esquerda", "andar para a esquerda"],
	["p1_direita", "andar para a direita"], ["p1_descer", "descer da plataforma"],
	["p2_pular", "pular (jogador 2)"], ["p2_dash", "dash (jogador 2)"],
	["p2_esquerda", "andar para a esquerda (jogador 2)"], ["p2_direita", "andar para a direita (jogador 2)"],
]

var _t := 0.0
var _ultimo := {}  # dispositivo -> {"entrada": String, "acao": String}


static func nome_entrada(ev: InputEvent) -> String:
	## "LB (botão 4)" ou "Analógico esq. Y (eixo 1) = -0.85"
	if ev is InputEventJoypadButton:
		var i: int = ev.button_index
		return "%s (botão %d)" % [BOTOES.get(i, "?"), i]
	if ev is InputEventJoypadMotion:
		var e: int = ev.axis
		return "%s (eixo %d) = %.2f" % [EIXOS.get(e, "?"), e, ev.axis_value]
	return ""


static func entendimento(ev: InputEvent) -> String:
	## O que o jogo faz com esta entrada (nomes das ações que ela aciona).
	var partes: Array[String] = []
	for a in ACOES:
		if InputMap.event_is_action(ev, a[0]):
			partes.append(a[1])
	if partes.is_empty():
		return "nada (sem função no jogo)"
	return ", ".join(partes.slice(0, 3))


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP


func _input(event: InputEvent) -> void:
	if _t < 0.3:
		return
	var registrar := false
	if event is InputEventJoypadButton and event.pressed:
		registrar = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		registrar = true
	if not registrar:
		return
	var texto := nome_entrada(event)
	_ultimo[event.device] = {"entrada": texto, "acao": entendimento(event)}
	# B fecha a tela
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B:
		get_viewport().set_input_as_handled()
		_fechar()


func _fechar() -> void:
	if is_queued_for_deletion():
		return
	Jogo.tocar("pulo")
	fechado.emit()
	queue_free()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _t > 0.3:
		accept_event()
		_fechar()


func _process(delta: float) -> void:
	_t += delta / maxf(Engine.time_scale, 0.05)
	if _t > 0.3 and Input.is_key_pressed(KEY_ESCAPE):
		_fechar()
	queue_redraw()


func _corta(texto: String, maximo: int) -> String:
	return texto if texto.length() <= maximo else texto.substr(0, maximo - 1) + "…"


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(UI.TINTA, 0.96))
	var cx := roundf(size.x / 2.0)
	UI.texto(self, Vector2(cx, 24), "TESTE DO CONTROLE", UI.G, UI.OURO)
	var devs := Input.get_connected_joypads()
	if devs.is_empty():
		UI.texto(self, Vector2(cx, 120), "Nenhum controle detectado.", UI.M, UI.LUZ)
		UI.texto(self, Vector2(cx, 140), "Aperte um botão do controle (o navegador só o enxerga depois disso).", UI.P, UI.BORDA)
	var y := 52.0
	for dev in devs.slice(0, 2):
		var quadro := Rect2(cx - 220, y, 440, 84)
		UI.moldura(self, quadro, Color("23263a"))
		var corrigido: bool = Jogo.texto_estado_controle(dev).begins_with("corrigido")
		UI.texto(self, Vector2(quadro.position.x + 8, y + 10), "CONTROLE %d: %s" % [dev + 1, _corta(Input.get_joy_name(dev), 38)], UI.P, UI.BRANCO, UI.ESQ)
		UI.texto(self, Vector2(quadro.position.x + 8, y + 22), "GUID: " + _corta(Input.get_joy_guid(dev), 60), UI.P, UI.BORDA, UI.ESQ)
		UI.texto(self, Vector2(quadro.position.x + 8, y + 34), "Estado: " + Jogo.texto_estado_controle(dev).to_upper(), UI.P,
				UI.OURO if corrigido else UI.VERDE, UI.ESQ)
		var ult: Dictionary = _ultimo.get(dev, {})
		if ult.is_empty():
			UI.texto(self, Vector2(quadro.position.x + 8, y + 54), "Aperte um botão ou mexa um analógico...", UI.P, UI.LUZ, UI.ESQ)
		else:
			UI.texto(self, Vector2(quadro.position.x + 8, y + 52), "Recebido: " + ult["entrada"], UI.P, UI.BRANCO, UI.ESQ)
			UI.texto(self, Vector2(quadro.position.x + 8, y + 66), "O jogo entende: " + ult["acao"], UI.P, UI.VERDE, UI.ESQ)
		y += 92.0
	UI.texto(self, Vector2(cx, size.y - 12), "B ou ESC: sair", UI.P, UI.LUZ)
