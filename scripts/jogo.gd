extends Node
## Autoload "Jogo": controles (atalhos pelo MapaControle, pausa e analógico nos menus),
## sons, modo de jogo e dados das classes.

const COR_TIME := {0: Color("94b0c2"), 1: Color("41a6f6"), 2: Color("ef7d57")}
## Classes sorteadas no nível 2 (o Recruta é a classe inicial de todos)
const CLASSES: Array[String] = ["arqueiro", "orc", "mago", "rei"]
const TEMPO_PARTIDA := 180.0
## Zona morta do analógico nas ações de movimento da partida (kit de controle)
const ZONA_MORTA_JOGO := 0.2

## Modo escolhido no menu
var solo := true
var dificuldade := 1  ## 0 fácil, 1 normal, 2 difícil
## true em celular/tablet (mostra os controles na tela)
var toque := false
## Último dispositivo usado foi um controle (esconde os botões da tela e mostra LB/RB nas cartas)
var usando_controle := false

## Opções (salvas no navegador)
signal opcoes_mudaram
var som := true
var iluminacao := true
## Tremor de tela, clarões e a pausa curtinha nos golpes fortes
var impacto := true
## Celular: mostra o joystick e o botão de pulo desenhados na tela (padrão: tela limpa)
var botoes_tela := false
## O tutorial dos controles de toque já foi mostrado neste aparelho
var tutorial_visto := false
const ARQUIVO_OPCOES := "user://opcoes.cfg"
## Arquivo em uso (os testes trocam por outro para não mexer no do jogador)
var arquivo_opcoes := ARQUIVO_OPCOES
## Torre da Tormenta: classes (nomes de Jogo.CLASSES) com MUITO DIFÍCIL desbloqueado
var torre_desbloqueada: Array[String] = []

## Pausa pedida por Start/Back do controle, Esc ou P (tratada em _input, antes da
## interface, para valer mesmo com um botão focado). Quem pausa/despausa escuta aqui.
signal pausa_pedida
## Partida em andamento (a Partida se registra); sem ela, ou com ela pausada, o analógico navega nos menus
var partida: Node = null
var _ultima_pausa_ms := -1000
var _controle_apertado := false

## Repetição ao segurar cima/baixo nos menus (teclado e direcional)
const ACOES_REPETIVEIS: Array[String] = ["menu_cima", "menu_baixo"]
const ATRASO_REPETICAO := 0.4
const INTERVALO_REPETICAO := 0.15
var _relogio := 0.0
var _rep_proximo := {}
var _pulso := {}

## Analógico esquerdo nos menus: zona morta 0,5 com histerese (solta abaixo de 0,3),
## um passo ao empurrar e, segurando, repete depois de 0,4 s a cada 0,15 s.
## Cada passo vira um pulso de menu_cima/menu_baixo (o analógico NÃO fica no InputMap
## dessas ações, senão cada movimento do eixo contaria como um aperto novo).
const ZONA_MORTA_MENU := 0.5
const SOLTAR_MENU := 0.3
var _eixos := {JOY_AXIS_LEFT_X: 0.0, JOY_AXIS_LEFT_Y: 0.0}
var _direcao := Vector2i.ZERO
var _proximo_passo := 0.0
## Passos dados pelo analógico nos menus (os testes conferem o ritmo por aqui)
var passos_analogico := 0

var _musica: AudioStreamPlayer
var _musica_atual := ""

var _sons := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_criar_controles()
	_carregar_opcoes()
	_musica = AudioStreamPlayer.new()
	_musica.volume_db = -8.0
	add_child(_musica)
	for nome in ["pulo", "flecha", "espada", "magia", "invocar", "acerto",
			"morte", "nivel", "porta", "vitoria", "pouso", "pingo", "item", "bola", "dash", "bloqueio"]:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/sfx/%s.wav" % nome)
		p.max_polyphony = 4
		add_child(p)
		_sons[nome] = p


func _process(delta: float) -> void:
	_atualizar_pulsos(delta / maxf(Engine.time_scale, 0.05))
	_conferir_pausa_por_polling()


