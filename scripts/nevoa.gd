extends Node2D
## Fumaça tóxica da Morte Súbita: sobe do chão e machuca quem estiver dentro.
## Desenhada em blocos (sem curvas lisas), com borda ondulada em degraus,
## faixa pontilhada e bolhas que estouram na superfície.

const BLOCO := 4.0

var partida: Node
var particulas: Particulas
var _t := 0.0
var _t_bolha := 0.0


func _process(delta: float) -> void:
	_t += delta
	if partida == null or not partida.morte_subita:
		return
	queue_redraw()
	# Bolhas e vapores saindo da superfície
	var topo: float = partida.nivel_nevoa
	if particulas != null and topo < GeradorArena.ALTURA:
		_t_bolha -= delta
		if _t_bolha <= 0.0:
			_t_bolha = 0.06
			particulas.fx("bolha", Vector2(randf() * GeradorArena.LARGURA, topo + 1.0))


func _onda(x: float) -> float:
	return roundf(1.6 * sin(_t * 2.6 + x * 0.11) + 1.0 * sin(_t * 1.7 - x * 0.23))


func _draw() -> void:
	if partida == null or not partida.morte_subita:
		return
	var topo: float = floorf(partida.nivel_nevoa)
	var larg := float(GeradorArena.LARGURA)
	var base := float(GeradorArena.ALTURA)
	if topo >= base:
		return
	var corpo := Color(0.22, 0.72, 0.39, 0.42)
	var faixa := Color(0.65, 0.94, 0.44, 0.38)
	var crista := Color(0.80, 1.0, 0.60, 0.85)
	var x := 0.0
	var passo := 0
	while x < larg:
		var y := topo + _onda(x)
		draw_rect(Rect2(x, y, BLOCO, base - y), corpo)
		draw_rect(Rect2(x, y, BLOCO, 1), crista)
		# Faixa pontilhada logo abaixo da crista
		for linha in 3:
			var desloc := 2.0 if (linha + passo) % 2 == 0 else 0.0
			draw_rect(Rect2(x + desloc, y + 2.0 + linha * 2.0, 2, 2), faixa)
		x += BLOCO
		passo += 1
	# Bolhas subindo por dentro
	for i in 16:
		var bx := floorf(fmod(i * 53.0 + _t * 4.0 * (1 + i % 3), larg))
		var altura := maxf(base - topo, 1.0)
		var by := floorf(base - fmod(i * 37.0 + _t * (10.0 + i % 4 * 5.0), altura))
		var tam := 2.0 if i % 3 == 0 else 1.0
		draw_rect(Rect2(bx, by, tam, tam), Color(0.80, 1.0, 0.60, 0.6))
