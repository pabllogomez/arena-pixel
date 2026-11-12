class_name GeradorArena
extends RefCounted
## Gera arenas proceduralmente, montando "peças" sorteadas em lugares
## diferentes a cada partida (sem espelhamento):
##   escadaria, torre, ponte, ilha, paredão e mezanino.
##
## Portas: cada lateral recebe de 1 a 3 portas, com no mínimo 2 pares no total.
## Se os lados ficarem desiguais (ex.: 3 x 2), abrem-se portas no teto até a
## conta fechar (3 x 3). Entrar em uma porta leva até a porta par dela.
##
## Depois de montar, o mapa é verificado com a Navegacao: tudo tem que ser
## alcançável e ter caminho de volta. Plataformas inalcançáveis são removidas;
## se o mapa não passar, outro é gerado.

const COLUNAS := 30
const LINHAS := 16
const TAM := 16
const LARGURA := COLUNAS * TAM
const ALTURA := LINHAS * TAM

const VAZIO := 0
const SOLIDO := 1
const PLATAFORMA := 2

const PECAS: Array[String] = [
	"escadaria", "torre", "ponte", "ilha", "ilha", "paredao", "mezanino",
]
const MIN_PARES_PORTAS := 2

const CORES_PORTAS: Array[Color] = [
	Color("73eff7"), Color("ffcd75"), Color("a7f070"), Color("f4a2f4"),
]

const NO_INICIO := {1: Vector2i(2, LINHAS - 2), 2: Vector2i(COLUNAS - 3, LINHAS - 2)}


static func gerar(rng: RandomNumberGenerator) -> Dictionary:
	for tentativa in 300:
		var m := _tentar(rng)
		if not m.is_empty():
			m["tentativas"] = tentativa + 1
			return m
	push_error("GeradorArena: nenhum mapa válido após 300 tentativas")
	return {}


# ------------------------------------------------------------------ Montagem

static func _tentar(rng: RandomNumberGenerator) -> Dictionary:
	var g: Array = []
	var ocupado: Array = []
	for y in LINHAS:
		var linha: Array[int] = []
		linha.resize(COLUNAS)
		linha.fill(VAZIO)
		g.append(linha)
		var oc: Array[bool] = []
		oc.resize(COLUNAS)
		oc.fill(false)
		ocupado.append(oc)
	for x in COLUNAS:
		g[0][x] = SOLIDO
		g[LINHAS - 1][x] = SOLIDO
	for y in LINHAS:
		g[y][0] = SOLIDO
		g[y][COLUNAS - 1] = SOLIDO

	# Área livre perto de onde os jogadores nascem
	for y in range(LINHAS - 5, LINHAS - 1):
		for x in [1, 2, 3, COLUNAS - 4, COLUNAS - 3, COLUNAS - 2]:
			ocupado[y][x] = true

	var alvo_pecas := rng.randi_range(9, 12)
	var colocadas := 0
	for i in 90:
		if colocadas >= alvo_pecas:
			break
		var tipo: String = PECAS[rng.randi() % PECAS.size()]
		var celulas := _peca(tipo, rng)
		if _cabe(celulas, ocupado):
			for c in celulas:
				var p: Vector2i = c[0]
				g[p.y][p.x] = c[1]
				ocupado[p.y][p.x] = true
			colocadas += 1

	var portas := _criar_portas(g, ocupado, rng)
	if portas.is_empty():
		return {}

	# Verificação: tudo alcançável a partir dos dois inícios, e com volta.
	var nav: Navegacao
	for rodada in 8:
		nav = Navegacao.new(g, portas)
		if not nav.nos.has(NO_INICIO[1]) or not nav.nos.has(NO_INICIO[2]):
			return {}
		var ida := nav.distancias(NO_INICIO[1])
		var volta := nav.alcanca_de_volta(NO_INICIO[1])
		var podou := false
		for no in nav.nos:
			if ida.has(no) and volta.has(no):
				continue
			var baixo: Vector2i = no + Vector2i.DOWN
			if g[baixo.y][baixo.x] == PLATAFORMA:
				g[baixo.y][baixo.x] = VAZIO
				podou = true
			else:
				return {}  # topo de bloco sólido inalcançável: descarta o mapa
		if not podou:
			break
		if rodada == 7:
			return {}

	# As portas precisam continuar funcionando depois da poda
	for p in portas:
		if not nav.nos.has(p["no_entrada"]) or not nav.nos.has(p["no_saida"]):
			return {}
	if not nav.distancias(NO_INICIO[2]).has(NO_INICIO[1]):
		return {}

	# Qualidade: o mapa precisa ter vida no alto
	var altos := 0
	for no in nav.nos:
		if no.y <= 8:
			altos += 1
	if altos < 18:
		return {}

	var pontos: Array = []
	for no in nav.nos:
		if no.x >= 4 and no.x <= COLUNAS - 5:
			pontos.append(Navegacao.centro(no))

	return {
		"grade": g,
		"portas": portas,
		"nav": nav,
		"inicio": {1: Navegacao.centro(NO_INICIO[1]), 2: Navegacao.centro(NO_INICIO[2])},
		"pontos_monstro": pontos,
	}


