extends Control
## Tela "JOGAR EM REDE": combina a conexão copiando e colando dois códigos.
##
##   Quem cria:  CRIAR PARTIDA -> COPIAR CONVITE (manda pro amigo) -> COLAR RESPOSTA
##   Quem entra: ENTRAR -> COLAR CONVITE -> COPIAR RESPOSTA (manda de volta)
## Assim que conecta, quem criou começa a partida para os dois.

signal voltar
signal iniciar_como_anfitriao

const LARG := 220.0
const ALT_ITEM := 20.0
const ESPACO := 5.0

var _estado := "inicio"
var _codigo := ""
var _aviso := ""
var _aviso_t := 0.0
var _sel := 0
var _t_conectando := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	Rede.codigo_pronto.connect(_ao_codigo_pronto)
	Rede.conectado.connect(_ao_conectar)
	Rede.falhou.connect(func(motivo: String) -> void:
		_estado = "erro"
		_aviso = motivo
		_sel = 0)


func _exit_tree() -> void:
	Rede.codigo_pronto.disconnect(_ao_codigo_pronto)
	Rede.conectado.disconnect(_ao_conectar)


# ------------------------------------------------------------------ Estados

func _texto() -> String:
	match _estado:
		"inicio":
			return "Os dois abrem o jogo. Um CRIA a partida e o outro ENTRA.\nVocês trocam dois códigos (por WhatsApp, por exemplo)."
		"gerando":
			return "Gerando código..."
		"convite":
			return "1. Copie o CONVITE e mande para o seu amigo.\n2. Ele vai te mandar uma RESPOSTA: cole aqui."
		"entrar":
			return "Cole o CONVITE que seu amigo mandou."
		"resposta":
			return "Copie a RESPOSTA e mande de volta para quem criou a partida.\nA partida começa sozinha quando ele colar."
		"conectando":
			return "Conectando..." if _t_conectando < 15.0 else \
					"Está demorando... Confira se o código está completo\nou tente de novo (os dois na mesma rede Wi-Fi ajuda)."
		"conectado":
			return "Conectado! Começando a partida..."
		"erro":
			return _aviso
	return ""


func _botoes() -> Array:
	## [id, texto, destaque]
	match _estado:
		"inicio":
			return [["criar", "CRIAR PARTIDA", true], ["entrar", "ENTRAR NA PARTIDA", true], ["voltar", "VOLTAR", false]]
		"gerando", "conectando", "conectado":
			return [["cancelar", "CANCELAR", false]]
		"convite":
			return [["copiar", "COPIAR CONVITE", true], ["colar_resposta", "COLAR RESPOSTA", true],
					["mostrar", "não copiou? mostrar código", false], ["cancelar", "CANCELAR", false]]
		"entrar":
			return [["colar_convite", "COLAR CONVITE", true], ["cancelar", "VOLTAR", false]]
		"resposta":
			return [["copiar", "COPIAR RESPOSTA", true], ["mostrar", "não copiou? mostrar código", false],
					["cancelar", "CANCELAR", false]]
		"erro":
			return [["cancelar", "VOLTAR", false]]
	return []


func _acionar(id: String) -> void:
	Jogo.tocar("pulo")
	match id:
		"criar":
			_estado = "gerando"
			Rede.criar_convite()
		"entrar":
			_estado = "entrar"
		"colar_convite":
			var codigo := Rede.pedir_colagem("Cole aqui o CONVITE que seu amigo mandou:")
			if codigo.strip_edges() == "":
				return
			_estado = "gerando"
			if not Rede.aceitar_convite(codigo):
				return  # o sinal "falhou" mostra o erro
		"copiar":
			Rede.copiar(_codigo)
			_avisar("Código copiado!")
		"mostrar":
			Rede.mostrar_para_copiar(_codigo)
		"colar_resposta":
			var codigo := Rede.pedir_colagem("Cole aqui a RESPOSTA do seu amigo:")
			if codigo.strip_edges() == "":
				return
			if Rede.aceitar_resposta(codigo):
				_estado = "conectando"
				_t_conectando = 0.0
		"cancelar":
			Rede.desconectar()
			_estado = "inicio"
		"voltar":
			Rede.desconectar()
			voltar.emit()
	_sel = 0


