extends Node
## Autoload "Jogo": controles, sons, modo de jogo e dados das classes.

const COR_TIME := {0: Color("94b0c2"), 1: Color("41a6f6"), 2: Color("ef7d57")}
## Classes sorteadas no nível 2 (o Recruta é a classe inicial de todos)
const CLASSES: Array[String] = ["arqueiro", "orc", "mago", "rei"]
const TEMPO_PARTIDA := 180.0

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

## Mapeamentos para controles que o Godot não conhece (o campo platform é
## ignorado por add_joy_mapping, então não é preciso informá-lo).
## Ordem "padrão" do navegador, mas sem a etiqueta mapping="standard" (o Brave
## esconde a etiqueta; Chrome/Edge às vezes também). Os gatilhos chegam como
## botões 6 e 7, porque o Godot só os converte em eixo quando há a etiqueta.
const MAPEAMENTO_PADRAO := "a:b0,b:b1,x:b2,y:b3,leftshoulder:b4,rightshoulder:b5," \
		+ "lefttrigger:b6,righttrigger:b7,back:b8,start:b9,leftstick:b10,rightstick:b11," \
		+ "dpup:b12,dpdown:b13,dpleft:b14,dpright:b15,guide:b16,leftx:a0,lefty:a1,rightx:a2,righty:a3"
## Ordem "crua" estilo Xbox (xpad), como o Firefox entrega no Linux.
const MAPEAMENTO_XBOX := "a:b0,b:b1,y:b3,x:b2,start:b7,guide:b8,back:b6,leftstick:b9,rightstick:b10," \
		+ "leftshoulder:b4,rightshoulder:b5,dpup:-a7,dpleft:-a6,dpdown:+a7,dpright:+a6," \
		+ "leftx:a0,lefty:a1,rightx:a3,righty:a4,lefttrigger:a2,righttrigger:a5"
## Por controle (número do dispositivo): "reconhecido" ou "corrigido automaticamente"
var estado_controle := {}

## Repetição ao segurar cima/baixo nos menus (teclado, direcional e analógico)
const ACOES_REPETIVEIS: Array[String] = ["menu_cima", "menu_baixo"]
const ATRASO_REPETICAO := 0.4
const INTERVALO_REPETICAO := 0.15
var _relogio := 0.0
var _rep_proximo := {}
var _pulso := {}

var _musica: AudioStreamPlayer
var _musica_atual := ""

var _sons := {}


func _ready() -> void:
	_criar_controles()
	_carregar_opcoes()
	Input.joy_connection_changed.connect(_ao_mudar_controle)
	for dev in Input.get_connected_joypads():
		_verificar_controle(dev)
	_musica = AudioStreamPlayer.new()
	_musica.volume_db = -8.0
	add_child(_musica)
	for nome in ["pulo", "flecha", "espada", "magia", "invocar", "acerto",
			"morte", "nivel", "porta", "vitoria", "pouso", "pingo", "item", "bola", "dash"]:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/sfx/%s.wav" % nome)
		p.max_polyphony = 4
		add_child(p)
		_sons[nome] = p


func _process(delta: float) -> void:
	_atualizar_pulsos(delta / maxf(Engine.time_scale, 0.05))


func _atualizar_pulsos(delta: float) -> void:
	## Calcula, uma vez por quadro, quais ações de menu "disparam" agora: ao apertar
	## e depois, com a tecla/direcional/analógico segurado, a cada INTERVALO_REPETICAO.
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


func menu_pulso(acao: String) -> bool:
	## Use nos menus no lugar de is_action_just_pressed para cima/baixo: repete ao segurar.
	return _pulso.get(acao, false)


# ------------------------------------------------------------------ Controles

static func mapeamento_xbox(guid: String, nome: String) -> String:
	## Linha de mapeamento SDL (layout cru estilo Xbox) para um controle desconhecido.
	return _linha_mapeamento(guid, nome, MAPEAMENTO_XBOX)


static func mapeamento_padrao(guid: String, nome: String) -> String:
	## Linha de mapeamento SDL (ordem padrão do navegador, sem a etiqueta "standard").
	return _linha_mapeamento(guid, nome, MAPEAMENTO_PADRAO)


static func _linha_mapeamento(guid: String, nome: String, campos: String) -> String:
	if guid.strip_edges() == "":
		return ""
	var limpo := nome.replace(",", " ").replace("\n", " ").strip_edges()
	if limpo == "":
		limpo = "Controle"
	return "%s,%s,%s" % [guid.strip_edges(), limpo, campos]


static func layout_por_formato(botoes: int, eixos: int) -> String:
	## Decide o layout pelo formato que o navegador informa: a ordem padrão tem
	## 16+ botões e até 4 eixos; a crua estilo Xbox, ~11 botões e 6–8 eixos.
	if botoes >= 16 and eixos <= 4:
		return "padrao"
	return "xbox"


func _formato_no_navegador(dev: int) -> Vector2i:
	## (botões, eixos) do controle segundo o navegador; (-1, -1) fora do navegador.
	if not OS.has_feature("web"):
		return Vector2i(-1, -1)
	var r = JavaScriptBridge.eval("(function(){var p=(navigator.getGamepads?navigator.getGamepads():[])[%d];return p?(p.buttons.length+','+p.axes.length):''})()" % dev, true)
	var partes := str(r).split(",")
	if partes.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(partes[0]), int(partes[1]))


