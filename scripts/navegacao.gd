class_name Navegacao
extends RefCounted
## Grafo de navegação da arena.
##
## Um "nó" é uma célula vazia com chão (ou plataforma) logo embaixo, ou seja,
## um lugar onde dá para ficar em pé. As arestas dizem como ir de um nó a
## outro: andando, pulando, caindo de uma beirada, descendo de uma plataforma
## ou entrando em uma porta.
##
## Usado pelo gerador (para garantir que todo lugar é alcançável), pelo bot
## e pelos lacaios do Rei (para achar caminhos).

enum Tipo { ANDAR, PULAR, CAIR, DESCER, PORTA }

const SUBIDA_MAX := 3          # tiles que dá para subir com um pulo
const PULO_HORIZ_MAX := 4      # tiles de distância horizontal em um pulo
const INVALIDO := Vector2i(-1, -1)

var g: Array
var portas: Array
var portas_abertas := true
## nó (Vector2i) -> Array de arestas {"de", "para", "tipo", "porta"}
var nos := {}


func _init(grade: Array, lista_portas: Array) -> void:
	g = grade
	portas = lista_portas
	for y in range(1, GeradorArena.LINHAS - 1):
		for x in range(1, GeradorArena.COLUNAS - 1):
			if _e_no(x, y):
				nos[Vector2i(x, y)] = []
	for no in nos:
		_ligar(no)
	for i in portas.size():
		var p: Dictionary = portas[i]
		var par: Dictionary = portas[p["par"]]
		var de: Vector2i = p.get("no_entrada", INVALIDO)
		var para: Vector2i = par.get("no_saida", INVALIDO)
		if nos.has(de) and nos.has(para):
			nos[de].append({"de": de, "para": para, "tipo": Tipo.PORTA, "porta": i})


# ------------------------------------------------------------------ Construção

