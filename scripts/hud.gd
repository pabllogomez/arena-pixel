extends Control
## Interface da partida: painéis dos jogadores (retrato, vida, nível, XP),
## cartas de melhoria, cronômetro, anúncios, contagem regressiva e tela de fim.
## Tudo desenhado em pixel art com as peças de `UI`.

const LARG_PAINEL := 130.0
const ALT_PAINEL := 24.0
const LARG_CARTA := 184.0
const ALT_CARTA := 38.0

var partida: Node

var _t := 0.0
# Animações por jogador
var _rastro := {1: 1.0, 2: 1.0}       ## vida "antiga" (pedaço branco que escorre)
var _espera_rastro := {1: 0.0, 2: 0.0}
var _vida_vista := {1: 1.0, 2: 1.0}
var _xp_visto := {1: 0.0, 2: 0.0}
var _nivel_visto := {1: 1, 2: 1}
var _pulso := {1: 0.0, 2: 0.0}        ## brilho ao subir de nível
var _tranco := {1: 0.0, 2: 0.0}       ## painel treme ao apanhar
var _cartas_t := {1: 0.0, 2: 0.0}     ## tempo desde que as cartas apareceram
var _cartas_qtd := {1: 0, 2: 0}
# Anúncio
var _anuncio_max := 0.0
var _anuncio_ant := 0.0
var _fim_t := 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_PASS  # recebe cliques/toques nas cartas de melhoria


func _process(delta: float) -> void:
	_t += delta
	if partida != null:
		_animar(delta)
	queue_redraw()


func _animar(delta: float) -> void:
	for n in [1, 2]:
		if not partida.jogadores.has(n):
			continue
		var l: Lutador = partida.jogadores[n]
		var f: float = clampf(l.vida / l.vida_max, 0.0, 1.0)
		if f < _vida_vista[n] - 0.001:
			_espera_rastro[n] = 0.35
			_tranco[n] = 0.18
		_vida_vista[n] = f
		if _rastro[n] < f:
			_rastro[n] = f
		elif _espera_rastro[n] > 0.0:
			_espera_rastro[n] -= delta
		else:
			_rastro[n] = move_toward(_rastro[n], f, delta * 0.9)
		_tranco[n] = maxf(_tranco[n] - delta, 0.0)
		# XP enche aos poucos; ao subir de nível a barra pisca
		var alvo_xp := float(l.xp) / l.xp_para_proximo()
		if l.nivel != _nivel_visto[n]:
			_nivel_visto[n] = l.nivel
			_pulso[n] = 0.6
			_xp_visto[n] = 0.0
		_xp_visto[n] = move_toward(_xp_visto[n], alvo_xp, delta * 1.5)
		_pulso[n] = maxf(_pulso[n] - delta, 0.0)
		# Cartas deslizam para dentro sempre que aparece uma escolha nova
		var qtd: int = l.escolhas.size() if mostra_cartas(n) else 0
		if qtd != _cartas_qtd[n]:
			_cartas_qtd[n] = qtd
			_cartas_t[n] = 0.0
		_cartas_t[n] += delta
	# Anúncio novo: guarda a duração para animar a entrada
	if partida.anuncio_t > _anuncio_ant + 0.05:
		_anuncio_max = partida.anuncio_t
	_anuncio_ant = partida.anuncio_t
	if partida.fim:
		_fim_t += delta


func _draw() -> void:
	if partida == null:
		return
	for n in [1, 2]:
		if partida.jogadores.has(n):
			_painel(partida.jogadores[n], n)
	_cronometro()
	_contagem()
	_anuncio()
	for n in [1, 2]:
		if mostra_cartas(n):
			_cartas(n)
	if partida.fim:
		_fim()


# ------------------------------------------------------------------ Painel do jogador

