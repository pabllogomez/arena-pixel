extends Node2D
## Ambientação da masmorra: escuridão, tochas tremulando, luz em volta dos
## personagens e pingos d'água caindo do teto. A iluminação pode ser
## desligada no ícone de tocha (ou tecla I); a escolha fica salva.

const TEX_TOCHA := preload("res://assets/sprites/tocha.png")
const TEX_PINGO := preload("res://assets/sprites/pingo.png")
const TAM := GeradorArena.TAM

var _escuridao: CanvasModulate
var _textura_luz: Texture2D
var _tochas: Array = []        # [Sprite2D, PointLight2D, fase]
var _fontes_pingo: Array = []  # [posição de origem, y do chão, tempo até o próximo]
var _t := 0.0


static func material_sem_sombra() -> CanvasItemMaterial:
	## Para coisas que devem brilhar mesmo no escuro (textos, efeitos, projéteis).
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m


func configurar(g: Array, rng: RandomNumberGenerator, escuridao: CanvasModulate) -> void:
	_escuridao = escuridao
	_textura_luz = _criar_textura_luz()
	_criar_tochas(g, rng)
	_criar_fontes_pingo(g, rng)
	Jogo.opcoes_mudaram.connect(aplicar_opcoes)
	aplicar_opcoes()


func _criar_textura_luz() -> Texture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.5, Color(1, 1, 1, 0.45))
	var t := GradientTexture2D.new()
	t.gradient = grad
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


func criar_luz(cor: Color, raio: float, energia: float) -> PointLight2D:
	var luz := PointLight2D.new()
	luz.texture = _textura_luz
	luz.color = cor
	luz.energy = energia
	luz.texture_scale = raio / 64.0
	luz.add_to_group("luz")
	luz.enabled = Jogo.iluminacao
	return luz


func aplicar_opcoes() -> void:
	if not is_inside_tree():
		return
	_escuridao.visible = Jogo.iluminacao
	for luz in get_tree().get_nodes_in_group("luz"):
		luz.enabled = Jogo.iluminacao


# ------------------------------------------------------------------ Tochas

func _criar_tochas(g: Array, rng: RandomNumberGenerator) -> void:
	var candidatos: Array[Vector2i] = []
	for y in range(2, GeradorArena.LINHAS - 3):
		for x in range(2, GeradorArena.COLUNAS - 2):
			# Parede livre: a célula e a de baixo vazias (não fica em cima de plataforma)
			if g[y][x] == GeradorArena.VAZIO and g[y + 1][x] == GeradorArena.VAZIO and g[y - 1][x] == GeradorArena.VAZIO:
				candidatos.append(Vector2i(x, y))
	GeradorArena._embaralhar(candidatos, rng)
	var escolhidas: Array[Vector2i] = []
	for c in candidatos:
		var longe := true
		for e in escolhidas:
			if absi(e.x - c.x) < 6 and absi(e.y - c.y) < 4:
				longe = false
		if longe:
			escolhidas.append(c)
		if escolhidas.size() >= 7:
			break
	for c in escolhidas:
		var pos := Vector2((c.x + 0.5) * TAM, (c.y + 0.5) * TAM)
		var s := Sprite2D.new()
		s.texture = TEX_TOCHA
		s.hframes = 4
		s.position = pos
		s.material = material_sem_sombra()
		add_child(s)
		var luz := criar_luz(Color(1.0, 0.62, 0.32), 72.0, 1.1)
		luz.position = pos + Vector2(0, -5)
		add_child(luz)
		_tochas.append([s, luz, rng.randf() * TAU])


# ------------------------------------------------------------------ Pingos

func _criar_fontes_pingo(g: Array, rng: RandomNumberGenerator) -> void:
	## Pingos caem de baixo de blocos de pedra (teto ou blocos flutuantes).
	var candidatos: Array = []
	for y in range(0, GeradorArena.LINHAS - 2):
		for x in range(1, GeradorArena.COLUNAS - 1):
			if g[y][x] == GeradorArena.SOLIDO and g[y + 1][x] == GeradorArena.VAZIO:
				var chao := y + 1
				while chao < GeradorArena.LINHAS and g[chao][x] == GeradorArena.VAZIO:
					chao += 1
				if chao - y >= 3:
					candidatos.append([Vector2((x + rng.randf_range(0.2, 0.8)) * TAM, (y + 1) * TAM), chao * TAM])
	GeradorArena._embaralhar(candidatos, rng)
	for i in mini(8, candidatos.size()):
		var c: Array = candidatos[i]
		_fontes_pingo.append([c[0], float(c[1]), rng.randf_range(0.5, 4.0)])


func _pingar(origem: Vector2, chao: float) -> void:
	var s := Sprite2D.new()
	s.texture = TEX_PINGO
	s.hframes = 4
	s.position = origem
	s.material = material_sem_sombra()
	s.modulate.a = 0.85
	add_child(s)
	var queda := chao - origem.y
	var tempo := sqrt(2.0 * queda / 500.0)  # gravidade dos pingos: 500 px/s²
	var tw := s.create_tween()
	tw.tween_property(s, "position:y", chao - 4.0, tempo).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if randf() < 0.25:
			Jogo.tocar("pingo"))
	tw.tween_property(s, "frame", 3, 0.24).from(1)
	tw.tween_callback(s.queue_free)


func _process(delta: float) -> void:
	_t += delta
	for t in _tochas:
		var s: Sprite2D = t[0]
		var luz: PointLight2D = t[1]
		var fase: float = t[2]
		s.frame = int(_t * 8.0 + fase) % 4
		# Chama tremendo: a luz pulsa de forma irregular
		luz.energy = 1.0 + 0.15 * sin(_t * 9.0 + fase) + 0.08 * sin(_t * 23.0 + fase * 2.0)
	for f in _fontes_pingo:
		f[2] -= delta
		if f[2] <= 0.0:
			f[2] = randf_range(1.2, 4.5)
			_pingar(f[0], f[1])
