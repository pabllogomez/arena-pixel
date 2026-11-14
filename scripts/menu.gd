extends Control
## Menu inicial: SINGLE PLAYER (Torre da Tormenta ou Arena, contra a CPU), DUELO
## (local ou em rede) e opções, com as telas de personagem e dificuldade.
## Fica dentro da masmorra: título que cai letra por letra, as classes
## correndo numa plataforma e botões em pixel art.

signal jogar
signal jogar_rede
## Torre da Tormenta: índice do personagem (Jogo.CLASSES) e da dificuldade (0 a 2)
signal jogar_torre(personagem: int, dificuldade: int)

const PRINCIPAL := ["SINGLE PLAYER", "DUELO", "OPÇÕES"]
const SINGLE := ["TORRE DA TORMENTA", "ARENA"]
const DUELO := ["LOCAL", "REDE"]
## Tela de onde o "voltar" leva: [tela, opção selecionada ao chegar]
## (a tela da dificuldade da torre volta para o personagem escolhido)
const TELA_PAI := {
	"single": ["principal", 0], "duelo": ["principal", 1], "dificuldade": ["single", 1],
	"personagem": ["single", 0], "torre_dif": ["personagem", -1],
}
const TITULOS := {
	"principal": "MODO DE JOGO", "single": "SINGLE PLAYER", "duelo": "DUELO",
	"dificuldade": "DIFICULDADE DA MÁQUINA", "personagem": "ESCOLHA SEU PERSONAGEM",
	"torre_dif": "DIFICULDADE DA TORRE",
}
const Y_OPCOES := 147.0
const ESPACO_OPCOES := 20.0
const LARG_OPCAO := 140.0
const ALT_OPCAO := 17.0
const DIFICULDADES := ["FÁCIL", "NORMAL", "DIFÍCIL"]
const DIFICULDADES_TORRE := ["NORMAL", "DIFÍCIL", "MUITO DIFÍCIL"]
const TITULO := "ARENA PIXEL"
const TAM_TITULO := 40
const Y_TITULO := 44.0

## "principal", "single", "duelo", "dificuldade", "personagem" ou "torre_dif"
var _tela := "principal"
var _sel := 0
var _personagem := 0  ## escolhido na tela "personagem" (índice em Jogo.CLASSES)
var _t := 0.0
var _t_tela := 0.0   # tempo desde que a lista de opções atual apareceu
var _texturas: Array[Texture2D] = []
var _fundo: Control
var _pousou: Array[bool] = []
var _painel: Control = null


func _ready() -> void:
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


func _opcoes() -> Array:
	match _tela:
		"single":
			return SINGLE
		"duelo":
			return DUELO
		"dificuldade":
			return DIFICULDADES
		"personagem":
			return Jogo.CLASSES.map(func(c: String) -> String: return c.to_upper())
		"torre_dif":
			return DIFICULDADES_TORRE
	return PRINCIPAL


func _bloqueada(i: int) -> bool:
	## Só MUITO DIFÍCIL da torre tranca (até vencer a torre com o personagem).
	return _tela == "torre_dif" and i == 2 and not Jogo.torre_muito_dificil(Jogo.CLASSES[_personagem])


func _voltar() -> void:
	if not TELA_PAI.has(_tela):
		return
	var pai: Array = TELA_PAI[_tela]
	_mudar_tela(pai[0], _personagem if pai[1] < 0 else pai[1])


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
		if _tela != "principal" and _rect_voltar().grow(3).has_point(pos):
			Jogo.tocar("pulo")
			_voltar()
			return
		if _tela == "personagem":
			# Tocar no personagem em cima da plataforma também escolhe
			for i in Jogo.CLASSES.size():
				if Rect2(_x_classe(size.x / 2.0, i) - 24.0, 80.0, 48.0, 52.0).has_point(pos):
					_sel = i
					_confirmar()
					return
		var opcoes := _opcoes()
		for i in opcoes.size():
			if _rect_opcao(i).grow(1).has_point(pos):
				_sel = i
				_confirmar()