func _atualizar_pulsos(delta: float) -> void:
	## Calcula, uma vez por quadro, quais ações de menu "disparam" agora: ao apertar
	## e depois, com a tecla/direcional segurado, a cada INTERVALO_REPETICAO. O analógico
	## (ver _atualizar_analogico) soma seus próprios passos.
	_relogio += delta
	for a in ACOES_REPETIVEIS:
		var dispara := false
		if Input.is_action_just_pressed(a):
			dispara = true
			_rep_proximo[a] = _relogio + ATRASO_REPETICAO
		elif Input.is_action_pressed(a):
			if _rep_proximo.has(a) and _relogio >= _rep_proximo[a]:
				dispara = true
				_rep_proximo[a] = _relogio + INTERVALO_REPETICAO
			elif not _rep_proximo.has(a):
				_rep_proximo[a] = _relogio + ATRASO_REPETICAO
		else:
			_rep_proximo.erase(a)
		_pulso[a] = dispara
	_atualizar_analogico(delta)


func menu_pulso(acao: String) -> bool:
	## Use nos menus no lugar de is_action_just_pressed para cima/baixo: repete ao segurar.
	return _pulso.get(acao, false)


func em_menu() -> bool:
	## true quando não há partida rodando (menu, lobby) ou ela está pausada/com painel aberto.
	return partida == null or not is_instance_valid(partida) or partida.pausado


# ------------------------------------------------------------------ Analógico nos menus

func _atualizar_analogico(delta: float) -> void:
	_ler_analogico()
	if _direcao == Vector2i.ZERO:
		return
	_proximo_passo -= delta
	while _proximo_passo <= 0.0 and _direcao != Vector2i.ZERO:
		_passo_analogico()
		_proximo_passo += INTERVALO_REPETICAO


func _ler_analogico() -> void:
	## No navegador os eventos de eixo nem sempre chegam: lê direto do Input (o maior
	## valor entre os controles conectados). Sem controle (testes) valem os eventos.
	var ids := Input.get_connected_joypads()
	if ids.is_empty():
		return
	var x := 0.0
	var y := 0.0
	for id in ids:
		var ax := Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
		var ay := Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
		if absf(ax) > absf(x):
			x = ax
		if absf(ay) > absf(y):
			y = ay
	if is_equal_approx(x, _eixos[JOY_AXIS_LEFT_X]) and is_equal_approx(y, _eixos[JOY_AXIS_LEFT_Y]):
		return
	_eixos[JOY_AXIS_LEFT_X] = x
	_eixos[JOY_AXIS_LEFT_Y] = y
	_atualizar_direcao_analogico()


func _atualizar_direcao_analogico() -> void:
	var v := Vector2(_eixos[JOY_AXIS_LEFT_X], _eixos[JOY_AXIS_LEFT_Y])
	var nova := Vector2i.ZERO
	var dominante := Vector2i(signi(roundi(v.x * 100.0)), 0) if absf(v.x) >= absf(v.y) else Vector2i(0, signi(roundi(v.y * 100.0)))
	var forca := maxf(absf(v.x), absf(v.y))
	if _direcao != Vector2i.ZERO:
		# Histerese: continua enquanto passar de 0,3 na mesma direção.
		var ao_longo := v.x * _direcao.x + v.y * _direcao.y
		nova = _direcao if ao_longo >= SOLTAR_MENU else Vector2i.ZERO
		if forca > ZONA_MORTA_MENU and dominante != _direcao and dominante != Vector2i.ZERO:
			nova = dominante
	elif forca > ZONA_MORTA_MENU:
		nova = dominante
	if nova == _direcao:
		return
	_direcao = nova
	if nova != Vector2i.ZERO:
		_passo_analogico()
		_proximo_passo = ATRASO_REPETICAO


func _passo_analogico() -> void:
	# Só em menus (na partida sem pausa o analógico anda). Os menus só usam cima/baixo.
	if not em_menu() or _direcao.y == 0:
		return
	passos_analogico += 1
	_pulso["menu_cima" if _direcao.y < 0 else "menu_baixo"] = true


# ------------------------------------------------------------------ Pausa