static func _cabe(celulas: Array, ocupado: Array) -> bool:
	if celulas.is_empty():
		return false
	var proprias := {}
	for c in celulas:
		proprias[c[0]] = true
	for c in celulas:
		var p: Vector2i = c[0]
		if p.x < 2 or p.x > COLUNAS - 3 or p.y < 3 or p.y > LINHAS - 2:
			return false
		# Margem: 1 tile para os lados e 2 para cima/baixo entre peças
		for dy in range(-2, 3):
			for dx in range(-1, 2):
				var q := p + Vector2i(dx, dy)
				if q.x < 0 or q.y < 0 or q.x >= COLUNAS or q.y >= LINHAS:
					continue
				if ocupado[q.y][q.x] and not proprias.has(q):
					return false
	return true


static func _peca(tipo: String, rng: RandomNumberGenerator) -> Array:
	var c: Array = []
	match tipo:
		"escadaria":
			# Degraus de 2 tiles subindo em diagonal
			var dir := 1 if rng.randf() < 0.5 else -1
			var n := rng.randi_range(3, 4)
			var x0 := rng.randi_range(4, COLUNAS / 2) if dir == 1 else rng.randi_range(COLUNAS / 2, COLUNAS - 5)
			var y0 := rng.randi_range(LINHAS - 4, LINHAS - 3)
			for i in n:
				for k in 2:
					c.append([Vector2i(x0 + dir * (i * 3 + k), y0 - i * 2), PLATAFORMA])
		"torre":
			# Coluna de pedra com plataformas para escalar
			var x := rng.randi_range(5, COLUNAS - 6)
			var h := rng.randi_range(3, 5)
			var topo := LINHAS - 1 - h
			for y in range(topo, LINHAS - 1):
				c.append([Vector2i(x, y), SOLIDO])
			var lado := 1 if rng.randf() < 0.5 else -1
			if h >= 4:
				var y_apoio := LINHAS - 3 if h == 4 else LINHAS - 4
				for k in [1, 2]:
					c.append([Vector2i(x + lado * k, y_apoio), PLATAFORMA])
			if rng.randf() < 0.6:
				for k in [1, 2, 3]:
					c.append([Vector2i(x - lado * k, topo - 3), PLATAFORMA])
		"ponte":
			var comp := rng.randi_range(5, 9)
			var y := rng.randi_range(4, LINHAS - 5)
			var x0 := rng.randi_range(3, COLUNAS - 3 - comp)
			for i in comp:
				c.append([Vector2i(x0 + i, y), PLATAFORMA])
		"ilha":
			var larg := rng.randi_range(1, 3)
			var y := rng.randi_range(3, LINHAS - 4)
			var x0 := rng.randi_range(3, COLUNAS - 3 - larg)
			var valor := SOLIDO if rng.randf() < 0.4 else PLATAFORMA
			for i in larg:
				c.append([Vector2i(x0 + i, y), valor])
		"paredao":
			var larg := rng.randi_range(1, 2)
			var h := rng.randi_range(1, 2)
			var x0 := rng.randi_range(5, COLUNAS - 6 - larg)
			for i in larg:
				for k in h:
					c.append([Vector2i(x0 + i, LINHAS - 2 - k), SOLIDO])
		"mezanino":
			# Andar largo com buracos
			var comp := rng.randi_range(8, 14)
			var y := rng.randi_range(5, LINHAS - 6)
			var x0 := rng.randi_range(3, COLUNAS - 3 - comp)
			var buracos := {}
			for b in rng.randi_range(1, 2):
				var bx := rng.randi_range(2, comp - 4)
				buracos[bx] = true
				buracos[bx + 1] = true
			for i in comp:
				if not buracos.has(i):
					c.append([Vector2i(x0 + i, y), PLATAFORMA])
	return c


# ------------------------------------------------------------------ Portas