func _mudar_tela(tela: String, sel: int) -> void:
	_tela = tela
	_sel = sel
	_t_tela = 0.0


func _confirmar() -> void:
	if _bloqueada(_sel):
		Jogo.tocar("acerto")  # trancada: não faz nada (o aviso já está na tela)
		return
	Jogo.tocar("nivel")
	match _tela:
		"principal":
			match _sel:
				0:
					_mudar_tela("single", 0)
				1:
					_mudar_tela("duelo", 0)
				_:
					_abrir_opcoes()
		"single":
			if _sel == 0:
				_mudar_tela("personagem", _personagem)
			else:
				Jogo.solo = true
				_mudar_tela("dificuldade", Jogo.dificuldade)
		"duelo":
			if _sel == 0:
				Jogo.solo = false
				jogar.emit()
			else:
				jogar_rede.emit()
		"dificuldade":
			Jogo.dificuldade = _sel
			jogar.emit()
		"personagem":
			_personagem = _sel
			_mudar_tela("torre_dif", 0)
		"torre_dif":
			Jogo.solo = true
			jogar_torre.emit(_personagem, _sel)


func _process(delta: float) -> void:
	_t += delta
	_t_tela += delta
	queue_redraw()
	if _painel != null:
		return  # o painel de opções cuida do teclado enquanto está aberto
	var opcoes := _opcoes()
	if Jogo.menu_pulso("menu_cima"):
		_sel = wrapi(_sel - 1, 0, opcoes.size())
		Jogo.tocar("pulo")
	elif Jogo.menu_pulso("menu_baixo"):
		_sel = wrapi(_sel + 1, 0, opcoes.size())
		Jogo.tocar("pulo")
	elif Input.is_action_just_pressed("menu_ok"):
		_confirmar()
	elif Input.is_action_just_pressed("menu_voltar"):
		_voltar()


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
	_desenhar_classes(cx, _personagem if _tela == "torre_dif" else (_sel if _tela == "personagem" else -1))

	var titulo: String = TITULOS[_tela]
	var larg := UI.largura(titulo)
	UI.texto(self, Vector2(cx, 138), titulo, UI.P, UI.OURO)
	draw_rect(Rect2(cx - larg / 2.0 - 26, 138, 20, 1), UI.BORDA)
	draw_rect(Rect2(cx + larg / 2.0 + 6, 138, 20, 1), UI.BORDA)
	var opcoes := _opcoes()
	for i in opcoes.size():
		# Os botões sobem para o lugar um depois do outro
		var e := clampf((_t_tela - i * 0.05) / 0.14, 0.0, 1.0)
		if e <= 0.0:
			continue
		var r := _rect_opcao(i)
		r.position.y += roundf(pow(1.0 - e, 2.0) * 14.0)
		UI.botao(self, r, opcoes[i], i == _sel, false, UI.P, _t)
		if _tela == "personagem" and i < _texturas.size():
			# Ícone com o sprite do personagem (anda quando selecionado)
			var quadro := (2 + int(_t * 8.0) % 4) if i == _sel else 0
			draw_texture_rect_region(_texturas[i], Rect2(r.position.x + 4.0, r.position.y, 16, 16),
					Rect2(quadro * 16, 0, 16, 16), Color.WHITE if i == _sel else Color(1, 1, 1, 0.7))
		if _bloqueada(i):
			if i != _sel:
				draw_rect(r.grow(-2), Color(UI.TINTA, 0.6))
			_cadeado(Vector2(r.position.x + 8.0, r.position.y + 4.0), UI.OURO if i == _sel else UI.BORDA)
	if _bloqueada(_sel) and _t_tela > 0.3:
		UI.texto(self, Vector2(cx, 216), "VENÇA A TORRE COM ESTE PERSONAGEM", UI.P, UI.OURO)

	if _tela != "principal":
		UI.botao(self, _rect_voltar(), "VOLTAR", false)
	_desenhar_tela_cheia()
	if Jogo.toque:
		UI.texto(self, Vector2(cx, 238), "Toque em uma opção", UI.P, UI.BORDA)
		UI.texto(self, Vector2(cx, 249), "Esquerda: arraste para andar    Direita: toque pula, arraste de lado dá dash    Melhorias: toque na carta", UI.P, Color("41a6f6"))
		UI.texto(self, Vector2(cx, 260), _regras(), UI.P, UI.BORDA)
		return
	var com_controle := Jogo.tem_controle()
	var ajuda := "W/S ou ↑/↓: escolher     ESPAÇO: confirmar"
	if com_controle:
		ajuda = "W/S, ↑/↓ ou direcional: escolher     ESPAÇO ou A: confirmar"
	if _tela != "principal":
		ajuda += "     ESC: voltar"
	UI.texto(self, Vector2(cx, 238), ajuda, UI.P, UI.BORDA)
	if com_controle:
		UI.texto(self, Vector2(cx, 249), "Controle: direcional/analógico anda    A: pula    B: dash    LB/RB: melhorias", UI.P, Color("41a6f6"))
	elif _tela == "duelo" and _sel == 0:
		UI.texto(self, Vector2(cx, 249), "P1: A/D andar, W pular, S descer, SHIFT dash, Q/E melhorias    P2: setas, CTRL dash, 1/2 melhorias", UI.P, Color("ef7d57"))
	else:
		UI.texto(self, Vector2(cx, 249), "A/D: andar    W ou ESPAÇO: pular    SHIFT: dash    S: descer    Q/E: melhorias", UI.P, Color("41a6f6"))
	UI.texto(self, Vector2(cx, 260), _regras(), UI.P, UI.BORDA)