func _conferir_pausa_por_polling() -> void:
	## Reserva: alguns navegadores/controles não entregam o evento do botão Start/Back.
	var apertado := false
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, MapaControle.botao(JOY_BUTTON_START)) \
				or Input.is_joy_button_pressed(id, MapaControle.botao(JOY_BUTTON_BACK)):
			apertado = true
	if apertado and not _controle_apertado and Time.get_ticks_msec() - _ultima_pausa_ms > 400:
		_pedir_pausa()
	_controle_apertado = apertado


func _pedir_pausa() -> void:
	_ultima_pausa_ms = Time.get_ticks_msec()
	pausa_pedida.emit()


func _input(event: InputEvent) -> void:
	## Pausa (Start/Back/Esc/P) e último tipo de entrada usado (controle x teclado/toque/mouse).
	var pausa := false
	if event is InputEventJoypadButton:
		pausa = event.pressed and (event.button_index == MapaControle.botao(JOY_BUTTON_START) \
				or event.button_index == MapaControle.botao(JOY_BUTTON_BACK))
	elif event is InputEventKey:
		pausa = event.pressed and not event.echo and event.is_action_pressed("pausar")
	elif event is InputEventJoypadMotion and _eixos.has(event.axis):
		_eixos[event.axis] = event.axis_value
		_atualizar_direcao_analogico()
	if pausa:
		_pedir_pausa()
		get_viewport().set_input_as_handled()
	if event is InputEventJoypadButton:
		if event.pressed:
			usando_controle = true
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.5:
			usando_controle = true
	elif event is InputEventKey:
		if event.pressed:
			usando_controle = false
	elif event is InputEventScreenTouch or event is InputEventMouseButton:
		usando_controle = false


static func tem_controle() -> bool:
	## Há algum controle conectado ou foi o último dispositivo usado?
	return Jogo.usando_controle or not Input.get_connected_joypads().is_empty()


func torre_muito_dificil(classe: String) -> bool:
	return torre_desbloqueada.has(classe)


func desbloquear_torre_muito_dificil(classe: String) -> void:
	if not torre_desbloqueada.has(classe):
		torre_desbloqueada.append(classe)
		_salvar_opcoes()


func dados_classe(indice: int) -> ClasseDados:
	return load("res://resources/classes/%s.tres" % CLASSES[indice])


func dados_recruta() -> ClasseDados:
	return load("res://resources/classes/recruta.tres")


func config_rede() -> Dictionary:
	## Partida em rede criada pelo anfitrião (P1 = anfitrião, P2 = convidado).
	solo = false
	return {"semente": randi(), "tempo": TEMPO_PARTIDA, "bots": {1: -1, 2: -1}, "rede": "anfitriao"}


func config_partida() -> Dictionary:
	return {
		"semente": randi(),
		"tempo": TEMPO_PARTIDA,
		"bots": {1: -1, 2: dificuldade if solo else -1},
	}


# ------------------------------------------------------------------ Música

func tocar_musica(nome: String) -> void:
	## "menu" (calma) ou "batalha" (tensa). Troca com um fade curto.
	if nome == _musica_atual:
		return
	_musica_atual = nome
	var stream: AudioStream = load("res://assets/musica/%s.ogg" % nome)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var tw := create_tween()
	if _musica.playing:
		tw.tween_property(_musica, "volume_db", -40.0, 0.4)
	tw.tween_callback(func() -> void:
		_musica.stream = stream
		_musica.pitch_scale = 1.0
		_musica.volume_db = -8.0
		_musica.play())


func musica_tensa(ligada: bool) -> void:
	## Morte Súbita: a música acelera.
	create_tween().tween_property(_musica, "pitch_scale", 1.18 if ligada else 1.0, 1.0)


# ------------------------------------------------------------------ Opções

func definir_som(ligado: bool) -> void:
	som = ligado
	AudioServer.set_bus_mute(0, not ligado)
	_salvar_opcoes()
	opcoes_mudaram.emit()


func definir_iluminacao(ligada: bool) -> void:
	iluminacao = ligada
	_salvar_opcoes()
	opcoes_mudaram.emit()