func _avisar(texto: String) -> void:
	_aviso = texto
	_aviso_t = 2.0


func _ao_codigo_pronto(codigo: String) -> void:
	_codigo = codigo
	_estado = "convite" if Rede.papel == "anfitriao" else "resposta"
	_sel = 0
	# Já tenta copiar sozinho, para poupar um toque
	Rede.copiar(codigo)


func _ao_conectar() -> void:
	_estado = "conectado"
	if Rede.papel == "anfitriao":
		await get_tree().create_timer(0.6).timeout
		iniciar_como_anfitriao.emit()


# ------------------------------------------------------------------ Entrada e desenho

func _rect_botao(i: int) -> Rect2:
	return Rect2(size.x / 2.0 - LARG / 2.0, 140.0 + i * (ALT_ITEM + ESPACO), LARG, ALT_ITEM)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var botoes := _botoes()
		for i in botoes.size():
			if _rect_botao(i).grow(2).has_point(event.position):
				_sel = i
				_acionar(botoes[i][0])
				accept_event()
				return


func _process(delta: float) -> void:
	if _aviso_t > 0.0:
		_aviso_t -= delta
	if _estado == "conectando":
		_t_conectando += delta
	var botoes := _botoes()
	if not botoes.is_empty():
		_sel = clampi(_sel, 0, botoes.size() - 1)
		if Input.is_action_just_pressed("menu_cima"):
			_sel = wrapi(_sel - 1, 0, botoes.size())
		elif Input.is_action_just_pressed("menu_baixo"):
			_sel = wrapi(_sel + 1, 0, botoes.size())
		elif Input.is_action_just_pressed("menu_ok"):
			_acionar(botoes[_sel][0])
		elif Input.is_action_just_pressed("menu_voltar"):
			_acionar("voltar" if _estado == "inicio" else "cancelar")
	queue_redraw()


func _draw() -> void:
	var fonte := ThemeDB.fallback_font
	var cx := size.x / 2.0
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.065, 0.085))
	_centrado(fonte, Vector2(cx, 34), "JOGAR EM REDE", 20, Color("ffcd75"))
	_centrado(fonte, Vector2(cx, 52), "1 contra 1 · no mesmo Wi-Fi ou pela internet", 8, Color("566c86"))
	var linhas := _texto().split("\n")
	for i in linhas.size():
		_centrado(fonte, Vector2(cx, 78 + i * 13), linhas[i], 9, Color("94b0c2") if _estado != "erro" else Color("ef7d57"))
	if _codigo != "" and _estado in ["convite", "resposta"]:
		var previa := _codigo.substr(0, 34) + "…  (%d caracteres)" % _codigo.length()
		_centrado(fonte, Vector2(cx, 120), previa, 7, Color("566c86"))
	if _estado in ["gerando", "conectando"]:
		var pontos := ".".repeat(1 + int(Time.get_ticks_msec() / 400) % 3)
		_centrado(fonte, Vector2(cx, 120), pontos, 16, Color("ffcd75"))
	var botoes := _botoes()
	for i in botoes.size():
		var r := _rect_botao(i)
		var sel := i == _sel
		var destaque: bool = botoes[i][2]
		var fundo := Color("333c57") if sel else Color(0.12, 0.12, 0.17)
		if destaque:
			fundo = Color("38b764") if sel else Color("257179")
		draw_rect(r, fundo)
		draw_rect(r, Color(1, 1, 1, 0.5 if sel else 0.15), false, 1.0)
		_centrado(fonte, r.get_center(), botoes[i][1], 9 if botoes[i][1].begins_with("não") else 10, Color.WHITE)
	if _aviso_t > 0.0:
		_centrado(fonte, Vector2(cx, size.y - 14), _aviso, 10, Color("a7f070"))


func _centrado(fonte: Font, pos: Vector2, texto: String, tam: int, cor: Color) -> void:
	var larg := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	draw_string(fonte, pos + Vector2(-larg / 2.0, tam / 3.0), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)
