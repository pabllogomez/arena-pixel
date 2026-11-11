extends Control
## Interface da partida: vida, nível, XP, escolhas de melhoria,
## contagem regressiva e tela de vitória.

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

	var centro := size / 2.0
	if partida.contagem > 0.0:
		var c: float = partida.contagem
		_texto_centro(fonte, centro + Vector2(0, -8), str(ceili(c)), 32, Color.WHITE)
	elif partida.contagem > -0.8:
		_texto_centro(fonte, centro + Vector2(0, -8), "LUTE!", 32, Color("ffcd75"))

	if partida.fim:
		draw_rect(Rect2(0, centro.y - 30, size.x, 52), Color(0, 0, 0, 0.7))
		var v: int = partida.vencedor
		_texto_centro(fonte, centro + Vector2(0, -4), "JOGADOR %d VENCEU!" % v, 20, Jogo.COR_TIME[v])
		_texto_centro(fonte, centro + Vector2(0, 14), "Pular: revanche (mapa novo)   ·   Esc: trocar classes", 8, Color.WHITE)


func _painel(fonte: Font, l: Lutador, n: int) -> void:
	var cor: Color = Jogo.COR_TIME[n]
	var x := 6.0 if n == 1 else size.x - 6.0 - LARG_PAINEL
	draw_rect(Rect2(x - 3, 1, LARG_PAINEL + 6, 22), Color(0, 0, 0, 0.6))
	var titulo := "P%d %s" % [n, l.dados.nome.to_upper()]
	draw_string(fonte, Vector2(x, 9), titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, cor)
	draw_string(fonte, Vector2(x, 9), "Nv %d" % l.nivel, HORIZONTAL_ALIGNMENT_RIGHT, LARG_PAINEL, 8, Color.WHITE)
	# Vida
	draw_rect(Rect2(x, 12, LARG_PAINEL, 5), Color("333c57"))
	draw_rect(Rect2(x, 12, LARG_PAINEL * l.vida / l.vida_max, 5), cor)
	# Experiência
	draw_rect(Rect2(x, 19, LARG_PAINEL, 2), Color("333c57"))
	draw_rect(Rect2(x, 19, LARG_PAINEL * float(l.xp) / l.xp_para_proximo(), 2), Color("a7f070"))

	if l.escolhas.is_empty() or not l.vivo:
		return
	var par: Array = l.escolhas[0]
	var teclas := ["Q", "E"] if n == 1 else ["1", "2"]
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
	draw_string_outline(fonte, p, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, 4, Color("1a1c2c"))
	draw_string(fonte, p, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)