func _cel(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= GeradorArena.COLUNAS or y >= GeradorArena.LINHAS:
		return GeradorArena.SOLIDO
	return g[y][x]


func _e_no(x: int, y: int) -> bool:
	return _cel(x, y) == GeradorArena.VAZIO and _cel(x, y + 1) != GeradorArena.VAZIO


func _aresta(de: Vector2i, para: Vector2i, tipo: Tipo) -> void:
	if not nos.has(para):
		return  # ex.: cair dentro do vão de uma porta lateral
	nos[de].append({"de": de, "para": para, "tipo": tipo, "porta": -1})


func _ligar(no: Vector2i) -> void:
	var x := no.x
	var y := no.y
	for d in [-1, 1]:
		var lado := Vector2i(x + d, y)
		if nos.has(lado):
			_aresta(no, lado, Tipo.ANDAR)
		elif _cel(x + d, y) == GeradorArena.VAZIO:
			var pouso := _queda(x + d, y)
			if pouso != INVALIDO:
				_aresta(no, pouso, Tipo.CAIR)
	if _cel(x, y + 1) == GeradorArena.PLATAFORMA:
		var pouso := _queda(x, y + 1)
		if pouso != INVALIDO:
			_aresta(no, pouso, Tipo.DESCER)
	# Pulos
	for dy in range(-6, SUBIDA_MAX + 1):
		for dx in range(-PULO_HORIZ_MAX, PULO_HORIZ_MAX + 1):
			var alvo := Vector2i(x + dx, y - dy)
			if alvo == no or not nos.has(alvo):
				continue
			if dy == 0 and absi(dx) <= 1:
				continue  # vizinho: basta andar
			if dy > 0 and absi(dx) > SUBIDA_MAX:
				continue
			if _arco_livre(no, alvo):
				_aresta(no, alvo, Tipo.PULAR)


func _queda(x: int, y: int) -> Vector2i:
	## Onde para quem começa a cair na célula (x, y).
	for yy in range(y, GeradorArena.LINHAS - 1):
		if yy != y and _cel(x, yy) == GeradorArena.SOLIDO:
			return INVALIDO
		if _cel(x, yy) == GeradorArena.VAZIO and _cel(x, yy + 1) != GeradorArena.VAZIO:
			return Vector2i(x, yy)
	return INVALIDO


func _arco_livre(a: Vector2i, b: Vector2i) -> bool:
	## Aproximação da trajetória: sobe na coluna de origem até o topo do arco,
	## anda na horizontal e desce na coluna de destino. Plataformas não bloqueiam
	## (dá para atravessá-las por baixo); só blocos sólidos.
	var topo := mini(a.y, b.y) - 1
	if topo < 1:
		return false
	for r in range(topo, a.y):
		if _cel(a.x, r) == GeradorArena.SOLIDO:
			return false
	var passo := 1 if b.x >= a.x else -1
	for c in range(a.x, b.x + passo, passo):
		if _cel(c, topo) == GeradorArena.SOLIDO:
			return false
	for r in range(topo, b.y + 1):
		if _cel(b.x, r) == GeradorArena.SOLIDO:
			return false
	return true


# ------------------------------------------------------------------ Consultas

static func centro(no: Vector2i) -> Vector2:
	## Posição (em pixels da arena) de um personagem em pé neste nó.
	return Vector2((no.x + 0.5) * GeradorArena.TAM, (no.y + 0.5) * GeradorArena.TAM)


func no_de_posicao(pos: Vector2) -> Vector2i:
	var c := Vector2i(floori(pos.x / GeradorArena.TAM), floori(pos.y / GeradorArena.TAM))
	if nos.has(c):
		return c
	return INVALIDO


func no_mais_proximo(pos: Vector2) -> Vector2i:
	var exato := no_de_posicao(pos)
	if exato != INVALIDO:
		return exato
	var melhor := INVALIDO
	var melhor_d := INF
	for no in nos:
		var d := centro(no).distance_squared_to(pos)
		if d < melhor_d:
			melhor_d = d
			melhor = no
	return melhor


func _arestas(no: Vector2i, usar_portas: bool) -> Array:
	var r: Array = []
	for e in nos.get(no, []):
		if e["tipo"] == Tipo.PORTA and not (usar_portas and portas_abertas):
			continue
		r.append(e)
	return r


func distancias(origem: Vector2i, usar_portas := true) -> Dictionary:
	## Número de passos até cada nó alcançável.
	var dist := {origem: 0}
	var fila: Array[Vector2i] = [origem]
	var i := 0
	while i < fila.size():
		var no: Vector2i = fila[i]
		i += 1
		for e in _arestas(no, usar_portas):
			var p: Vector2i = e["para"]
			if not dist.has(p):
				dist[p] = dist[no] + 1
				fila.append(p)
	return dist


func alcanca_de_volta(destino: Vector2i, usar_portas := true) -> Dictionary:
	## Nós que conseguem chegar até o destino (busca no grafo invertido).
	var reverso := {}
	for no in nos:
		for e in _arestas(no, usar_portas):
			var p: Vector2i = e["para"]
			if not reverso.has(p):
				reverso[p] = []
			reverso[p].append(no)
	var vistos := {destino: true}
	var fila: Array[Vector2i] = [destino]
	var i := 0
	while i < fila.size():
		var no: Vector2i = fila[i]
		i += 1
		for anterior in reverso.get(no, []):
			if not vistos.has(anterior):
				vistos[anterior] = true
				fila.append(anterior)
	return vistos


func caminho(origem: Vector2i, destino: Vector2i, usar_portas := true) -> Array:
	## Lista de arestas da origem ao destino (vazia se não houver caminho).
	if not nos.has(origem) or not nos.has(destino) or origem == destino:
		return []
	var veio := {origem: null}
	var fila: Array[Vector2i] = [origem]
	var i := 0
	while i < fila.size():
		var no: Vector2i = fila[i]
		i += 1
		if no == destino:
			break
		for e in _arestas(no, usar_portas):
			var p: Vector2i = e["para"]
			if not veio.has(p):
				veio[p] = e
				fila.append(p)
	if not veio.has(destino):
		return []
	var r: Array = []
	var atual := destino
	while veio[atual] != null:
		var e: Dictionary = veio[atual]
		r.push_front(e)
		atual = e["de"]
	return r
