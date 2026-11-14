extends Control
## Menu inicial: modo de jogo (1 ou 2 jogadores, rede, opções) e dificuldade
## do bot. Fica dentro da masmorra: título que cai letra por letra, as classes
## correndo numa plataforma e botões em pixel art.

signal jogar
signal jogar_rede

const MODOS := ["1 JOGADOR", "2 JOGADORES", "JOGAR EM REDE", "OPÇÕES"]
const Y_OPCOES := 147.0
const ESPACO_OPCOES := 20.0
const LARG_OPCAO := 140.0
const ALT_OPCAO := 17.0
const DIFICULDADES := ["FÁCIL", "NORMAL", "DIFÍCIL"]
const TITULO := "ARENA PIXEL"
const TAM_TITULO := 40
const Y_TITULO := 44.0

var _tela := "modo"  # "modo" ou "dificuldade"
var _sel := 0
var _t := 0.0
var _t_tela := 0.0   # tempo desde que a lista de opções atual apareceu
var _texturas: Array[Texture2D] = []
var _fundo: Control
var _pousou: Array[bool] = []
var _painel: Control = null


func _ready() -> void:
	_sel = 0 if Jogo.solo else 1
	for c in Jogo.CLASSES:
		_texturas.append(load("res://assets/sprites/%s_1.png" % c))
	_fundo = preload("res://scripts/fundo_menu.gd").new()
	add_child(_fundo)
	_pousou.resize(TITULO.length())
	_pousou.fill(false)


func _abrir_opcoes() -> void:
	_painel = preload("res://scripts/painel_opcoes.gd").new()
	_painel.na_pausa = false
	_painel.continuar.connect(func() -> void:
		_painel.queue_free()
		_painel = null)
	add_child(_painel)


func _rect_opcao(i: int) -> Rect2:
	return Rect2(roundf(size.x / 2.0 - LARG_OPCAO / 2.0), Y_OPCOES + i * ESPACO_OPCOES, LARG_OPCAO, ALT_OPCAO)


func _rect_tela_cheia() -> Rect2:
	return Rect2(size.x - 26.0, 6, 20, 20)


func _rect_voltar() -> Rect2:
	return Rect2(6, 6, 56, 16)


func _gui_input(event: InputEvent) -> void:
	if _painel != null:
		return
	# Toque ou clique: escolhe a opção tocada (o toque vira clique automaticamente)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = event.position - _deslocamento()
		if _rect_tela_cheia().grow(4).has_point(pos):
			Jogo.tocar("pulo")
			Jogo.alternar_tela_cheia()
			return
		if _tela == "dificuldade" and _rect_voltar().grow(3).has_point(pos):
			_mudar_tela("modo", 0)
			return
		var opcoes := MODOS if _tela == "modo" else DIFICULDADES
		for i in opcoes.size():
			if _rect_opcao(i).grow(1).has_point(pos):
				_sel = i
				_confirmar()


func _mudar_tela(tela: String, sel: int) -> void:
	_tela = tela
	_sel = sel
	_t_tela = 0.0


func _confirmar() -> void:
	Jogo.tocar("nivel")
	if _tela == "modo" and MODOS[_sel] == "OPÇÕES":
		_abrir_opcoes()
		return
	if _tela == "modo" and MODOS[_sel] == "JOGAR EM REDE":
		jogar_rede.emit()
		return
	if _tela == "modo":
		Jogo.solo = _sel == 0
		if Jogo.solo:
			_mudar_tela("dificuldade", Jogo.dificuldade)
		else:
			jogar.emit()
	else:
		Jogo.dificuldade = _sel
		jogar.emit()


func _process(delta: float) -> void:
	_t += delta
	_t_tela += delta
	queue_redraw()
	if _painel != null:
		return  # o painel de opções cuida do teclado enquanto está aberto
	var opcoes := MODOS if _tela == "modo" else DIFICULDADES
	if Jogo.menu_pulso("menu_cima"):
		_sel = wrapi(_sel - 1, 0, opcoes.size())
		Jogo.tocar("pulo")
	elif Jogo.menu_pulso("menu_baixo"):
		_sel = wrapi(_sel + 1, 0, opcoes.size())
		Jogo.tocar("pulo")
	elif Input.is_action_just_pressed("menu_ok"):
		_confirmar()
	elif Input.is_action_just_pressed("menu_voltar") and _tela == "dificuldade":
		_mudar_tela("modo", 0)


