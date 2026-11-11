extends Control
## Interface da partida: vida, nível, XP, escolhas de melhoria, cronômetro,
## anúncios, contagem regressiva e tela de fim de partida.

const LARG_PAINEL := 112.0
const LARG_ESCOLHA := 150.0

var partida: Node


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

	if partida.fim:
		draw_rect(Rect2(0, centro.y - 30, size.x, 52), Color(0, 0, 0, 0.7))
		var v: int = partida.vencedor
		var texto := "EMPATE!"
		var cor := Color.WHITE
		if v != 0:
			var l: Lutador = partida.jogadores[v]
			cor = Jogo.COR_TIME[v]
			if Jogo.solo:
				texto = "VOCÊ VENCEU!" if v == 1 else "A MÁQUINA VENCEU!"
			else:
				texto = "JOGADOR %d VENCEU!" % v
			texto += "  (" + l.dados.nome.to_upper() + ")"
		_texto_centro(fonte, centro + Vector2(0, -4), texto, 18, cor)
		if not Jogo.toque:
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

	# Escolha de melhoria (só para humanos; o bot escolhe sozinho)
	if l.escolhas.is_empty() or not l.vivo or l.controle is ControleBot or partida.fim:
		return
	var par: Array = l.escolhas[0]
	var teclas := ["Q", "E"] if n == 1 else ["1", "2"]
	if Jogo.toque and n == 1:
		teclas = ["toque", "toque"]
	var ex := 6.0 if n == 1 else size.x - 6.0 - LARG_ESCOLHA
	var y := 27.0
	draw_rect(Rect2(ex - 3, y, LARG_ESCOLHA + 6, 31), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(ex - 3, y, LARG_ESCOLHA + 6, 1), Color("a7f070"))
	var extra := "" if l.escolhas.size() == 1 else "  (+%d)" % (l.escolhas.size() - 1)
	draw_string(fonte, Vector2(ex, y + 9), "SUBIU DE NÍVEL! Escolha:" + extra,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("a7f070"))
	for i in 2:
		var m: Dictionary = par[i]
		var linha := "[%s] %s: %s" % [teclas[i], m["nome"], m["desc"]]
		draw_string(fonte, Vector2(ex, y + 19 + i * 9), linha, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)


func _texto_centro(fonte: Font, pos: Vector2, texto: String, tam: int, cor: Color) -> void:
	var larg := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	var p := pos + Vector2(-larg / 2.0, tam / 3.0)
	draw_string_outline(fonte, p, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, 4, Color(Color("1a1c2c"), cor.a))
	draw_string(fonte, p, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)