func _ao_mudar_controle(dev: int, conectado: bool) -> void:
	if conectado:
		_verificar_controle(dev)
	else:
		estado_controle.erase(dev)


func _verificar_controle(dev: int) -> void:
	## Controle que o Godot reconhece fica como está; os desconhecidos recebem o
	## mapeamento estilo Xbox (senão LB/RB/Start chegam trocados no navegador).
	if not dev in Input.get_connected_joypads():
		return
	if Input.is_joy_known(dev):
		estado_controle[dev] = "reconhecido"
		return
	var formato := _formato_no_navegador(dev)
	if formato.x < 0:
		# Fora do navegador o Godot usa o banco de controles do sistema; não mexe.
		estado_controle[dev] = "desconhecido"
		return
	var layout := layout_por_formato(formato.x, formato.y)
	var guid := Input.get_joy_guid(dev)
	var nome := Input.get_joy_name(dev)
	var m := mapeamento_padrao(guid, nome) if layout == "padrao" else mapeamento_xbox(guid, nome)
	if m == "":
		return
	Input.add_joy_mapping(m, true)
	estado_controle[dev] = "corrigido (%s, %d botões, %d eixos)" % [
			"ordem padrão" if layout == "padrao" else "layout Xbox", formato.x, formato.y]
	print("Controle %d (%s): %s" % [dev, nome, estado_controle[dev]])


func texto_estado_controle(dev: int) -> String:
	if estado_controle.has(dev):
		return estado_controle[dev]
	return "reconhecido" if Input.is_joy_known(dev) else "desconhecido"


func _input(event: InputEvent) -> void:
	## Guarda o último tipo de entrada usado (controle x teclado/toque/mouse).
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
	if cfg.load(ARQUIVO_OPCOES) == OK:
		som = cfg.get_value("opcoes", "som", true)
		iluminacao = cfg.get_value("opcoes", "iluminacao", true)
		impacto = cfg.get_value("opcoes", "impacto", true)
		botoes_tela = cfg.get_value("opcoes", "botoes_tela", false)
		tutorial_visto = cfg.get_value("opcoes", "tutorial_visto", false)
	AudioServer.set_bus_mute(0, not som)


func _salvar_opcoes() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("opcoes", "som", som)
	cfg.set_value("opcoes", "iluminacao", iluminacao)
	cfg.set_value("opcoes", "impacto", impacto)
	cfg.set_value("opcoes", "botoes_tela", botoes_tela)
	cfg.set_value("opcoes", "tutorial_visto", tutorial_visto)
	cfg.save(ARQUIVO_OPCOES)


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
	# Jogador 1: WASD + Espaço | Jogador 2: setas + 0
	_acao("p1_esquerda", [KEY_A])
	_acao("p1_direita", [KEY_D])
	_acao("p1_pular", [KEY_W, KEY_SPACE])
	_acao("p1_descer", [KEY_S])
	_acao("p1_dash", [KEY_SHIFT])
	_acao("p1_opcao1", [KEY_Q])
	_acao("p1_opcao2", [KEY_E])
	_acao("p2_esquerda", [KEY_LEFT])
	_acao("p2_direita", [KEY_RIGHT])
	_acao("p2_pular", [KEY_UP, KEY_KP_0, KEY_0])
	_acao("p2_descer", [KEY_DOWN])
	_acao("p2_dash", [KEY_CTRL])
	_acao("p2_opcao1", [KEY_KP_1, KEY_K])
	_acao("p2_opcao2", [KEY_KP_2, KEY_L])
	# Sentido do dash por toque (sem tecla: o controles_toque.gd aperta por um instante)
	for j in [1, 2]:
		_acao("p%d_dash_esq" % j, [])
		_acao("p%d_dash_dir" % j, [])
	# Menus
	_acao("menu_cima", [KEY_W, KEY_UP], 0.5)
	_acao("menu_baixo", [KEY_S, KEY_DOWN], 0.5)
	_acao("menu_ok", [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_KP_0, KEY_0])
	_acao("menu_voltar", [KEY_ESCAPE, KEY_BACKSPACE])
	_acao("pausar", [KEY_ESCAPE, KEY_P])
	for dev in [0, 1]:
		_botao("menu_cima", dev, JOY_BUTTON_DPAD_UP)
		_botao("menu_baixo", dev, JOY_BUTTON_DPAD_DOWN)
		_eixo("menu_cima", dev, JOY_AXIS_LEFT_Y, -1.0)
		_eixo("menu_baixo", dev, JOY_AXIS_LEFT_Y, 1.0)
		_botao("menu_ok", dev, JOY_BUTTON_A)
		_botao("menu_voltar", dev, JOY_BUTTON_B)
		_botao("pausar", dev, JOY_BUTTON_START)
	# Controles (gamepad): 1º controle = P1, 2º controle = P2
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
	ev.button_index = botao
	InputMap.action_add_event(nome, ev)


func _eixo(nome: String, dispositivo: int, eixo: JoyAxis, valor: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = dispositivo
	ev.axis = eixo
	ev.axis_value = valor
	InputMap.action_add_event(nome, ev)