func _deslocamento() -> Vector2:
	## O layout foi desenhado para 270 px de altura; centraliza na tela atual.
	return Vector2(0, roundf((size.y - 270.0) / 2.0))


func _draw() -> void:
	# Versão no canto, embaixo do botão de opções (na build de teste: "0.1-teste · commit")
	draw_set_transform(Vector2.ZERO)
	UI.texto(self, Vector2(size.x - 4.0, 32.0), "v" + str(ProjectSettings.get_setting("application/config/version", "")), UI.P, UI.BORDA, UI.DIR)
	var cx := roundf(size.x / 2.0)
	draw_set_transform(_deslocamento())
	_desenhar_titulo(cx)
	if _t > 0.9:
		UI.texto(self, Vector2(cx, 74), "Comece como Recruta. Cace monstros. Ganhe uma classe. Vença!", UI.P, UI.LUZ)
	_desenhar_classes(cx)

	var titulo := "MODO DE JOGO" if _tela == "modo" else "DIFICULDADE DA MÁQUINA"
	var larg := UI.largura(titulo)
	UI.texto(self, Vector2(cx, 138), titulo, UI.P, UI.OURO)
	draw_rect(Rect2(cx - larg / 2.0 - 26, 138, 20, 1), UI.BORDA)
	draw_rect(Rect2(cx + larg / 2.0 + 6, 138, 20, 1), UI.BORDA)
	var opcoes := MODOS if _tela == "modo" else DIFICULDADES
	for i in opcoes.size():
		# Os botões sobem para o lugar um depois do outro
		var e := clampf((_t_tela - i * 0.05) / 0.14, 0.0, 1.0)
		if e <= 0.0:
			continue
		var r := _rect_opcao(i)
		r.position.y += roundf(pow(1.0 - e, 2.0) * 14.0)
		UI.botao(self, r, opcoes[i], i == _sel, false, UI.P, _t)

	if _tela == "dificuldade":
		UI.botao(self, _rect_voltar(), "VOLTAR", false)
	_desenhar_tela_cheia()
	if Jogo.toque:
		UI.texto(self, Vector2(cx, 238), "Toque em uma opção", UI.P, UI.BORDA)
		UI.texto(self, Vector2(cx, 249), "Esquerda: arraste para andar    Direita: toque pula, arraste de lado dá dash    Melhorias: toque na carta", UI.P, Color("41a6f6"))
		UI.texto(self, Vector2(cx, 260), "O ataque é automático. Partidas de 3 minutos + Morte Súbita.", UI.P, UI.BORDA)
		return
	var com_controle := Jogo.tem_controle()
	var ajuda := "W/S ou ↑/↓: escolher     ESPAÇO: confirmar"
	if com_controle:
		ajuda = "W/S, ↑/↓ ou direcional: escolher     ESPAÇO ou A: confirmar"
	if _tela == "dificuldade":
		ajuda += "     ESC: voltar"
	UI.texto(self, Vector2(cx, 238), ajuda, UI.P, UI.BORDA)
	if com_controle:
		UI.texto(self, Vector2(cx, 249), "Controle: direcional/analógico anda    A: pula    B: dash    LB/RB: melhorias", UI.P, Color("41a6f6"))
	elif _tela == "modo" and _sel == 1:
		UI.texto(self, Vector2(cx, 249), "P1: A/D andar, W pular, S descer, SHIFT dash, Q/E melhorias    P2: setas, CTRL dash, 1/2 melhorias", UI.P, Color("ef7d57"))
	else:
		UI.texto(self, Vector2(cx, 249), "A/D: andar    W ou ESPAÇO: pular    SHIFT: dash    S: descer    Q/E: melhorias", UI.P, Color("41a6f6"))
	UI.texto(self, Vector2(cx, 260), "O ataque é automático. Partidas de 3 minutos + Morte Súbita.", UI.P, UI.BORDA)


