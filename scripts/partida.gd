extends Node2D
## Uma partida 1x1: monta a arena procedural, cria os jogadores,
## teleporta quem entra nas portas, gera monstros e decide o vencedor.

signal revanche
signal voltar

const CENA_LUTADOR := preload("res://scenes/lutador.tscn")
const CENA_MINION := preload("res://scenes/minion.tscn")
const TEX_GOSMA := preload("res://assets/sprites/gosma.png")
const TEX_LACAIO := {
	1: preload("res://assets/sprites/lacaio_1.png"),
	2: preload("res://assets/sprites/lacaio_2.png"),
}
const TEX_CORTE := preload("res://assets/sprites/corte.png")
const TEX_BRILHO := preload("res://assets/sprites/brilho.png")

const TAM := GeradorArena.TAM
const ATLAS_PAREDE := Vector2i(0, 0)
const ATLAS_PLATAFORMA := Vector2i(1, 0)
const ATLAS_CHAO := Vector2i(2, 0)

const MAX_MONSTROS := 4
const INTERVALO_MONSTRO := 6.0

@onready var tiles: TileMapLayer = $Mundo/Tiles
@onready var desenho_portas: Node2D = $Mundo/Portas
@onready var entidades: Node2D = $Mundo/Entidades
@onready var hud: Control = $HUD/Painel

var mapa: Dictionary
var portas: Array = []
var jogadores := {}
var contagem := 3.0
var vencedor := 0
var fim := false

var _t_monstro := 0.0
var _t_fim := 0.0