func _regras() -> String:
	## Linha de regras no rodapé: a da torre aparece nas telas dela.
	if _tela == "personagem" or _tela == "torre_dif" or (_tela == "single" and _sel == 0):
		return "Torre da Tormenta: 9 andares, 1:30 por luta, sem monstros nem itens."
	return "O ataque é automático. Partidas de 3 minutos + Morte Súbita."


func _cadeado(pos: Vector2, cor: Color) -> void:
	## Cadeadinho de 7x9 pixels (opção trancada).
	pos = pos.round()
	draw_rect(Rect2(pos.x + 2, pos.y, 3, 1), cor)
	draw_rect(Rect2(pos.x + 1, pos.y + 1, 1, 3), cor)
	draw_rect(Rect2(pos.x + 5, pos.y + 1, 1, 3), cor)
	draw_rect(Rect2(pos.x, pos.y + 4, 7, 5), cor)
	draw_rect(Rect2(pos.x + 3, pos.y + 5, 1, 2), UI.TINTA)


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


func _x_classe(cx: float, i: int) -> float:
	return roundf(cx + (i - (Jogo.CLASSES.size() - 1) / 2.0) * 60.0)


func _desenhar_classes(cx: float, escolhida := -1) -> void:
	## As classes que podem ser sorteadas, correndo em cima de uma plataforma.
	## Com `escolhida` >= 0 (telas da torre) só ela fica acesa.
	var n := _texturas.size()
	var plataforma := Rect2(cx - 122, 117, 244, 5)
	draw_rect(plataforma.grow(1), UI.TINTA)
	draw_rect(plataforma, Color("333c57"))
	draw_rect(Rect2(plataforma.position, Vector2(plataforma.size.x, 1)), UI.BORDA)
	for i in n:
		var x := _x_classe(cx, i)
		var apagada := escolhida >= 0 and i != escolhida
		var e := clampf((_t - 0.7 - i * 0.08) / 0.15, 0.0, 1.0)
		if e <= 0.0:
			continue
		var quadro := 2 + int(_t * 8.0 + i) % 4
		var sobe := roundf(pow(1.0 - e, 2.0) * 10.0)
		draw_texture_rect_region(_texturas[i], Rect2(x - 16, 85 - sobe, 32, 32), Rect2(quadro * 16, 0, 16, 16),
				Color(1, 1, 1, 0.35) if apagada else Color.WHITE)
		UI.texto(self, Vector2(x, 128), Jogo.CLASSES[i].to_upper(), UI.P, UI.OURO if i == escolhida else UI.BORDA)


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
