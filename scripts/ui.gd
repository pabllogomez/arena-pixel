class_name UI
extends RefCounted
## Peças de interface em pixel art usadas por todas as telas: fonte pixel,
## texto com contorno de 1 px, molduras de cantos chanfrados, botões e barras.
## Tudo é desenhado preso à grade (posições arredondadas), sem curvas lisas.

const FONTE: FontFile = preload("res://assets/fontes/Tiny5-Regular.ttf")

# Paleta da interface
const TINTA := Color("1a1c2c")
const FUNDO := Color("23263a")
const BORDA := Color("566c86")
const LUZ := Color("94b0c2")
const BRANCO := Color("f4f4f4")
const OURO := Color("ffcd75")
const VERDE := Color("a7f070")
const VERMELHO := Color("b13e53")
const APAGADO := Color("333c57")

enum {ESQ = -1, CENTRO = 0, DIR = 1}

## A fonte foi desenhada para 8 px: só usar múltiplos (8, 16, 24, 32...)
const P := 8
const M := 16
const G := 24
const GG := 32


static func largura(texto: String, tam := P) -> float:
	return FONTE.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x


static func texto(ci: CanvasItem, pos: Vector2, t: String, tam := P, cor := BRANCO,
		alinhar := CENTRO, contorno := true, cor_contorno := TINTA) -> void:
	## `pos.y` é o meio da linha; `pos.x` é o centro, a esquerda ou a direita
	## do texto, conforme `alinhar`.
	var larg := largura(t, tam)
	var x := pos.x
	if alinhar == CENTRO:
		x -= larg / 2.0
	elif alinhar == DIR:
		x -= larg
	var e := tam / 8                       # tamanho de 1 "pixel" da fonte
	var p := Vector2(roundf(x), roundf(pos.y) + 3 * e)
	if contorno:
		var c := Color(cor_contorno, cor.a)
		for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(1, 1)]:
			ci.draw_string(FONTE, p + d * e, t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, c)
	ci.draw_string(FONTE, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)


static func moldura(ci: CanvasItem, r: Rect2, fundo := FUNDO, borda := BORDA, brilho := LUZ) -> void:
	## Painel com contorno escuro, borda de 1 px e cantos chanfrados.
	r = Rect2(r.position.round(), r.size.round())
	# Contorno escuro (cantos cortados)
	ci.draw_rect(Rect2(r.position + Vector2(1, 0), r.size - Vector2(2, 0)), TINTA)
	ci.draw_rect(Rect2(r.position + Vector2(0, 1), r.size - Vector2(0, 2)), TINTA)
	# Borda
	var b := r.grow(-1)
	ci.draw_rect(Rect2(b.position + Vector2(1, 0), b.size - Vector2(2, 0)), borda)
	ci.draw_rect(Rect2(b.position + Vector2(0, 1), b.size - Vector2(0, 2)), borda)
	# Luz em cima, sombra embaixo (dá volume à borda)
	ci.draw_rect(Rect2(b.position + Vector2(1, 0), Vector2(b.size.x - 2, 1)), brilho)
	ci.draw_rect(Rect2(b.position + Vector2(1, b.size.y - 1), Vector2(b.size.x - 2, 1)), borda.darkened(0.35))
	# Miolo
	ci.draw_rect(r.grow(-2), fundo)


static func botao(ci: CanvasItem, r: Rect2, rotulo: String, selecionado: bool, destaque := false,
		tam := P, t := 0.0) -> void:
	## Botão de menu. O selecionado ganha borda dourada e setas que pulsam.
	var fundo := Color("29366f") if selecionado else FUNDO
	var borda := OURO if selecionado else BORDA
	var brilho := BRANCO if selecionado else LUZ
	if destaque:
		fundo = Color("38b764") if selecionado else Color("257179")
		borda = VERDE if selecionado else Color("38b764")
	moldura(ci, r, fundo, borda, brilho)
	texto(ci, r.get_center(), rotulo, tam, BRANCO if selecionado or destaque else LUZ)
	if selecionado:
		var vai := 1.0 if int(t * 4.0) % 2 == 0 else 0.0
		var y := roundf(r.get_center().y)
		seta(ci, Vector2(r.position.x - 6.0 - vai, y), 1.0, OURO)
		seta(ci, Vector2(r.end.x + 5.0 + vai, y), -1.0, OURO)