func _desenhar_titulo(cx: float) -> void:
	## Cada letra cai do alto, levanta poeira ao pousar e depois ondula de leve.
	## Duas passadas: primeiro o contorno e a sombra de todas as letras, depois
	## as cores (senão o contorno de uma letra cobre a vizinha).
	var x0 := cx - roundf(UI.largura(TITULO, TAM_TITULO) / 2.0)
	for passada in 2:
		var x := x0
		for i in TITULO.length():
			var letra := TITULO[i]
			var larg := UI.largura(letra, TAM_TITULO)
			var e := clampf((_t - 0.1 - i * 0.05) / 0.2, 0.0, 1.0)
			if letra != " " and e > 0.0:
				var y := Y_TITULO - roundf(pow(1.0 - e, 2.0) * 70.0)
				if e >= 1.0:
					if not _pousou[i]:
						_pousou[i] = true
						_fundo.poeira(_deslocamento() + Vector2(x + larg / 2.0, Y_TITULO + 18.0))
					y += roundf(sin(_t * 2.2 + i * 0.6) * 1.5)
				if passada == 0:
					var sombra := Color("5d275d") if i < 5 else Color("29366f")
					UI.texto(self, Vector2(x, y + 5.0), letra, TAM_TITULO, sombra, UI.ESQ)
					UI.texto(self, Vector2(x, y), letra, TAM_TITULO, UI.TINTA, UI.ESQ)
				else:
					UI.texto(self, Vector2(x, y), letra, TAM_TITULO, UI.OURO if i < 5 else Color("73eff7"), UI.ESQ, false)
			x += larg


func _desenhar_classes(cx: float) -> void:
	## As classes que podem ser sorteadas, correndo em cima de uma plataforma.
	var n := _texturas.size()
	var plataforma := Rect2(cx - 122, 117, 244, 5)
	draw_rect(plataforma.grow(1), UI.TINTA)
	draw_rect(plataforma, Color("333c57"))
	draw_rect(Rect2(plataforma.position, Vector2(plataforma.size.x, 1)), UI.BORDA)
	for i in n:
		var x := cx + (i - (n - 1) / 2.0) * 60.0
		var e := clampf((_t - 0.7 - i * 0.08) / 0.15, 0.0, 1.0)
		if e <= 0.0:
			continue
		var quadro := 2 + int(_t * 8.0 + i) % 4
		var sobe := roundf(pow(1.0 - e, 2.0) * 10.0)
		draw_texture_rect_region(_texturas[i], Rect2(x - 16, 85 - sobe, 32, 32), Rect2(quadro * 16, 0, 16, 16))
		UI.texto(self, Vector2(x, 128), Jogo.CLASSES[i].to_upper(), UI.P, UI.BORDA)


func _desenhar_tela_cheia() -> void:
	## Botão de tela cheia no canto: quatro cantoneiras (para fora = ampliar,
	## para dentro = sair da tela cheia).
	var r := _rect_tela_cheia()
	var cheia := Jogo.tela_cheia()
	UI.moldura(self, r, Color(UI.TINTA, 0.92), UI.OURO if cheia else UI.BORDA, UI.BRANCO if cheia else UI.LUZ)
	var c := r.position + Vector2(10, 10)
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			# Ampliar: quina no canto de fora, braços para dentro. Reduzir: o contrário.
			var k := 2 if cheia else 5
			var passo := 1 if cheia else -1
			for i in 3:
				draw_rect(Rect2(_px(c.x, sx, k + passo * i), _px(c.y, sy, k), 1, 1), UI.BRANCO)
				draw_rect(Rect2(_px(c.x, sx, k), _px(c.y, sy, k + passo * i), 1, 1), UI.BRANCO)
	if not Jogo.toque:
		UI.tecla(self, Vector2(r.position.x - 9.0, r.position.y + 10.0), "F")


func _px(centro: float, sinal: int, k: int) -> float:
	## Coluna/linha do k-ésimo pixel a partir do centro, para o lado `sinal`.
	return centro + k if sinal > 0 else centro - k - 1