func definir_botoes_tela(ligado: bool) -> void:
	botoes_tela = ligado
	_salvar_opcoes()
	opcoes_mudaram.emit()


func marcar_tutorial_visto() -> void:
	if not tutorial_visto:
		tutorial_visto = true
		_salvar_opcoes()


func tela_cheia() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func alternar_tela_cheia() -> void:
	if tela_cheia():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		# No Android, também tenta travar a tela na horizontal
		if OS.has_feature("web"):
			JavaScriptBridge.eval("try { screen.orientation.lock('landscape').catch(function(){}); } catch (e) {}")


func definir_impacto(ligado: bool) -> void:
	impacto = ligado
	_salvar_opcoes()
	opcoes_mudaram.emit()


# ------------------------------------------------------------------ Clarão ao apanhar

const SHADER_CLARAO := """shader_type canvas_item;
uniform float clarao = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.rgb = mix(c.rgb, vec3(1.0), clarao);
	COLOR = c * COLOR;
}
"""
var _shader_clarao: Shader


func material_clarao() -> ShaderMaterial:
	## Material que deixa o sprite branco por um instante (parâmetro "clarao").
	if _shader_clarao == null:
		_shader_clarao = Shader.new()
		_shader_clarao.code = SHADER_CLARAO
	var m := ShaderMaterial.new()
	m.shader = _shader_clarao
	return m


func pintar_clarao(sprite: Sprite2D, ligado: bool) -> void:
	## Clarão branco de quem apanhou. Com "impactos" desligado vira só um tom avermelhado.
	var m := sprite.material as ShaderMaterial
	if m != null:
		m.set_shader_parameter("clarao", 1.0 if ligado and impacto else 0.0)
	var a := sprite.modulate.a
	sprite.modulate = Color(1, 0.35, 0.35, a) if ligado and not impacto else Color(1, 1, 1, a)


func _carregar_opcoes() -> void:
	var cfg := ConfigFile.new()
	torre_desbloqueada.clear()
	if cfg.load(arquivo_opcoes) == OK:
		som = cfg.get_value("opcoes", "som", true)
		iluminacao = cfg.get_value("opcoes", "iluminacao", true)
		impacto = cfg.get_value("opcoes", "impacto", true)
		botoes_tela = cfg.get_value("opcoes", "botoes_tela", false)
		tutorial_visto = cfg.get_value("opcoes", "tutorial_visto", false)
		for c in CLASSES:
			if cfg.get_value("torre", "muito_dificil_" + c, false):
				torre_desbloqueada.append(c)
	AudioServer.set_bus_mute(0, not som)


func _salvar_opcoes() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("opcoes", "som", som)
	cfg.set_value("opcoes", "iluminacao", iluminacao)
	cfg.set_value("opcoes", "impacto", impacto)
	cfg.set_value("opcoes", "botoes_tela", botoes_tela)
	cfg.set_value("opcoes", "tutorial_visto", tutorial_visto)
	for c in torre_desbloqueada:
		cfg.set_value("torre", "muito_dificil_" + c, true)
	cfg.save(arquivo_opcoes)


func tocar(nome: String) -> void:
	# Em rede, o anfitrião repassa os sons da partida para o convidado
	if Rede.e_anfitriao() and Rede.partida != null:
		Rede.evento(["som", nome])
	if _sons.has(nome):
		_sons[nome].pitch_scale = randf_range(0.92, 1.08)
		_sons[nome].play()


func hostis(a, b) -> bool:
	## Times: 1 e 2 = jogadores (e seus lacaios); 0 = monstros neutros.
	return a.equipe != b.equipe


static func acao(jogador: int, nome: String) -> String:
	return "p%d_%s" % [jogador, nome]