func _painel(l: Lutador, n: int) -> void:
	var cor: Color = Jogo.COR_TIME[n]
	var dir := n == 2  # o painel do jogador 2 é espelhado
	var tranco := Vector2.ZERO
	if _tranco[n] > 0.0 and Jogo.impacto:
		tranco = Vector2(1 if int(_t * 40.0) % 2 == 0 else -1, 0)
	var x0 := (size.x - 2.0 - LARG_PAINEL if dir else 2.0) + tranco.x
	UI.moldura(self, Rect2(x0, 0, LARG_PAINEL, ALT_PAINEL), Color(UI.TINTA, 0.92), UI.BORDA.darkened(0.25), UI.BORDA)

	# Retrato da classe atual, com a borda na cor do time
	var rx := x0 + LARG_PAINEL - 22.0 if dir else x0 + 2.0
	var retrato := Rect2(rx, 2, 20, 20)
	UI.moldura(self, retrato, Color("29366f") if n == 1 else Color("5d275d"), cor, cor.lightened(0.4))
	if l.vivo:
		draw_texture_rect_region(l.sprite.texture, Rect2(retrato.position + Vector2(2, 2), Vector2(16, 16)), Rect2(0, 0, 16, 16))
	else:
		# Caveirinha: um X no retrato de quem caiu
		for i in 6:
			draw_rect(Rect2(retrato.position + Vector2(7 + i, 7 + i), Vector2(1, 1)), UI.VERMELHO)
			draw_rect(Rect2(retrato.position + Vector2(12 - i, 7 + i), Vector2(1, 1)), UI.VERMELHO)

	# Nome, classe e nível
	var bx := x0 + 4.0 if dir else x0 + 25.0   # começo das barras
	var larg_barra := LARG_PAINEL - 29.0
	var titulo := "%s %s" % [l.nome_jogador(), l.dados.nome.to_upper()]
	var nivel := "Nv %d" % l.nivel
	var cor_nivel := UI.BRANCO if _pulso[n] > 0.0 and int(_t * 12.0) % 2 == 0 else UI.OURO
	if dir:
		UI.texto(self, Vector2(bx + larg_barra, 6), titulo, UI.P, cor, UI.DIR)
		UI.texto(self, Vector2(bx, 6), nivel, UI.P, cor_nivel, UI.ESQ)
	else:
		UI.texto(self, Vector2(bx, 6), titulo, UI.P, cor, UI.ESQ)
		UI.texto(self, Vector2(bx + larg_barra, 6), nivel, UI.P, cor_nivel, UI.DIR)

	# Vida: pisca em vermelho quando está acabando
	var f: float = _vida_vista[n]
	var cor_vida := cor
	if l.vivo and f < 0.3 and int(_t * 5.0) % 2 == 0:
		cor_vida = UI.VERMELHO
	UI.barra(self, Rect2(bx, 12, larg_barra, 6), f, cor_vida, _rastro[n], dir)
	# Marcas de quarto em quarto
	for q in [0.25, 0.5, 0.75]:
		var mx := bx + roundf(larg_barra * (1.0 - q if dir else q))
		draw_rect(Rect2(mx, 12, 1, 2), Color(UI.TINTA, 0.6))
	# Experiência
	var cor_xp := UI.BRANCO if _pulso[n] > 0.0 and int(_t * 12.0) % 2 == 0 else UI.VERDE
	UI.barra(self, Rect2(bx, 20, larg_barra, 2), 1.0 if _pulso[n] > 0.3 else _xp_visto[n], cor_xp, -1.0, dir)

	# Efeito de item ativo, com o tempo que falta
	if l.efeito != "" and l.vivo:
		var txt := "%s  %ds" % [l.nome_efeito(), ceili(l.efeito_t)]
		if dir:
			UI.texto(self, Vector2(x0 + LARG_PAINEL - 2.0, 30), txt, UI.P, Color("f4a2f4"), UI.DIR)
		else:
			UI.texto(self, Vector2(x0 + 2.0, 30), txt, UI.P, Color("f4a2f4"), UI.ESQ)


# ------------------------------------------------------------------ Cronômetro e avisos

func _cronometro() -> void:
	var x := roundf(size.x / 2.0)
	var caixa := Rect2(x - 23, 0, 46, 17)
	if partida.morte_subita:
		var aceso := int(_t * 4.0) % 2 == 0
		UI.moldura(self, caixa, Color("3a1420"), UI.VERMELHO, Color("ef7d57"))
		UI.texto(self, Vector2(x, 8), "SÚBITA", UI.P, UI.BRANCO if aceso else Color("ef7d57"))
		return
	var t: float = ceilf(partida.tempo_restante)
	var texto := "%d:%02d" % [int(t) / 60, int(t) % 60]
	var cor := UI.BRANCO
	var borda := UI.BORDA
	var sobe := 0.0
	if t <= 30.0:
		cor = Color("ef7d57") if int(t) % 2 == 0 else UI.OURO
		borda = Color("ef7d57")
	if t <= 10.0:
		# Últimos segundos: o número dá um pulinho a cada batida
		borda = UI.VERMELHO
		if fmod(partida.tempo_restante, 1.0) > 0.85:
			sobe = -1.0
	UI.moldura(self, caixa, Color(UI.TINTA, 0.92), borda, borda.lightened(0.3))
	UI.texto(self, Vector2(x, 8 + sobe), texto, UI.M, cor)