func iniciar(classe1: ClasseDados, classe2: ClasseDados, semente: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	mapa = GeradorArena.gerar(rng)
	portas = mapa["portas"]
	_montar_tiles(mapa["grade"])
	desenho_portas.portas = portas
	hud.partida = self

	var classes := {1: classe1, 2: classe2}
	for n in [1, 2]:
		var l: Lutador = CENA_LUTADOR.instantiate()
		l.configurar(n, classes[n], self)
		l.position = mapa["inicio"][n]
		l.morreu.connect(_ao_morrer)
		entidades.add_child(l)
		jogadores[n] = l

	for i in 2:
		_criar_monstro()


func _montar_tiles(g: Array) -> void:
	tiles.clear()
	for y in GeradorArena.LINHAS:
		for x in GeradorArena.COLUNAS:
			match g[y][x]:
				GeradorArena.SOLIDO:
					var topo_livre: bool = y > 0 and g[y - 1][x] != GeradorArena.SOLIDO
					tiles.set_cell(Vector2i(x, y), 0, ATLAS_CHAO if topo_livre else ATLAS_PAREDE)
				GeradorArena.PLATAFORMA:
					tiles.set_cell(Vector2i(x, y), 0, ATLAS_PLATAFORMA)


func _process(delta: float) -> void:
	if contagem > -1.0:
		var antes := contagem
		contagem -= delta
		if antes > 0.0 and contagem <= 0.0:
			for l in jogadores.values():
				l.ativo = true

	if fim:
		_t_fim += delta
		if _t_fim > 1.0 and (Input.is_action_just_pressed("p1_pular") or Input.is_action_just_pressed("p2_pular")):
			revanche.emit()
	if Input.is_action_just_pressed("ui_cancel"):
		voltar.emit()


func _physics_process(delta: float) -> void:
	_atravessar_portas(delta)

	if not fim:
		_t_monstro += delta
		if _t_monstro >= INTERVALO_MONSTRO:
			_t_monstro = 0.0
			if _contar_equipe(0) < MAX_MONSTROS:
				_criar_monstro()


# ------------------------------------------------------------------ Portas

func _atravessar_portas(delta: float) -> void:
	for v in get_tree().get_nodes_in_group("viajante"):
		if v.cooldown_porta > 0.0:
			v.cooldown_porta -= delta
			continue
		var p: Vector2 = v.position
		for porta in portas:
			var gatilho: Rect2 = porta["gatilho"]
			var normal: Vector2 = porta["normal"]
			if gatilho.has_point(p) and v.velocity.dot(normal) <= 0.0:
				_teleportar(v, porta, portas[porta["par"]])
				break
		# Segurança: se algo escapar da arena, volta para o centro
		if p.x < -48 or p.x > GeradorArena.LARGURA + 48 or p.y < -64 or p.y > GeradorArena.ALTURA + 48:
			v.position = Vector2(GeradorArena.LARGURA / 2.0, 2 * TAM)
			v.velocity = Vector2.ZERO


func _teleportar(v, de: Dictionary, para: Dictionary) -> void:
	var vel: Vector2 = v.velocity
	var normal: Vector2 = para["normal"]
	if v is Projetil:
		v.velocity = normal * vel.length()
	elif para["tipo"] == "teto":
		v.velocity = Vector2(0.0, 40.0)
	else:
		var vy := -80.0 if de["tipo"] == "teto" else minf(vel.y, 0.0)
		v.velocity = Vector2(normal.x * maxf(absf(vel.x), 60.0), vy)
	criar_brilho(v.position)
	v.position = para["saida"]
	v.cooldown_porta = 0.2
	if v is Lutador:
		criar_brilho(v.position)
		Jogo.tocar("porta")


# ------------------------------------------------------------------ Criação de entidades

func criar_projetil(dono: Lutador, pos: Vector2, vel: Vector2, dano: float, alcance: float, magia: bool) -> void:
	var p := Projetil.new()
	p.partida = self
	p.dono = dono
	p.equipe = dono.equipe
	p.position = pos
	p.velocity = vel
	p.dano = dano
	p.alcance_max = alcance
	p.magia = magia
	p.dano_min = dono.dados.dano_minimo_magia
	p.raio_explosao = dono.raio_explosao
	entidades.add_child(p)


func criar_lacaio(rei: Lutador) -> void:
	var m: Minion = CENA_MINION.instantiate()
	m.configurar(self, rei.equipe, rei, TEX_LACAIO[rei.equipe],
			rei.dados.vida_lacaio * rei.mult_lacaio, rei.dano * rei.mult_lacaio,
			rei.dados.velocidade_lacaio, 2000.0, 2)
	m.position = rei.position
	entidades.add_child(m)
	criar_brilho(m.position)
	Jogo.tocar("invocar")


func contar_lacaios(rei: Lutador) -> int:
	var n := 0
	for a in get_tree().get_nodes_in_group("alvo"):
		if a is Minion and a.dono == rei:
			n += 1
	return n


func _contar_equipe(equipe: int) -> int:
	var n := 0
	for a in get_tree().get_nodes_in_group("alvo"):
		if a.equipe == equipe:
			n += 1
	return n


func _criar_monstro() -> void:
	var pontos: Array = mapa["pontos_monstro"]
	if pontos.is_empty():
		return
	var m: Minion = CENA_MINION.instantiate()
	m.configurar(self, 0, null, TEX_GOSMA, 30.0, 6.0, 30.0, 70.0, 4)
	m.position = pontos.pick_random()
	entidades.add_child(m)
	criar_brilho(m.position)


func criar_corte(pos: Vector2, espelhar: bool) -> void:
	var s := Sprite2D.new()
	s.texture = TEX_CORTE
	s.hframes = 2
	s.flip_h = espelhar
	s.position = pos
	entidades.add_child(s)
	var tw := s.create_tween()
	tw.tween_interval(0.06)
	tw.tween_callback(func() -> void: s.frame = 1)
	tw.tween_interval(0.08)
	tw.tween_callback(s.queue_free)


func criar_brilho(pos: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = TEX_BRILHO
	s.hframes = 3
	s.position = pos
	entidades.add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "frame", 2, 0.2)
	tw.tween_callback(s.queue_free)


func mostrar_texto(pos: Vector2, texto: String, cor: Color) -> void:
	var l := Label.new()
	l.text = texto
	var ls := LabelSettings.new()
	ls.font_size = 8
	ls.font_color = cor
	ls.outline_size = 3
	ls.outline_color = Color("1a1c2c")
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(80, 12)
	l.position = pos - Vector2(40, 6)
	l.z_index = 10
	entidades.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 12.0, 0.6)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.3)
	tw.tween_callback(l.queue_free)


# ------------------------------------------------------------------ Fim de partida

func _ao_morrer(l: Lutador) -> void:
	if fim:
		return
	fim = true
	vencedor = 2 if l.numero == 1 else 1
	for j in jogadores.values():
		j.ativo = false
	Engine.time_scale = 0.35
	await get_tree().create_timer(0.5, true, false, true).timeout
	Engine.time_scale = 1.0
	Jogo.tocar("vitoria")


func _exit_tree() -> void:
	Engine.time_scale = 1.0