func _criar_controles() -> void:
	# Refaz tudo do zero (também usado pelos testes ao trocar MapaControle.web)
	for a in InputMap.get_actions():
		if a.begins_with("p1_") or a.begins_with("p2_") or a.begins_with("menu_") or a == "pausar":
			InputMap.erase_action(a)
	# Jogador 1: WASD + Espaço | Jogador 2: setas + 0
	_acao("p1_esquerda", [KEY_A], ZONA_MORTA_JOGO)
	_acao("p1_direita", [KEY_D], ZONA_MORTA_JOGO)
	_acao("p1_pular", [KEY_W, KEY_SPACE])
	_acao("p1_descer", [KEY_S], ZONA_MORTA_JOGO)
	_acao("p1_dash", [KEY_SHIFT])
	_acao("p1_opcao1", [KEY_Q])
	_acao("p1_opcao2", [KEY_E])
	_acao("p2_esquerda", [KEY_LEFT], ZONA_MORTA_JOGO)
	_acao("p2_direita", [KEY_RIGHT], ZONA_MORTA_JOGO)
	_acao("p2_pular", [KEY_UP, KEY_KP_0, KEY_0])
	_acao("p2_descer", [KEY_DOWN], ZONA_MORTA_JOGO)
	_acao("p2_dash", [KEY_CTRL])
	_acao("p2_opcao1", [KEY_KP_1, KEY_K])
	_acao("p2_opcao2", [KEY_KP_2, KEY_L])
	# Sentido do dash por toque (sem tecla: o controles_toque.gd aperta por um instante)
	for j in [1, 2]:
		_acao("p%d_dash_esq" % j, [])
		_acao("p%d_dash_dir" % j, [])
	# Menus (qualquer controle; o analógico não entra aqui, ver _atualizar_analogico)
	_acao("menu_cima", [KEY_W, KEY_UP], 0.5)
	_acao("menu_baixo", [KEY_S, KEY_DOWN], 0.5)
	_acao("menu_ok", [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_KP_0, KEY_0])
	_acao("menu_voltar", [KEY_ESCAPE, KEY_BACKSPACE])
	_acao("pausar", [KEY_ESCAPE, KEY_P])
	_botao("menu_cima", -1, JOY_BUTTON_DPAD_UP)
	_botao("menu_baixo", -1, JOY_BUTTON_DPAD_DOWN)
	_botao("menu_ok", -1, JOY_BUTTON_A)
	_botao("menu_voltar", -1, JOY_BUTTON_B)
	_botao("pausar", -1, JOY_BUTTON_START)
	_botao("pausar", -1, JOY_BUTTON_BACK)
	# Controles (gamepad): 1º controle = P1, 2º controle = P2. Gatilhos não são ligados.
	for j in [1, 2]:
		var dev: int = j - 1
		_botao("p%d_esquerda" % j, dev, JOY_BUTTON_DPAD_LEFT)
		_botao("p%d_direita" % j, dev, JOY_BUTTON_DPAD_RIGHT)
		_botao("p%d_descer" % j, dev, JOY_BUTTON_DPAD_DOWN)
		_botao("p%d_pular" % j, dev, JOY_BUTTON_A)
		_botao("p%d_dash" % j, dev, JOY_BUTTON_B)
		_botao("p%d_opcao1" % j, dev, JOY_BUTTON_LEFT_SHOULDER)
		_botao("p%d_opcao2" % j, dev, JOY_BUTTON_RIGHT_SHOULDER)
		_eixo("p%d_esquerda" % j, dev, JOY_AXIS_LEFT_X, -1.0)
		_eixo("p%d_direita" % j, dev, JOY_AXIS_LEFT_X, 1.0)
		_eixo("p%d_descer" % j, dev, JOY_AXIS_LEFT_Y, 1.0)


func _acao(nome: String, teclas: Array, zona_morta := 0.3) -> void:
	if not InputMap.has_action(nome):
		InputMap.add_action(nome, zona_morta)
	for t in teclas:
		var ev := InputEventKey.new()
		ev.physical_keycode = t
		InputMap.action_add_event(nome, ev)


func _botao(nome: String, dispositivo: int, botao: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = dispositivo
	ev.button_index = MapaControle.botao(botao)  # no navegador, o índice W3C
	InputMap.action_add_event(nome, ev)


func _eixo(nome: String, dispositivo: int, eixo: JoyAxis, valor: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = dispositivo
	ev.axis = eixo
	ev.axis_value = valor
	InputMap.action_add_event(nome, ev)