func _contagem() -> void:
	var centro := (size / 2.0).round()
	var c: float = partida.contagem
	if partida.tutorial_aberto:
		return
	if c > 0.0:
		var batida := 1.0 - (c - floorf(c))  # 0 no começo de cada número
		if c >= 3.0:
			batida = 0.0
		var tam := 48 if batida < 0.07 else (40 if batida < 0.14 else 32)
		UI.texto(self, centro + Vector2(0, -10), str(ceili(c)), tam, UI.BRANCO)
		UI.texto(self, centro + Vector2(0, 16), "PREPARAR", UI.P, UI.LUZ)
	elif c > -0.8:
		var e := -c
		var tam2 := 48 if e < 0.07 else (40 if e < 0.14 else 32)
		var alt := minf(e / 0.1, 1.0) * 34.0
		UI.faixa(self, centro.y - 10 - alt / 2.0, alt, size.x, UI.OURO)
		if e < 0.7 or int(_t * 20.0) % 2 == 0:
			UI.texto(self, centro + Vector2(0, -10), "LUTE!", tam2, UI.OURO)


func _anuncio() -> void:
	if partida.anuncio_t <= 0.0 or partida.fim:
		return
	var resta: float = partida.anuncio_t
	var passou := maxf(_anuncio_max - resta, 0.0)
	var abre := minf(minf(passou / 0.12, resta / 0.12), 1.0)
	var y := roundf(size.y / 2.0) - 54.0
	var cor: Color = partida.anuncio_cor
	UI.faixa(self, y - 11.0 * abre, 22.0 * abre, size.x, cor)
	if abre < 1.0:
		return
	# O texto entra deslizando da direita e freia no centro
	var entra := clampf((passou - 0.12) / 0.16, 0.0, 1.0)
	var desliza := roundf(pow(1.0 - entra, 2.0) * 120.0)
	var texto: String = partida.anuncio
	var tam := UI.M if UI.largura(texto, UI.M) < size.x - 16.0 else UI.P
	UI.texto(self, Vector2(size.x / 2.0 + desliza, y), texto, tam, cor.lightened(0.25))


# ------------------------------------------------------------------ Cartas de melhoria

func mostra_cartas(n: int) -> bool:
	if partida == null or not partida.jogadores.has(n):
		return false
	var l: Lutador = partida.jogadores[n]
	return not l.escolhas.is_empty() and l.vivo and partida.e_local(n) and not partida.fim


func _cartas_na_esquerda(n: int) -> bool:
	# Em rede, as cartas de quem está olhando a tela ficam sempre na esquerda
	return n == 1 or partida.rede != ""


func rects_cartas(n: int) -> Array:
	## Duas cartas grandes empilhadas, centralizadas na vertical
	## (P1 no lado esquerdo, P2 no direito).
	var x := 6.0 if _cartas_na_esquerda(n) else size.x - 6.0 - LARG_CARTA
	var y0 := roundf(size.y / 2.0) - ALT_CARTA - 2.0
	return [Rect2(x, y0, LARG_CARTA, ALT_CARTA), Rect2(x, y0 + ALT_CARTA + 5.0, LARG_CARTA, ALT_CARTA)]


