extends Control
## Tela de escolha de classes. Cada jogador escolhe com seus próprios
## controles e confirma com o botão de pulo.

signal pronto

const LARG_PAINEL := 168.0

var _pronto := {1: false, 2: false}
var _t := 0.0
var _saindo := false
var _dados: Array[ClasseDados] = []


func _ready() -> void:
	for i in Jogo.CLASSES.size():
		_dados.append(Jogo.dados_classe(i))


func _process(delta: float) -> void:
	_t += delta
	for n in [1, 2]:
		if _saindo:
			break
		if Input.is_action_just_pressed(Jogo.acao(n, "pular")):
			_pronto[n] = not _pronto[n]
			Jogo.tocar("nivel" if _pronto[n] else "acerto")
		elif not _pronto[n]:
			var passo := 0
			if Input.is_action_just_pressed(Jogo.acao(n, "esquerda")):
				passo = -1
			elif Input.is_action_just_pressed(Jogo.acao(n, "direita")):
				passo = 1
			if passo != 0:
				Jogo.escolha[n] = wrapi(Jogo.escolha[n] + passo, 0, _dados.size())
				Jogo.tocar("pulo")
	if _pronto[1] and _pronto[2] and not _saindo:
		_saindo = true
		await get_tree().create_timer(0.4).timeout
		pronto.emit()
	queue_redraw()


func _draw() -> void:
	var fonte := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color("1a1c2c"))
	_centro(fonte, Vector2(size.x / 2.0, 20), "ARENA PIXEL", 20, Color("ffcd75"))
	_centro(fonte, Vector2(size.x / 2.0, 34), "Escolha sua classe", 8, Color("94b0c2"))
	_painel(fonte, 1, 16.0, "A / D trocar  ·  Espaço confirmar")
	_painel(fonte, 2, size.x - 16.0 - LARG_PAINEL, "← / → trocar  ·  0 confirmar")
	_centro(fonte, Vector2(size.x / 2.0, size.y - 5), "O ataque é automático: chegue perto do inimigo!", 8, Color("566c86"))


func _painel(fonte: Font, n: int, x: float, ajuda: String) -> void:
	var cor: Color = Jogo.COR_TIME[n]
	var d: ClasseDados = _dados[Jogo.escolha[n]]
	var topo := 44.0
	var alto := 146.0
	draw_rect(Rect2(x, topo, LARG_PAINEL, alto), Color("29366f") if _pronto[n] else Color("333c57"))
	draw_rect(Rect2(x, topo, LARG_PAINEL, alto), cor, false, 1.0)
	draw_string(fonte, Vector2(x + 6, topo + 11), "JOGADOR %d" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, cor)

	# Personagem animado (4x)
	var tex := d.textura_p1 if n == 1 else d.textura_p2
	var quadro := 2 + int(_t * 8.0) % 4 if _pronto[n] else int(_t * 2.0) % 2
	var cx := x + LARG_PAINEL / 2.0
	draw_texture_rect_region(tex, Rect2(cx - 24, topo + 14, 48, 48), Rect2(quadro * 16, 0, 16, 16))
	if not _pronto[n]:
		_centro(fonte, Vector2(cx - 44, topo + 40), "<", 16, Color.WHITE)
		_centro(fonte, Vector2(cx + 44, topo + 40), ">", 16, Color.WHITE)

	_centro(fonte, Vector2(cx, topo + 72), d.nome.to_upper(), 12, Color.WHITE)
	draw_multiline_string(fonte, Vector2(x + 6, topo + 86), d.descricao, HORIZONTAL_ALIGNMENT_CENTER,
			LARG_PAINEL - 12, 8, -1, Color("94b0c2"))

	var ataque_vel := 1.0 / d.intervalo_ataque
	var stats := [
		["Vida", d.vida_max / 170.0],
		["Dano", (d.dano * ataque_vel) / 25.0 if d.tipo_ataque != ClasseDados.TipoAtaque.INVOCAR else 0.5],
		["Veloc.", d.velocidade / 110.0],
		["Alcance", d.alcance / 150.0 if d.tipo_ataque != ClasseDados.TipoAtaque.INVOCAR else 1.0],
	]
	var y := topo + 108.0
	for s in stats:
		draw_string(fonte, Vector2(x + 6, y + 6), s[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
		draw_rect(Rect2(x + 50, y, LARG_PAINEL - 58, 5), Color("1a1c2c"))
		draw_rect(Rect2(x + 50, y, (LARG_PAINEL - 58) * clampf(s[1], 0.05, 1.0), 5), cor)
		y += 9.0

	var rodape := "PRONTO!  (pule de novo para cancelar)" if _pronto[n] else ajuda
	_centro(fonte, Vector2(cx, topo + alto + 8), rodape, 8, Color("a7f070") if _pronto[n] else Color("94b0c2"))


func _centro(fonte: Font, pos: Vector2, texto: String, tam: int, cor: Color) -> void:
	var larg := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	draw_string(fonte, pos + Vector2(-larg / 2.0, tam / 3.0), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)
