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

## Opções (salvas no navegador)
signal opcoes_mudaram
var som := true
var iluminacao := true
const ARQUIVO_OPCOES := "user://opcoes.cfg"

var _musica: AudioStreamPlayer
var _musica_atual := ""

var _sons := {}


func _ready() -> void:
	_criar_controles()
	_carregar_opcoes()
	_musica = AudioStreamPlayer.new()
	_musica.volume_db = -8.0
	add_child(_musica)
	for nome in ["pulo", "flecha", "espada", "magia", "invocar", "acerto",
			"morte", "nivel", "porta", "vitoria", "pouso", "pingo", "item", "bola"]:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/sfx/%s.wav" % nome)
		p.max_polyphony = 4
		add_child(p)
		_sons[nome] = p


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


func _carregar_opcoes() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(ARQUIVO_OPCOES) == OK:
		som = cfg.get_value("opcoes", "som", true)
		iluminacao = cfg.get_value("opcoes", "iluminacao", true)
	AudioServer.set_bus_mute(0, not som)


func _salvar_opcoes() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("opcoes", "som", som)
	cfg.set_value("opcoes", "iluminacao", iluminacao)
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
	_acao("p1_opcao1", [KEY_Q])
	_acao("p1_opcao2", [KEY_E])
	_acao("p2_esquerda", [KEY_LEFT])
	_acao("p2_direita", [KEY_RIGHT])
	_acao("p2_pular", [KEY_UP, KEY_KP_0, KEY_0])
	_acao("p2_descer", [KEY_DOWN])
	_acao("p2_opcao1", [KEY_KP_1, KEY_K])
	_acao("p2_opcao2", [KEY_KP_2, KEY_L])
	# Menus
	_acao("menu_cima", [KEY_W, KEY_UP])
	_acao("menu_baixo", [KEY_S, KEY_DOWN])
	_acao("menu_ok", [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_KP_0, KEY_0])
	_acao("menu_voltar", [KEY_ESCAPE, KEY_BACKSPACE])
	_acao("pausar", [KEY_ESCAPE, KEY_P])
	for dev in [0, 1]:
		_botao("menu_cima", dev, JOY_BUTTON_DPAD_UP)
		_botao("menu_baixo", dev, JOY_BUTTON_DPAD_DOWN)
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
		_botao("p%d_opcao1" % j, dev, JOY_BUTTON_X)
		_botao("p%d_opcao2" % j, dev, JOY_BUTTON_Y)
		_eixo("p%d_esquerda" % j, dev, JOY_AXIS_LEFT_X, -1.0)
		_eixo("p%d_direita" % j, dev, JOY_AXIS_LEFT_X, 1.0)
		_eixo("p%d_descer" % j, dev, JOY_AXIS_LEFT_Y, 1.0)


func _acao(nome: String, teclas: Array) -> void:
	if not InputMap.has_action(nome):
		InputMap.add_action(nome, 0.3)
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