func _cartas(n: int) -> void:
	var l: Lutador = partida.jogadores[n]
	var par: Array = l.escolhas[0]
	var rects := rects_cartas(n)
	var lado := -1.0 if _cartas_na_esquerda(n) else 1.0
	var usa_p1: bool = n == 1 or partida.rede != ""  # em rede, cada um joga com os controles do P1
	var teclas := ["Q", "E"] if usa_p1 else ["1", "2"]
	var aceso := int(_t * 3.0) % 2 == 0
	for i in 2:
		# Entrada: cada carta desliza da lateral, a de baixo um instante depois
		var e := clampf((_cartas_t[n] - i * 0.06) / 0.18, 0.0, 1.0)
		var fora := roundf(pow(1.0 - e, 2.0) * (LARG_CARTA + 12.0)) * lado
		var r: Rect2 = rects[i]
		r.position.x += fora
		var m: Dictionary = par[i]
		UI.moldura(self, r, Color("23263a"), UI.VERDE if aceso else Color("38b764"), UI.BRANCO if aceso else UI.VERDE)
		var x := r.position.x + 7.0
		var meio := r.position.y + r.size.y / 2.0
		# Ícone da melhoria num quadrinho
		var quadro := Rect2(x, meio - 10.0, 20, 20)
		UI.moldura(self, quadro, UI.TINTA, UI.BORDA, UI.LUZ)
		UI.icone(self, quadro.position + Vector2(3, 3), m["id"])
		x += 25.0
		var nome: String = m["nome"].to_upper()
		var cabe := UI.largura(nome, UI.M) <= r.end.x - x - 4.0
		UI.texto(self, Vector2(x, meio - 7.0), nome, UI.M if cabe else UI.P, UI.BRANCO, UI.ESQ)
		UI.texto(self, Vector2(x, meio + 9.0), m["desc"], UI.P, UI.LUZ, UI.ESQ)
		if not (Jogo.toque and usa_p1):
			# Tecla correspondente, presa no canto da carta
			UI.tecla(self, Vector2(r.end.x - 9.0, r.position.y + 2.0), teclas[i])
		if i == 0 and e >= 1.0:
			var titulo := "SUBIU DE NÍVEL!"
			if l.escolhas.size() > 1:
				titulo += "  (+%d)" % (l.escolhas.size() - 1)
			UI.texto(self, Vector2(r.position.x + 3.0, r.position.y - 8.0), titulo, UI.P, UI.VERDE if aceso else UI.BRANCO, UI.ESQ)


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


# ------------------------------------------------------------------ Fim de partida

func _fim() -> void:
	var centro := (size / 2.0).round()
	var v: int = partida.vencedor
	var texto := "EMPATE!"
	var classe := ""
	var cor := UI.BRANCO
	if v != 0:
		var l: Lutador = partida.jogadores[v]
		cor = Jogo.COR_TIME[v]
		classe = l.dados.nome.to_upper()
		if partida.rede != "":
			texto = "VOCÊ VENCEU!" if v == Rede.numero_local() else "SEU AMIGO VENCEU!"
		elif Jogo.solo:
			texto = "VOCÊ VENCEU!" if v == 1 else "A MÁQUINA VENCEU!"
		else:
			texto = "JOGADOR %d VENCEU!" % v
	# A faixa abre do meio; depois o texto cai no lugar
	var abre := clampf((_fim_t - 0.5) / 0.15, 0.0, 1.0)
	if abre <= 0.0:
		return
	UI.faixa(self, centro.y - 4.0 - 30.0 * abre, 60.0 * abre, size.x, cor)
	if abre < 1.0:
		return
	var e := clampf((_fim_t - 0.65) / 0.12, 0.0, 1.0)
	var tam := 40 if e < 0.5 else (32 if e < 1.0 else UI.G)
	UI.texto(self, centro + Vector2(0, -14), texto, tam, cor.lightened(0.2))
	if _fim_t < 0.9:
		return
	if classe != "":
		# Retrato do vencedor e a classe com que venceu
		var tex: Texture2D = partida.jogadores[v].sprite.texture
		var quadro := 2 + int(_t * 8.0) % 4
		var larg_classe := UI.largura(classe, UI.P)
		var x := centro.x - (larg_classe + 20.0) / 2.0
		draw_texture_rect_region(tex, Rect2(roundf(x), centro.y - 3, 16, 16), Rect2(quadro * 16, 0, 16, 16))
		UI.texto(self, Vector2(x + 20.0, centro.y + 6), classe, UI.P, UI.BRANCO, UI.ESQ)
	var dica := "Revanche joga em um mapa novo"
	if partida.rede == "convidado":
		dica = "Aguardando quem criou a partida pedir revanche..."
	elif not Jogo.toque:
		dica = "ESPAÇO: revanche (mapa novo)     ESC: menu"
	if int(_t * 2.0) % 4 != 3:
		UI.texto(self, centro + Vector2(0, 19), dica, UI.P, UI.LUZ)
