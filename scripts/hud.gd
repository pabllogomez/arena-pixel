extends Control
## Interface da partida: vida, nível, XP, escolhas de melhoria, cronômetro,
## anúncios, contagem regressiva e tela de fim de partida.

const LARG_PAINEL := 112.0
const LARG_CARTA := 168.0
const ALT_CARTA := 36.0

var partida: Node


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_PASS  # recebe cliques/toques nas cartas de melhoria


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if partida == null:
		return
	var fonte := ThemeDB.fallback_font
	for n in [1, 2]:
		if partida.jogadores.has(n):
			_painel(fonte, partida.jogadores[n], n)
	_cronometro(fonte)

	var centro := size / 2.0
	if partida.contagem > 0.0:
		var c: float = partida.contagem
		_texto_centro(fonte, centro + Vector2(0, -8), str(ceili(c)), 32, Color.WHITE)
	elif partida.contagem > -0.8:
		_texto_centro(fonte, centro + Vector2(0, -8), "LUTE!", 32, Color("ffcd75"))

	if partida.anuncio_t > 0.0 and not partida.fim:
		var a: float = clampf(partida.anuncio_t * 2.0, 0.0, 1.0)
		var cor: Color = partida.anuncio_cor
		_texto_centro(fonte, centro + Vector2(0, -30), partida.anuncio, 16, Color(cor, a))

	for n in [1, 2]:
		if mostra_cartas(n):
			_cartas(fonte, n)

	if partida.fim:
		draw_rect(Rect2(0, centro.y - 30, size.x, 52), Color(0, 0, 0, 0.7))
		var v: int = partida.vencedor
		var texto := "EMPATE!"
		var cor := Color.WHITE
		if v != 0:
			var l: Lutador = partida.jogadores[v]
			cor = Jogo.COR_TIME[v]
			if partida.rede != "":
				texto = "VOCÊ VENCEU!" if v == Rede.numero_local() else "SEU AMIGO VENCEU!"
			elif Jogo.solo:
				texto = "VOCÊ VENCEU!" if v == 1 else "A MÁQUINA VENCEU!"
			else:
				texto = "JOGADOR %d VENCEU!" % v
			texto += "  (" + l.dados.nome.to_upper() + ")"
		_texto_centro(fonte, centro + Vector2(0, -4), texto, 18, cor)
		if partida.rede == "convidado":
			_texto_centro(fonte, centro + Vector2(0, 14), "Aguardando quem criou a partida pedir revanche...", 8, Color.WHITE)
		elif not Jogo.toque:
			_texto_centro(fonte, centro + Vector2(0, 14), "Espaço: revanche (mapa novo)   ·   Esc: menu", 8, Color.WHITE)
		else:
			_texto_centro(fonte, centro + Vector2(0, 14), "Revanche joga em um mapa novo", 8, Color.WHITE)


func _cronometro(fonte: Font) -> void:
	var x := size.x / 2.0
	draw_rect(Rect2(x - 24, 1, 48, 14), Color(0, 0, 0, 0.6))
	if partida.morte_subita:
		var pisca := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 120.0)
		_texto_centro(fonte, Vector2(x, 8), "SÚBITA", 8, Color(Color("b13e53"), pisca))
		return
	var t: float = ceilf(partida.tempo_restante)
	var texto := "%d:%02d" % [int(t) / 60, int(t) % 60]
	var cor := Color.WHITE
	if t <= 30.0:
		cor = Color("ef7d57") if int(t) % 2 == 0 else Color("ffcd75")
	_texto_centro(fonte, Vector2(x, 8), texto, 10, cor)