static func seta(ci: CanvasItem, pos: Vector2, lado: float, cor: Color) -> void:
	## Setinha de 3 px apontando para `lado` (1 = direita, -1 = esquerda).
	pos = pos.round()
	for i in 3:
		ci.draw_rect(Rect2(pos.x + lado * i - (0.0 if lado > 0.0 else 1.0), pos.y - 2 + i, 1, 5 - 2 * i), TINTA.lerp(cor, 1.0))
	# contorno simples para destacar em qualquer fundo
	ci.draw_rect(Rect2(pos.x - lado - (0.0 if lado > 0.0 else 1.0), pos.y - 3, 1, 7), TINTA)


static func barra(ci: CanvasItem, r: Rect2, fracao: float, cor: Color, rastro := -1.0,
		cor_rastro := BRANCO) -> void:
	## Barra com fundo escuro, brilho em cima e sombra embaixo. `rastro` é a
	## fração antiga (mostra em branco o pedaço que acabou de ser perdido).
	r = Rect2(r.position.round(), r.size.round())
	ci.draw_rect(r.grow(1), TINTA)
	ci.draw_rect(r, APAGADO)
	fracao = clampf(fracao, 0.0, 1.0)
	var larg := roundf(r.size.x * fracao)
	if fracao > 0.0:
		larg = maxf(larg, 1.0)
	if rastro > fracao:
		ci.draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * clampf(rastro, 0.0, 1.0)), r.size.y)), cor_rastro)
	if larg > 0.0:
		ci.draw_rect(Rect2(r.position, Vector2(larg, r.size.y)), cor)
		if r.size.y >= 3.0:
			ci.draw_rect(Rect2(r.position, Vector2(larg, 1)), cor.lightened(0.35))
			ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(larg, 1)), cor.darkened(0.3))


static func faixa(ci: CanvasItem, y: float, altura: float, largura_tela: float, cor: Color) -> void:
	## Faixa escura de lado a lado com filetes coloridos (anúncios, fim de partida).
	y = roundf(y)
	altura = roundf(altura)
	if altura < 2.0:
		return
	ci.draw_rect(Rect2(0, y, largura_tela, altura), Color(TINTA, 0.9))
	ci.draw_rect(Rect2(0, y, largura_tela, 1), cor)
	ci.draw_rect(Rect2(0, y + altura - 1, largura_tela, 1), cor)
	if altura >= 8.0:
		ci.draw_rect(Rect2(0, y + 2, largura_tela, 1), Color(cor, 0.35))
		ci.draw_rect(Rect2(0, y + altura - 3, largura_tela, 1), Color(cor, 0.35))


static func tecla(ci: CanvasItem, centro: Vector2, letra: String) -> void:
	## Desenho de uma tecla do teclado com a letra dentro.
	var larg := maxf(11.0, largura(letra, P) + 6.0)
	var r := Rect2((centro - Vector2(larg / 2.0, 6)).round(), Vector2(larg, 12))
	ci.draw_rect(Rect2(r.position + Vector2(1, 0), r.size - Vector2(2, 0)), TINTA)
	ci.draw_rect(Rect2(r.position + Vector2(0, 1), r.size - Vector2(0, 2)), TINTA)
	ci.draw_rect(Rect2(r.position + Vector2(1, 1), r.size - Vector2(2, 2)), BORDA)
	ci.draw_rect(Rect2(r.position + Vector2(1, 1), r.size - Vector2(2, 4)), BRANCO)
	texto(ci, r.get_center() + Vector2(0.5, -1), letra, P, TINTA, CENTRO, false)