static func _criar_portas(g: Array, ocupado: Array, rng: RandomNumberGenerator) -> Array:
	var n_esq := 0
	var n_dir := 0
	while maxi(n_esq, n_dir) < MIN_PARES_PORTAS:
		n_esq = rng.randi_range(1, 3)
		n_dir = rng.randi_range(1, 3)

	var esq := _portas_laterais(g, ocupado, true, n_esq, rng)
	var dir := _portas_laterais(g, ocupado, false, n_dir, rng)
	if esq.size() != n_esq or dir.size() != n_dir:
		return []

	var tetos: Array = []
	var usadas: Array[int] = []
	for i in absi(n_esq - n_dir):
		var p := _porta_teto(g, rng, usadas)
		if p.is_empty():
			return []
		tetos.append(p)

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
	return portas


static func _portas_laterais(g: Array, ocupado: Array, esquerda: bool, n: int,
		rng: RandomNumberGenerator) -> Array:
	var col := 0 if esquerda else COLUNAS - 1
	var dentro := 1 if esquerda else COLUNAS - 2
	var dentro2 := 2 if esquerda else COLUNAS - 3
	# Níveis possíveis: precisa de vão livre de 2 tiles e espaço para o apoio
	var candidatos: Array[int] = []
	# (os 2 níveis logo acima do chão ficariam em cima de onde os jogadores nascem)
	var niveis: Array = range(3, LINHAS - 3)
	niveis.append(LINHAS - 1)
	for nivel in niveis:
		var ok := true
		for y in [nivel - 1, nivel - 2]:
			if g[y][dentro] != VAZIO or g[y][dentro2] != VAZIO:
				ok = false
		if nivel < LINHAS - 1:
			for x in [dentro, dentro2]:
				if g[nivel][x] == SOLIDO:
					ok = false
			if g[nivel + 1][dentro] != VAZIO and nivel + 1 < LINHAS - 1:
				ok = false
		if ok:
			candidatos.append(nivel)
	_embaralhar(candidatos, rng)
	var escolhidos: Array[int] = []
	for nivel in candidatos:
		var longe := true
		for e in escolhidos:
			if absi(e - nivel) < 3:
				longe = false
		if longe:
			escolhidos.append(nivel)
		if escolhidos.size() == n:
			break

	var r: Array = []
	for nivel in escolhidos:
		g[nivel - 1][col] = VAZIO
		g[nivel - 2][col] = VAZIO
		if nivel < LINHAS - 1:
			for x in [dentro, dentro2]:
				g[nivel][x] = PLATAFORMA
				ocupado[nivel][x] = true
		var topo := (nivel - 2) * TAM
		var no := Vector2i(dentro, nivel - 1)
		r.append({
			"tipo": "esq" if esquerda else "dir",
			"abertura": Rect2(col * TAM, topo, TAM, 2 * TAM),
			"gatilho": Rect2(-64, topo, 70, 2 * TAM) if esquerda else Rect2(LARGURA - 6, topo, 70, 2 * TAM),
			"saida": Navegacao.centro(no),
			"no_entrada": no,
			"no_saida": no,
			"normal": Vector2.RIGHT if esquerda else Vector2.LEFT,
			"celulas": [Vector2i(col, nivel - 1), Vector2i(col, nivel - 2)],
		})
	return r


static func _porta_teto(g: Array, rng: RandomNumberGenerator, usadas: Array[int]) -> Dictionary:
	# Entre os painéis dos jogadores e o cronômetro, para não ficar atrás do HUD
	var cols: Array[int] = []
	for c in [8, 9, COLUNAS - 11, COLUNAS - 10]:
		cols.append(c)
	_embaralhar(cols, rng)
	for c in cols:
		var longe := true
		for u in usadas:
			if absi(u - c) < 4:
				longe = false
		if not longe:
			continue
		var livre := true
		for y in range(1, 4):
			for x in range(c - 1, c + 3):
				if g[y][x] != VAZIO:
					livre = false
		for x in range(c - 1, c + 3):
			if g[4][x] == SOLIDO:
				livre = false
		if not livre:
			continue
		usadas.append(c)
		g[0][c] = VAZIO
		g[0][c + 1] = VAZIO
		for x in range(c - 1, c + 3):
			g[4][x] = PLATAFORMA
		var no := Vector2i(c, 3)
		return {
			"tipo": "teto",
			"abertura": Rect2(c * TAM, 0, 2 * TAM, TAM),
			"gatilho": Rect2(c * TAM, -64, 2 * TAM, 70),
			"saida": Vector2(c * TAM + TAM, TAM + 8),
			"no_entrada": no,
			"no_saida": no,
			"normal": Vector2.DOWN,
			"celulas": [Vector2i(c, 0), Vector2i(c + 1, 0)],
		}
	return {}


static func _embaralhar(lista: Array, rng: RandomNumberGenerator) -> void:
	for i in range(lista.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = lista[i]
		lista[i] = lista[j]
		lista[j] = tmp
