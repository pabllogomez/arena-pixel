extends Control
## Tela final da Torre da Tormenta: GAME OVER (andar alcançado e estatísticas)
## ou CAMPEÃO (resumo da subida, com o aviso de MUITO DIFÍCIL desbloqueado).

signal de_novo
signal menu

const LARG_BOTAO := 140.0
const ALT_BOTAO := 17.0
## Segundos em que a tela ignora o teclado (evita pular direto por um aperto da luta)
const ESPERA_ENTRADA := 0.6

var torre: Torre

var _sel := 0
var _t := 0.0
var _texturas: Array[Texture2D] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(preload("res://scripts/fundo_menu.gd").new())
	for c in Jogo.CLASSES:
		_texturas.append(load("res://assets/sprites/%s_1.png" % c))


func _campeao() -> bool:
	return torre.estado == "campeao"


func _rotulos() -> Array:
	return ["JOGAR DE NOVO" if _campeao() else "TENTAR DE NOVO", "MENU"]


func _rect_botao(i: int) -> Rect2:
	return Rect2(roundf(size.x / 2.0 - LARG_BOTAO / 2.0), 212.0 + i * 20.0, LARG_BOTAO, ALT_BOTAO)


func _acionar() -> void:
	Jogo.tocar("nivel")
	if _sel == 0:
		de_novo.emit()
	else:
		menu.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in 2:
			if _rect_botao(i).grow(1).has_point(event.position):
				_sel = i
				_acionar()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t < ESPERA_ENTRADA:
		return
	if Jogo.menu_pulso("menu_cima"):
		_sel = wrapi(_sel - 1, 0, 2)
		Jogo.tocar("pulo")
	elif Jogo.menu_pulso("menu_baixo"):
		_sel = wrapi(_sel + 1, 0, 2)
		Jogo.tocar("pulo")
	elif Input.is_action_just_pressed("menu_ok"):
		_acionar()
	elif Input.is_action_just_pressed("menu_voltar"):
		_sel = 1
		_acionar()


static func formatar_tempo(segundos: float) -> String:
	var s := roundi(segundos)
	return "%d:%02d" % [s / 60, s % 60]


func _linhas() -> Array:
	## [rótulo, valor] das estatísticas mostradas.
	var l: Array = [
		["TEMPO TOTAL", formatar_tempo(torre.tempo_total)],
		["DANO CAUSADO", str(roundi(torre.dano_causado))],
		["DANO RECEBIDO", str(roundi(torre.dano_recebido))],
		["ABATES", str(torre.abates)],
		["MAIOR GOLPE", str(roundi(torre.maior_golpe))],
		["NÍVEL FINAL" if _campeao() else "NÍVEL", str(torre.nivel_final)],
	]
	return l


func _draw() -> void:
	if torre == null:
		return
	var cx := roundf(size.x / 2.0)
	var campeao := _campeao()
	var cor := UI.OURO if campeao else UI.VERMELHO.lightened(0.25)
	var titulo := "CAMPEÃO DA TORRE!" if campeao else "GAME OVER"
	UI.texto(self, Vector2(cx, 22), titulo, UI.GG if not campeao else UI.G, cor)
	var sub := "VOCÊ VENCEU OS 9 ANDARES" if campeao else \
			("CAIU NA ETAPA FINAL (ANDAR %d DE 9)" if torre.andar_alcancado > Torre.ANDARES_SUBIDA else "CAIU NO ANDAR %d DE 9") % torre.andar_alcancado
	UI.texto(self, Vector2(cx, 44), sub, UI.P, UI.LUZ)
	if campeao and torre.desbloqueou_agora:
		var aceso := int(_t * 3.0) % 2 == 0
		UI.texto(self, Vector2(cx, 56), "MUITO DIFÍCIL DESBLOQUEADO!", UI.P, UI.VERDE if aceso else UI.BRANCO)

	# Painel: personagem à esquerda, estatísticas à direita
	var painel := Rect2(cx - 190.0, 66.0, 380.0, 138.0)
	UI.moldura(self, painel, Color("23263a"), UI.OURO if campeao else UI.BORDA, UI.BRANCO if campeao else UI.LUZ)
	var retrato := Rect2(painel.position.x + 14.0, painel.position.y + 14.0, 52, 52)
	UI.moldura(self, retrato, Color("29366f"), Jogo.COR_TIME[1], Jogo.COR_TIME[1].lightened(0.4))
	var quadro := 2 + int(_t * 8.0) % 4 if campeao else 7  # campeão corre; derrotado cai
	draw_texture_rect_region(_texturas[torre.personagem], Rect2(retrato.position + Vector2(2, 2), Vector2(48, 48)),
			Rect2(quadro * 16, 0, 16, 16))
	var xt := retrato.end.x + 12.0
	UI.texto(self, Vector2(painel.position.x + 14.0 + 26.0, retrato.end.y + 12.0), torre.nome_personagem().to_upper(), UI.P, UI.BRANCO)
	UI.texto(self, Vector2(painel.position.x + 14.0 + 26.0, retrato.end.y + 24.0), torre.nome_dificuldade(), UI.P, UI.OURO)
	var y := painel.position.y + 16.0
	for linha in _linhas():
		UI.texto(self, Vector2(xt + 20.0, y), linha[0], UI.P, UI.LUZ, UI.ESQ)
		UI.texto(self, Vector2(painel.end.x - 16.0, y), linha[1], UI.P, UI.BRANCO, UI.DIR)
		draw_rect(Rect2(xt + 20.0, y + 6.0, painel.end.x - 16.0 - xt - 20.0, 1), Color(UI.BORDA, 0.5))
		y += 14.0
	# Melhorias escolhidas
	var melhorias := ", ".join(torre.melhorias_finais) if not torre.melhorias_finais.is_empty() else "NENHUMA"
	UI.texto(self, Vector2(xt + 20.0, y + 2.0), "MELHORIAS", UI.P, UI.LUZ, UI.ESQ)
	UI.texto(self, Vector2(painel.position.x + painel.size.x / 2.0, painel.end.y - 12.0), melhorias, UI.P, UI.VERDE if campeao else UI.BRANCO)

	var rotulos := _rotulos()
	for i in 2:
		UI.botao(self, _rect_botao(i), rotulos[i], i == _sel, false, UI.P, _t)
	if not Jogo.toque:
		UI.texto(self, Vector2(cx, 262), "W/S ou ↑/↓: escolher     ESPAÇO ou A: confirmar", UI.P, UI.BORDA)