func _painel(fonte: Font, l: Lutador, n: int) -> void:
	var cor: Color = Jogo.COR_TIME[n]
	var x := 6.0 if n == 1 else size.x - 6.0 - LARG_PAINEL
	draw_rect(Rect2(x - 3, 1, LARG_PAINEL + 6, 22), Color(0, 0, 0, 0.6))
	var titulo := "%s %s" % [l.nome_jogador(), l.dados.nome.to_upper()]
	draw_string(fonte, Vector2(x, 9), titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, cor)
	draw_string(fonte, Vector2(x, 9), "Nv %d" % l.nivel, HORIZONTAL_ALIGNMENT_RIGHT, LARG_PAINEL, 8, Color.WHITE)
	# Vida
	draw_rect(Rect2(x, 12, LARG_PAINEL, 5), Color("333c57"))
	draw_rect(Rect2(x, 12, LARG_PAINEL * l.vida / l.vida_max, 5), cor)
	# Experiência
	draw_rect(Rect2(x, 19, LARG_PAINEL, 2), Color("333c57"))
	draw_rect(Rect2(x, 19, LARG_PAINEL * float(l.xp) / l.xp_para_proximo(), 2), Color("a7f070"))

	# As cartas de melhoria são desenhadas em _cartas() (ficam por cima de tudo)


func mostra_cartas(n: int) -> bool:
	if partida == null or not partida.jogadores.has(n):
		return false
	var l: Lutador = partida.jogadores[n]
	return not l.escolhas.is_empty() and l.vivo and partida.e_local(n) and not partida.fim


func rects_cartas(n: int) -> Array:
	## Duas cartas grandes empilhadas, centralizadas na vertical
	## (P1 no lado esquerdo, P2 no direito).
	# Em rede, as cartas de quem está olhando a tela ficam sempre na esquerda
	var esquerda: bool = n == 1 or partida.rede != ""
	var x := 8.0 if esquerda else size.x - 8.0 - LARG_CARTA
	var y0 := size.y / 2.0 - ALT_CARTA - 2.0
	return [Rect2(x, y0, LARG_CARTA, ALT_CARTA), Rect2(x, y0 + ALT_CARTA + 6.0, LARG_CARTA, ALT_CARTA)]


func _cartas(fonte: Font, n: int) -> void:
	var l: Lutador = partida.jogadores[n]
	var par: Array = l.escolhas[0]
	var rects := rects_cartas(n)
	var pulso := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 160.0)
	var verde := Color("a7f070")
	var titulo := "SUBIU DE NÍVEL!"
	if l.escolhas.size() > 1:
		titulo += "  (+%d)" % (l.escolhas.size() - 1)
	var r0: Rect2 = rects[0]
	draw_string_outline(fonte, r0.position + Vector2(2, -6), titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 4, Color("1a1c2c"))
	draw_string(fonte, r0.position + Vector2(2, -6), titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, verde)
	var usa_p1: bool = n == 1 or partida.rede != ""  # em rede, cada um joga com os controles do P1
	var teclas := ["Q", "E"] if usa_p1 else ["1", "2"]
	for i in 2:
		var r: Rect2 = rects[i]
		var m: Dictionary = par[i]
		draw_rect(r, Color(0.06, 0.06, 0.09, 1.0))
		draw_rect(r, Color(verde, pulso), false, 1.0)
		var tx := r.position.x + 8.0
		if not (Jogo.toque and usa_p1):
			# Tecla correspondente
			var badge := Rect2(r.position + Vector2(6, r.size.y / 2.0 - 8), Vector2(16, 16))
			draw_rect(badge, Color("333c57"))
			draw_rect(badge, Color(1, 1, 1, 0.4), false, 1.0)
			var lt := fonte.get_string_size(teclas[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(fonte, badge.get_center() + Vector2(-lt / 2.0, 4), teclas[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
			tx = badge.end.x + 6.0
		draw_string(fonte, Vector2(tx, r.position.y + 15), m["nome"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		draw_string(fonte, Vector2(tx, r.position.y + 28), m["desc"], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("94b0c2"))


func _gui_input(event: InputEvent) -> void:
	# Clique ou toque numa carta escolhe a melhoria
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for n in [1, 2]:
			if not mostra_cartas(n):
				continue
			var rects := rects_cartas(n)
			for i in 2:
				var r: Rect2 = rects[i]
				if r.has_point(event.position):
					partida.escolher(n, i)
					accept_event()
					return


func _texto_centro(fonte: Font, pos: Vector2, texto: String, tam: int, cor: Color) -> void:
	var larg := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	var p := pos + Vector2(-larg / 2.0, tam / 3.0)
	draw_string_outline(fonte, p, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, 4, Color(Color("1a1c2c"), cor.a))
	draw_string(fonte, p, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)
