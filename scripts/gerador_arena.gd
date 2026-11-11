class_name GeradorArena
extends RefCounted
## Gera arenas proceduralmente.
##
## A arena é uma grade de 24x13 tiles com paredes em volta. Cada lateral
## recebe de 1 a 3 portas sorteadas. Se os lados ficarem desiguais
## (ex.: 3 x 2), abrem-se portas no teto até a conta fechar (3 x 3).
## Cada porta do lado com mais portas forma um par com uma do outro grupo:
## entrar em uma faz você sair pela outra (como os túneis do Pac-Man).

const COLUNAS := 24
const LINHAS := 13
const TAM := 16
const LARGURA := COLUNAS * TAM
const ALTURA := LINHAS * TAM

const VAZIO := 0
const SOLIDO := 1
const PLATAFORMA := 2

## Linhas da grade onde se pisa (chão = 12). Separadas por 3 tiles,
## que é o que todas as classes alcançam com um pulo.
const NIVEIS: Array[int] = [12, 9, 6, 3]

const CORES_PORTAS: Array[Color] = [
	Color("73eff7"), Color("ffcd75"), Color("a7f070"), Color("f4a2f4"),
]


static func gerar(rng: RandomNumberGenerator) -> Dictionary:
	var g: Array = []
	for y in LINHAS:
		var linha: Array[int] = []
		linha.resize(COLUNAS)
		linha.fill(VAZIO)
		g.append(linha)

	# Paredes externas
	for x in COLUNAS:
		g[0][x] = SOLIDO
		g[LINHAS - 1][x] = SOLIDO
	for y in LINHAS:
		g[y][0] = SOLIDO
		g[y][COLUNAS - 1] = SOLIDO

	# Plataformas espelhadas (justo para os dois lados)
	for nivel in [9, 6, 3]:
		_linha_de_plataformas(g, nivel, rng)

	# Blocos no chão
	for i in rng.randi_range(0, 2):
		_espelhar(g, LINHAS - 2, rng.randi_range(4, 9), SOLIDO)

	# Portas laterais
	var n_esq := rng.randi_range(1, 3)
	var n_dir := rng.randi_range(1, 3)
	var esq: Array = []
	for nivel in _sortear(NIVEIS, n_esq, rng):
		esq.append(_porta_lateral(g, nivel, true))
	var dir: Array = []
	for nivel in _sortear(NIVEIS, n_dir, rng):
		dir.append(_porta_lateral(g, nivel, false))

	# Portas no teto para fechar a conta
	var tetos: Array = []
	var cols_usadas: Array[int] = []
	for i in absi(n_esq - n_dir):
		var c := _coluna_teto(rng, cols_usadas)
		cols_usadas.append(c)
		tetos.append(_porta_teto(g, c))

	var grupo_a: Array = esq if n_esq >= n_dir else dir
	var grupo_b: Array = (dir if n_esq >= n_dir else esq) + tetos
	_embaralhar(grupo_b, rng)

	var portas: Array = grupo_a + grupo_b
	for i in grupo_a.size():
		var a: Dictionary = grupo_a[i]
		var b: Dictionary = grupo_b[i]
		a["par"] = portas.find(b)
		b["par"] = portas.find(a)
		a["cor"] = CORES_PORTAS[i % CORES_PORTAS.size()]
		b["cor"] = a["cor"]

	return {
		"grade": g,
		"portas": portas,
		"inicio": {
			1: Vector2(2.5 * TAM, (LINHAS - 1) * TAM - 8),
			2: Vector2((COLUNAS - 2.5) * TAM, (LINHAS - 1) * TAM - 8),
		},
		"pontos_monstro": _pontos_de_spawn(g),
	}


static func _espelhar(g: Array, y: int, x: int, valor: int) -> void:
	g[y][x] = valor
	g[y][COLUNAS - 1 - x] = valor


static func _linha_de_plataformas(g: Array, linha: int, rng: RandomNumberGenerator) -> void:
	var x := rng.randi_range(1, 3)
	while x <= COLUNAS / 2 - 1:
		var comp := rng.randi_range(2, 5)
		for i in comp:
			if x + i <= COLUNAS / 2 - 1:
				_espelhar(g, linha, x + i, PLATAFORMA)
		x += comp + rng.randi_range(2, 4)


static func _porta_lateral(g: Array, nivel: int, esquerda: bool) -> Dictionary:
	var col := 0 if esquerda else COLUNAS - 1
	var dentro := 1 if esquerda else COLUNAS - 2
	var dentro2 := 2 if esquerda else COLUNAS - 3
	# Abre um vão de 2 tiles de altura logo acima do nível
	g[nivel - 1][col] = VAZIO
	g[nivel - 2][col] = VAZIO
	g[nivel - 1][dentro] = VAZIO
	g[nivel - 2][dentro] = VAZIO
	# Garante um apoio para pisar na saída
	if nivel < LINHAS - 1:
		for c in [dentro, dentro2]:
			if g[nivel][c] == VAZIO:
				g[nivel][c] = PLATAFORMA
	var topo := (nivel - 2) * TAM
	return {
		"tipo": "esq" if esquerda else "dir",
		"abertura": Rect2(col * TAM, topo, TAM, 2 * TAM),
		"gatilho": Rect2(-64, topo, 70, 2 * TAM) if esquerda else Rect2(LARGURA - 6, topo, 70, 2 * TAM),
		"saida": Vector2((dentro + 0.5) * TAM, nivel * TAM - 8),
		"normal": Vector2.RIGHT if esquerda else Vector2.LEFT,
	}


static func _porta_teto(g: Array, c: int) -> Dictionary:
	g[0][c] = VAZIO
	g[0][c + 1] = VAZIO
	# Plataforma embaixo para dar para alcançar o teto
	for x in range(c - 1, c + 3):
		if x >= 1 and x <= COLUNAS - 2 and g[3][x] == VAZIO:
			g[3][x] = PLATAFORMA
	return {
		"tipo": "teto",
		"abertura": Rect2(c * TAM, 0, 2 * TAM, TAM),
		"gatilho": Rect2(c * TAM, -64, 2 * TAM, 70),
		"saida": Vector2(c * TAM + TAM, TAM + 8),
		"normal": Vector2.DOWN,
	}


static func _coluna_teto(rng: RandomNumberGenerator, usadas: Array[int]) -> int:
	# Só no centro do teto, para não ficar atrás do HUD dos jogadores
	for tentativa in 50:
		var c := rng.randi_range(8, 14)
		var ok := true
		for u in usadas:
			if absi(u - c) < 4:
				ok = false
		if ok:
			return c
	return 8 if usadas.is_empty() else (14 if usadas[0] < 11 else 8)


static func _pontos_de_spawn(g: Array) -> Array:
	## Posições (no centro da arena) com chão embaixo e espaço em cima.
	var pontos: Array = []
	for y in range(2, LINHAS - 1):
		for x in range(5, COLUNAS - 5):
			if g[y][x] == VAZIO and g[y - 1][x] == VAZIO and g[y + 1][x] != VAZIO:
				pontos.append(Vector2((x + 0.5) * TAM, (y + 1) * TAM - 8))
	return pontos


static func _sortear(lista: Array, n: int, rng: RandomNumberGenerator) -> Array:
	var copia := lista.duplicate()
	_embaralhar(copia, rng)
	return copia.slice(0, n)


static func _embaralhar(lista: Array, rng: RandomNumberGenerator) -> void:
	for i in range(lista.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = lista[i]
		lista[i] = lista[j]
		lista[j] = tmp
