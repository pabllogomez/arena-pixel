class_name SeguidorCaminho
extends RefCounted
## Segue um caminho da Navegacao, dizendo a cada quadro para onde andar,
## quando pular e quando descer. Usado pelo bot e pelos lacaios do Rei.

var nav: Navegacao
var usar_portas := false
var caminho: Array = []
## Fica true quando o seguidor percebe que precisa de um caminho novo.
var replanejar := false

var _preso_t := 0.0
var _ultima_pos := Vector2.ZERO


func _init(navegacao: Navegacao) -> void:
	nav = navegacao


func ir_para(origem: Vector2i, destino: Vector2i) -> void:
	caminho = nav.caminho(origem, destino, usar_portas)
	replanejar = false


func chegou() -> bool:
	return caminho.is_empty()


func passo(corpo: CharacterBody2D, delta: float) -> Dictionary:
	var r := {"eixo": 0.0, "pular": false, "descer": false}
	var no := nav.no_de_posicao(corpo.position)
	var no_chao := corpo.is_on_floor()
	while not caminho.is_empty() and caminho[0]["para"] == no:
		caminho.pop_front()
	if caminho.is_empty():
		return r
	var e: Dictionary = caminho[0]
	var de: Vector2i = e["de"]
	var para: Vector2i = e["para"]
	if no_chao and no != Navegacao.INVALIDO and no != de:
		# Saiu da rota (empurrão, queda...): pede um caminho novo
		caminho.clear()
		replanejar = true
		return r
	var x_para := Navegacao.centro(para).x
	var falta := x_para - corpo.position.x
	match e["tipo"]:
		Navegacao.Tipo.ANDAR, Navegacao.Tipo.CAIR:
			r["eixo"] = signf(falta)
		Navegacao.Tipo.DESCER:
			if no_chao:
				r["descer"] = true
		Navegacao.Tipo.PULAR:
			if no_chao and no == de:
				r["pular"] = true
			r["eixo"] = signf(falta) if absf(falta) > 3.0 else 0.0
		Navegacao.Tipo.PORTA:
			var porta: Dictionary = nav.portas[e["porta"]]
			if porta["tipo"] == "teto":
				var abertura: Rect2 = porta["abertura"]
				var dx := abertura.get_center().x - corpo.position.x
				r["eixo"] = signf(dx) if absf(dx) > 4.0 else 0.0
				if no_chao and absf(dx) < 10.0:
					r["pular"] = true
			else:
				var normal: Vector2 = porta["normal"]
				r["eixo"] = -normal.x

	# Preso em algum canto: tenta pular e pede caminho novo
	if r["eixo"] != 0.0 and corpo.position.distance_to(_ultima_pos) < 0.2:
		_preso_t += delta
	else:
		_preso_t = 0.0
	_ultima_pos = corpo.position
	if _preso_t > 0.5:
		_preso_t = 0.0
		if no_chao:
			r["pular"] = true
		replanejar = true
	return r
