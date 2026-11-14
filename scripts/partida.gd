extends Node2D
## Uma partida 1x1: monta a arena procedural, cria os jogadores (humanos ou
## bots), teleporta quem entra nas portas, gera monstros que evoluem com o
## nível dos jogadores, controla o cronômetro e a Morte Súbita e decide o
## vencedor.

signal revanche
signal voltar
## Torre da Tormenta: a luta acabou e o resultado já apareceu (vencedor 0 = empate)
signal fim_de_luta(vencedor: int)

const CENA_LUTADOR := preload("res://scenes/lutador.tscn")
const CENA_MINION := preload("res://scenes/minion.tscn")
const TEX_GOSMA: Array[Texture2D] = [
	preload("res://assets/sprites/gosma_1.png"),
	preload("res://assets/sprites/gosma_2.png"),
	preload("res://assets/sprites/gosma_3.png"),
	preload("res://assets/sprites/gosma_4.png"),
]
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

## Vida dos monstros de nível 1 (cresce 35% por nível)
const VIDA_MONSTRO := 36.0
## Dano dos monstros de nível 1 (cresce 20% por nível)
const DANO_MONSTRO := 3.0
## XP dos monstros de nível 1 (dos níveis seguintes: 4 + 2 por nível)
const XP_MONSTRO_NIVEL_1 := 2
## Enquanto houver Recruta, nascem mais monstros, mais rápido
const INTERVALO_MONSTRO_RECRUTA := 3.0
const MAX_MONSTROS_RECRUTA := 5
## Dano entre jogadores (fração do dano normal)
const PVP_BASE := 0.4
## Aumento geral do dano PvP (vale para tudo, inclusive Recruta e Morte Súbita)
const PVP_GERAL := 1.35
## Recruta atacando jogador
const PVP_RECRUTA_ATACA := 0.6
## Jogador com classe atacando Recruta
const PVP_CONTRA_RECRUTA := 1.0 / 3.0

# Morte Súbita
const NEVOA_VELOCIDADE := 3.0      # pixels por segundo
const NEVOA_DANO := 4.0            # a cada NEVOA_INTERVALO
const NEVOA_INTERVALO := 0.5
const MORTE_SUBITA_DEGRAU := 15.0  # segundos entre aumentos de dano PvP
const MORTE_SUBITA_AUMENTO := 0.3

@onready var tiles: TileMapLayer = $Mundo/Tiles
@onready var desenho_portas: Node2D = $Mundo/Portas
@onready var nevoa_visual: Node2D = $Mundo/Nevoa
@onready var entidades: Node2D = $Mundo/Entidades
@onready var masmorra: Node2D = $Mundo/Masmorra
@onready var hud: Control = $HUD/Painel

## Partículas da partida (faíscas, poeira, estilhaços...). Só enfeite.
var particulas: Particulas
var _quadros_impacto := 0
var _camera_lenta := false
var _t_confete := 0.0
## Tutorial de toque aberto (segura a contagem inicial nas partidas locais)
var tutorial_aberto := false

var mapa: Dictionary
var nav: Navegacao
var portas: Array = []
var portas_abertas := true
var jogadores := {}
var contagem := 3.0
var tempo_restante := 180.0
var morte_subita := false
var tempo_morte_subita := 0.0
var nivel_nevoa := float(GeradorArena.ALTURA)
var vencedor := 0   ## 0 = empate
var fim := false
var anuncio := ""
var anuncio_cor := Color.WHITE
var anuncio_t := 0.0

var _t_monstro := 0.0
# Itens
const INTERVALO_ITEM := 20.0
const MAX_ITENS := 2
## A Bola da troca aparece uma vez, depois deste tempo de partida, no topo
## central da arena, e fica lá até alguém pegar ou começar a Morte Súbita.
const MOMENTO_BOLA := 120.0
var _t_item := 0.0
var itens_ligados := true  ## (só os testes de equilíbrio e a Torre desligam)
## Regras que a Torre da Tormenta desliga (o padrão é o comportamento normal)
var monstros_ligados := true
var morte_subita_ligada := true  ## false: no fim do tempo vence quem tem mais % de vida
var regen := true                ## regeneração lenta fora de combate
var xp_ligado := true            ## false: o nível só muda por fora (vitória na Torre)
## Torre da Tormenta (vazio nas outras partidas): {"andar", "final", "adversario", ...}
var torre := {}
## Segundos da tela de apresentação do andar (só conta sem cartas de melhoria pendentes)
var intro_t := 0.0
var _fim_avisado := false
## Momentos (tempo restante, em segundos) em que a Bola aparece; sorteados por partida
var momentos_bola: Array[float] = []
## Jogo pausado pelo botão de pausa / Esc
var pausado := false
var _quadro_despausa := -1  ## quadro em que a pausa fechou (evita reabrir no mesmo aperto)
var _painel_pausa: Control
var _tremor := 0.0
var _t_nevoa := 0.0
var _t_fim := 0.0
var _vida_no_quadro := {}

# ------------------------------------------------------------------ Rede
## "" (partida local), "anfitriao" (simula e envia) ou "convidado" (só desenha)
var rede := ""
var _quadro := 0
var _fantasmas := {}      ## convidado: id da entidade no anfitrião -> Sprite2D
var _alvos := {}          ## convidado: nó -> posição recebida (para suavizar)
var _pulos_enviados := 0
var _descidas_enviadas := 0
var _dashes_enviados := 0
var _ultima_dir_dash := 0.0
const TEX_PROJETIL := {
	"flecha": preload("res://assets/sprites/flecha.png"),
	"orbe": preload("res://assets/sprites/orbe.png"),
	"item": preload("res://assets/sprites/item.png"),
	"bola": preload("res://assets/sprites/bola.png"),
}


func iniciar(config: Dictionary) -> void:
	## config: {"semente": int, "tempo": float, "bots": {1: dif, 2: dif}}
	##   dificuldade -1 = humano; 0, 1, 2, 3 = bot fácil, normal, difícil, muito difícil.
	## Chaves opcionais (padrão = partida normal): "itens", "monstros", "morte_subita",
	## "regen", "xp" (bool), "lutadores" ({n: estado}, ver Lutador.importar_estado) e
	## "torre" (dados do andar da Torre da Tormenta; ligam a apresentação e o fim de luta).
	rede = config.get("rede", "")
	if rede != "":
		Rede.partida = self
		Rede.desconectado.connect(_ao_perder_conexao)
	var rng := RandomNumberGenerator.new()
	rng.seed = config.get("semente", randi())
	tempo_restante = config.get("tempo", Jogo.TEMPO_PARTIDA)
	mapa = GeradorArena.gerar(rng)
	nav = mapa["nav"]
	portas = mapa["portas"]
	_montar_tiles(mapa["grade"])
	particulas = Particulas.new()
	particulas.grade = mapa["grade"]
	$Mundo.add_child(particulas)
	masmorra.particulas = particulas
	nevoa_visual.particulas = particulas
	desenho_portas.portas = portas
	nevoa_visual.partida = self
	nevoa_visual.material = masmorra.material_sem_sombra()
	hud.partida = self
	masmorra.configurar(mapa["grade"], rng, $Escuridao)
	Jogo.tocar_musica("batalha")
	Jogo.musica_tensa(false)

	var bots: Dictionary = config.get("bots", {1: -1, 2: -1})
	for n in [1, 2]:
		var dif: int = bots.get(n, -1)
		var c: Controle = ControleHumano.new(n) if dif < 0 else ControleBot.new(dif, self)
		if rede == "anfitriao" and n == 2:
			c = ControleRede.new()      # comandos do convidado chegam pela rede
		elif rede == "convidado":
			c = Controle.new()          # no convidado os personagens só são desenhados
		var l: Lutador = CENA_LUTADOR.instantiate()
		l.configurar(n, Jogo.dados_recruta(), self, c)
		l.position = mapa["inicio"][n]
		l.morreu.connect(_ao_morrer)
		entidades.add_child(l)
		l.add_child(masmorra.criar_luz(Color(0.85, 0.85, 1.0), 52.0, 0.8))
		if rede == "convidado":
			l.process_mode = Node.PROCESS_MODE_DISABLED
		jogadores[n] = l

	if Jogo.toque and not Jogo.tutorial_visto:
		_abrir_tutorial()
	if rede == "convidado":
		return  # quem simula monstros, tempo e regras é o anfitrião
	_sortear_momentos_bola(rng)
	itens_ligados = config.get("itens", true)
	monstros_ligados = config.get("monstros", true)
	morte_subita_ligada = config.get("morte_subita", true)
	regen = config.get("regen", true)
	xp_ligado = config.get("xp", true)
	torre = config.get("torre", {})
	# Só para testes: começa com classes definidas
	var classes: Dictionary = config.get("classes", {})
	for n in classes:
		jogadores[n].nivel = 2
		jogadores[n].receber_classe(Jogo.dados_classe(classes[n]))
	var estados: Dictionary = config.get("lutadores", {})
	for n in estados:
		jogadores[n].importar_estado(estados[n])
		# Melhoria ganha na vitória do andar anterior: escolher antes da contagem
		if estados[n].get("pendente", false):
			jogadores[n].escolhas.append(Melhorias.sortear(jogadores[n]))
	if not torre.is_empty():
		intro_t = 2.4
	if monstros_ligados:
		for i in 2:
			_criar_monstro()
	_congelar(true)  # tudo parado durante a contagem inicial
	if rede == "anfitriao":
		var remoto := config.duplicate()
		remoto["rede"] = "convidado"
		Rede.iniciar_partida_remota(remoto)


func _abrir_tutorial() -> void:
	## Primeira partida no celular: explica os gestos antes da contagem.
	var t: Control = preload("res://scripts/tutorial.gd").new()
	t.partida = self
	tutorial_aberto = true
	t.fechado.connect(func() -> void:
		tutorial_aberto = false
		Jogo.marcar_tutorial_visto())
	$HUD.add_child(t)


func _congelar(sim: bool) -> void:
	## Congela personagens, monstros, lacaios e projéteis (tochas e pingos seguem).
	if rede == "convidado":
		return
	entidades.process_mode = Node.PROCESS_MODE_DISABLED if sim else Node.PROCESS_MODE_INHERIT


func congelado() -> bool:
	return (pausado and rede == "") or contagem > 0.0


func espera_inicio() -> bool:
	## Torre: a contagem só começa depois das cartas de melhoria e da apresentação do andar.
	if contagem <= 0.0 or torre.is_empty():
		return false
	return intro_t > 0.0 or not jogadores[1].escolhas.is_empty()


func _retomar_com_contagem() -> void:
	contagem = 3.0
	for l in jogadores.values():
		l.ativo = false


func pausar() -> void:
	if pausado or fim:
		return
	pausado = true
	if rede == "":
		_congelar(true)  # em rede o jogo não para (o outro continua jogando)
	_painel_pausa = preload("res://scripts/painel_opcoes.gd").new()
	_painel_pausa.na_pausa = true
	_painel_pausa.continuar.connect(_despausar)
	_painel_pausa.sair_para_menu.connect(func() -> void: voltar.emit())
	$HUD.add_child(_painel_pausa)


func _despausar() -> void:
	_quadro_despausa = Engine.get_process_frames()
	if _painel_pausa != null:
		_painel_pausa.queue_free()
		_painel_pausa = null
	pausado = false
	if rede == "":
		_retomar_com_contagem()


func _atualizar_escolhas() -> void:
	# Teclas de melhoria dos humanos (o jogo continua rodando enquanto escolhe)
	for n in jogadores:
		var l: Lutador = jogadores[n]
		if l.controle is ControleHumano and l.vivo and not l.escolhas.is_empty() and not pausado:
			if Input.is_action_just_pressed(Jogo.acao(n, "opcao1")):
				l.escolher_melhoria(0)
			elif Input.is_action_just_pressed(Jogo.acao(n, "opcao2")):
				l.escolher_melhoria(1)


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


func oponente(l: Lutador) -> Lutador:
	return jogadores[2 if l.numero == 1 else 1]


# ------------------------------------------------------------------ Laço principal

func _process(delta: float) -> void:
	if rede == "convidado":
		_process_convidado(delta)
		return
	if not torre.is_empty() and not pausado and contagem > 0.0 and jogadores[1].escolhas.is_empty():
		intro_t = maxf(intro_t - delta, 0.0)
	if contagem > -1.0 and (not pausado or rede != "") and not (tutorial_aberto and rede == "") and not espera_inicio():
		var antes := contagem
		contagem -= delta
		if antes > 0.0 and contagem <= 0.0:
			_congelar(false)
			for l in jogadores.values():
				if l.vivo:
					l.ativo = true
	_atualizar_escolhas()
	# Pausa curtinha dos golpes fortes (contada em quadros, não em segundos)
	if _quadros_impacto > 0:
		_quadros_impacto -= 1
		if _quadros_impacto == 0 and not _camera_lenta:
			Engine.time_scale = 1.0
	_atualizar_enfeites(delta)

	if fim:
		_t_fim += delta
		if not torre.is_empty():
			# Na Torre quem decide o que vem depois é o controlador (sem revanche nem ESC aqui)
			if _t_fim > 2.6 and not _fim_avisado:
				_fim_avisado = true
				fim_de_luta.emit(vencedor)
			return
		if _t_fim > 1.5 and (Input.is_action_just_pressed("p1_pular") or Input.is_action_just_pressed("menu_ok")):
			revanche.emit()
	if fim and _t_fim > 1.5 and Input.is_action_just_pressed("menu_voltar"):
		voltar.emit()


func _physics_process(delta: float) -> void:
	if rede == "convidado":
		_physics_convidado()
		return
	if rede == "anfitriao":
		_quadro += 1
		if _quadro % 2 == 0:
			Rede.enviar_estado(_montar_estado())
	for n in jogadores:
		_vida_no_quadro[n] = jogadores[n].vida
	if contagem > 0.0 or (pausado and rede == ""):
		return
	if portas_abertas:
		_atravessar_portas(delta)
	_resgatar_fugitivos()
	if fim:
		return

	if not morte_subita:
		tempo_restante -= delta
		if tempo_restante <= 0.0:
			tempo_restante = 0.0
			if not morte_subita_ligada:
				_decidir_por_vida()
				return
			_iniciar_morte_subita()
		_t_monstro += delta
		var nivel := nivel_monstros()
		var intervalo := maxf(3.5, 6.0 - 0.4 * (nivel - 1))
		var maximo := 4 if nivel < 4 else 5
		if _tem_recruta():
			# Fase de Recruta: muitos monstros fracos valendo pouco XP
			intervalo = INTERVALO_MONSTRO_RECRUTA
			maximo = MAX_MONSTROS_RECRUTA
		if monstros_ligados and _t_monstro >= intervalo:
			_t_monstro = 0.0
			if _contar_equipe(0) < maximo:
				_criar_monstro()
		if itens_ligados:
			_atualizar_itens(delta)
	else:
		_atualizar_morte_subita(delta)


# ------------------------------------------------------------------ Regras de dano

func mult_pvp(atacante: Lutador, alvo: Lutador) -> float:
	var m := PVP_BASE
	if morte_subita:
		m = 1.0 + MORTE_SUBITA_AUMENTO * floorf(tempo_morte_subita / MORTE_SUBITA_DEGRAU)
	if atacante.eh_recruta:
		m *= PVP_RECRUTA_ATACA
	elif alvo.eh_recruta:
		m *= PVP_CONTRA_RECRUTA
	return m * PVP_GERAL


# ------------------------------------------------------------------ Classes

func sortear_classe(l: Lutador) -> void:
	## Sorteia uma classe sem repetir a do oponente.
	var outro := oponente(l)
	var opcoes: Array[ClasseDados] = []
	for i in Jogo.CLASSES.size():
		var candidata := Jogo.dados_classe(i)
		if outro.eh_recruta or outro.dados.nome != candidata.nome:
			opcoes.append(candidata)
	var d: ClasseDados = opcoes.pick_random()
	l.receber_classe(d)
	criar_brilho(l.position)
	criar_brilho(l.position + Vector2(0, -6))
	fx("classe", l.position, l.numero)
	tremer(1.5)
	_anunciar_classe(l.numero, d.nome)
	_evento(["classe", l.numero, Jogo.CLASSES.find(d.nome.to_lower())])


func _anunciar_classe(n: int, nome_classe: String) -> void:
	# Cada tela monta o texto do seu ponto de vista ("VOCÊ VIROU..." / "AMIGO VIROU...")
	var l: Lutador = jogadores[n]
	mostrar_anuncio("%s VIROU %s!" % [l.nome_jogador(), nome_classe.to_upper()], Jogo.COR_TIME[n], 2.0, false)


func mostrar_anuncio(texto: String, cor: Color, duracao := 2.0, enviar := true) -> void:
	if enviar:
		_evento(["anuncio", texto, cor.to_html(), duracao])
	anuncio = texto
	anuncio_cor = cor
	anuncio_t = duracao


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


func _resgatar_fugitivos() -> void:
	## Segurança: quem estiver fora da arena (ou preso no vão de uma porta
	## fechada) volta para dentro, na saída da porta mais próxima.
	var area := Rect2(TAM * 0.5, TAM * 0.5, GeradorArena.LARGURA - TAM, GeradorArena.ALTURA - TAM)
	for v in get_tree().get_nodes_in_group("viajante"):
		var p: Vector2 = v.position
		if area.has_point(p):
			continue
		if portas_abertas and p.x > -48 and p.x < GeradorArena.LARGURA + 48 and p.y > -64 and p.y < GeradorArena.ALTURA:
			continue  # atravessando uma porta aberta: normal
		if v is Projetil:
			v.queue_free()
			continue
		var melhor: Vector2 = mapa["inicio"][1]
		for porta in portas:
			var saida: Vector2 = porta["saida"]
			if saida.distance_to(p) < melhor.distance_to(p):
				melhor = saida
		v.position = melhor
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
	if not v is Projetil:
		fx("porta", v.position)
	v.position = para["saida"]
	v.cooldown_porta = 0.2
	if not v is Projetil:
		fx("porta", v.position)
	if v is Lutador:
		criar_brilho(v.position)
		Jogo.tocar("porta")


func _fechar_portas() -> void:
	portas_abertas = false
	nav.portas_abertas = false
	var g: Array = mapa["grade"]
	for porta in portas:
		for c in porta["celulas"]:
			g[c.y][c.x] = GeradorArena.SOLIDO
	_montar_tiles(g)
	desenho_portas.fechadas = true
	for porta in portas:
		var vao: Rect2 = porta["abertura"]
		for i in 3:
			particulas.fx("porta_fecha", vao.position + vao.size * Vector2(randf(), randf()))
	_tremor = maxf(_tremor, 2.5)


# ------------------------------------------------------------------ Morte Súbita

func _iniciar_morte_subita() -> void:
	morte_subita = true
	tempo_morte_subita = 0.0
	Jogo.musica_tensa(true)
	_fechar_portas()
	# A Bola da troca não sobrevive à Morte Súbita
	for it in get_tree().get_nodes_in_group("item"):
		if it.tipo == "bola":
			it.queue_free()
	for l in jogadores.values():
		if l.vivo and l.eh_recruta:
			sortear_classe(l)
	mostrar_anuncio("MORTE SÚBITA!", Color("b13e53"), 2.5)
	Jogo.tocar("morte")


func _atualizar_morte_subita(delta: float) -> void:
	tempo_morte_subita += delta
	nivel_nevoa = maxf(nivel_nevoa - NEVOA_VELOCIDADE * delta, -16.0)
	_t_nevoa += delta
	if _t_nevoa < NEVOA_INTERVALO:
		return
	_t_nevoa = 0.0
	for a in get_tree().get_nodes_in_group("alvo"):
		if a.esta_vivo() and a.position.y + 6.0 > nivel_nevoa:
			a.receber_dano(NEVOA_DANO, null)


# ------------------------------------------------------------------ Monstros

func _tem_recruta() -> bool:
	for l in jogadores.values():
		if l.vivo and l.eh_recruta:
			return true
	return false


func nivel_monstros() -> int:
	## Média dos níveis dos jogadores (arredondada para baixo). Usar a média,
	## e não o maior nível, evita que quem ficou para trás não consiga mais
	## matar monstros.
	var soma := 0
	for l in jogadores.values():
		soma += l.nivel
	return maxi(1, soma / maxi(jogadores.size(), 1))


func _criar_monstro() -> void:
	var pontos: Array = mapa["pontos_monstro"]
	if pontos.is_empty():
		return
	# Nasce longe dos jogadores: entre vários pontos sorteados, fica com o
	# que está mais distante do jogador mais próximo
	var pos: Vector2 = pontos.pick_random()
	var melhor_d := -1.0
	for tentativa in 12:
		var p: Vector2 = pontos.pick_random()
		var d := INF
		for l in jogadores.values():
			d = minf(d, l.position.distance_to(p))
		if d > melhor_d:
			melhor_d = d
			pos = p

	var n := nivel_monstros() - 1
	var faixa := clampi(1 + n / 2, 1, 4)  # níveis 1, 2-3, 4-5, 6+
	var m: Minion = CENA_MINION.instantiate()
	m.configurar(self, 0, null, TEX_GOSMA[faixa - 1],
			VIDA_MONSTRO * pow(1.35, n),     # vida
			DANO_MONSTRO * pow(1.2, n),      # dano
			minf(30.0 * (1.0 + 0.08 * n), 60.0),  # velocidade
			minf(70.0 + 15.0 * n, 170.0),    # visão
			XP_MONSTRO_NIVEL_1 if n == 0 else 4 + 2 * n)  # XP
	m.intervalo_ataque = maxf(0.9 * pow(0.93, n), 0.5)
	m.defensivo = n == 0  # nível 1: só revida
	m.position = pos
	entidades.add_child(m)
	criar_brilho(m.position)
	fx("nasce", m.position)


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
	p.dano_min = dono.ataque.dano_minimo_magia
	p.raio_explosao = dono.raio_explosao
	entidades.add_child(p)


func criar_lacaio(rei: Lutador) -> void:
	var m: Minion = CENA_MINION.instantiate()
	m.configurar(self, rei.equipe, rei, TEX_LACAIO[rei.equipe],
			rei.ataque.vida_lacaio * rei.mult_lacaio, rei.atk_dano() * rei.mult_lacaio,
			rei.ataque.velocidade_lacaio, 2000.0, 2)
	m.intervalo_ataque = 1.2
	m.alcance_arremesso = 90.0
	m.position = rei.position
	entidades.add_child(m)
	criar_brilho(m.position)
	fx("invocar", m.position, rei.equipe)
	Jogo.tocar("invocar")


func criar_lanca(lacaio: Minion, alvo) -> void:
	## Lança arremessada por um lacaio: mais fraca e lenta que as flechas.
	var p := Projetil.new()
	p.partida = self
	p.dono = lacaio.dono
	p.equipe = lacaio.equipe
	p.position = lacaio.position
	p.velocity = (alvo.global_position - lacaio.global_position).normalized() * 130.0
	p.dano = lacaio.dano * 0.6
	p.alcance_max = 110.0
	p.de_lacaio = true
	entidades.add_child(p)
	Jogo.tocar("flecha")


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


func criar_corte(pos: Vector2, espelhar: bool) -> void:
	_evento(["corte", pos.x, pos.y, espelhar])
	var s := Sprite2D.new()
	s.texture = TEX_CORTE
	s.material = masmorra.material_sem_sombra()
	s.hframes = 2
	s.flip_h = espelhar
	s.position = pos
	entidades.add_child(s)
	var tw := s.create_tween()
	tw.tween_interval(0.06)
	tw.tween_callback(func() -> void: s.frame = 1)
	tw.tween_interval(0.08)
	tw.tween_callback(s.queue_free)


func tremer(forca: float) -> void:
	_evento(["tremer", forca])
	_tremor = maxf(_tremor, forca)


func fx(nome: String, pos: Vector2, a = 0.0, b = 0.0) -> void:
	## Efeito de partículas (posição em coordenadas do mundo). O anfitrião
	## repassa para o convidado, que repete o mesmo efeito.
	_evento(["fx", nome, pos.x, pos.y, a, b])
	if nome == "estilhaco":
		# a = nome da textura do monstro/lacaio, b = [quadro, espelhado, ângulo do golpe]
		var tex: Texture2D = load("res://assets/sprites/%s.png" % a)
		var larg := tex.get_width() / 2
		var dados: Array = b
		particulas.estilhacar(tex, Rect2i(int(dados[0]) * larg, 0, larg, tex.get_height()), pos, dados[1],
				1.0, Vector2.from_angle(dados[2]) * 60.0)
		return
	particulas.fx(nome, pos, a, b)


func impacto(quadros: int) -> void:
	## Golpe forte: o jogo inteiro segura por alguns quadros (dá peso à pancada).
	if not Jogo.impacto or fim or rede == "convidado":
		return
	_quadros_impacto = maxi(_quadros_impacto, quadros)
	Engine.time_scale = 0.05


func _atualizar_enfeites(delta: float) -> void:
	## Anúncio, tremor de tela e festa do vencedor (igual no anfitrião e no convidado).
	if anuncio_t > 0.0:
		anuncio_t -= delta
	var mundo: Node2D = $Mundo
	if _tremor > 0.05 and Jogo.impacto:
		mundo.position = Vector2(0, 8) + Vector2(randf_range(-1, 1), randf_range(-1, 1)).round() * minf(_tremor, 3.0)
		_tremor = move_toward(_tremor, 0.0, delta * 10.0)
	else:
		_tremor = 0.0
		mundo.position = Vector2(0, 8)
	if fim and vencedor != 0 and jogadores[vencedor].vivo:
		_t_confete += delta
		if _t_confete < 3.0 and int(_t_confete * 20.0) != int((_t_confete - delta) * 20.0):
			particulas.fx("confete", jogadores[vencedor].position + Vector2(0, -6), vencedor)


func criar_poeira(pos: Vector2) -> void:
	## Pouso pesado (Orc): nuvem de poeira e lascas de pedra.
	_evento(["poeira", pos.x, pos.y])
	if rede != "convidado":
		Jogo.tocar("pouso")  # no convidado o som chega como evento próprio
	particulas.fx("pouso_pesado", pos)


func criar_brilho(pos: Vector2) -> void:
	_evento(["brilho", pos.x, pos.y])
	var s := Sprite2D.new()
	s.texture = TEX_BRILHO
	s.hframes = 3
	s.position = pos
	s.material = masmorra.material_sem_sombra()
	entidades.add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "frame", 2, 0.2)
	tw.tween_callback(s.queue_free)


func mostrar_texto(pos: Vector2, texto: String, cor: Color, forte := false) -> void:
	## Texto que salta do personagem (dano, XP, melhoria). `forte` = golpe grande.
	_evento(["texto", pos.x, pos.y, texto, cor.to_html(), forte])
	var l: Node2D = preload("res://scripts/texto_flutuante.gd").new()
	l.texto = texto
	l.tam = UI.M if forte else UI.P
	l.cor = cor
	l.position = (pos + Vector2(randf_range(-5.0, 5.0), 0.0)).round()
	l.z_index = 10
	l.material = masmorra.material_sem_sombra()
	entidades.add_child(l)
	# Salta para cima, para um instante e some piscando (sem ficar transparente)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - (18.0 if forte else 12.0), 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.3 if forte else 0.2)
	for i in 3:
		tw.tween_callback(l.hide)
		tw.tween_interval(0.04)
		tw.tween_callback(l.show)
		tw.tween_interval(0.04)
	tw.tween_callback(l.queue_free)


# ------------------------------------------------------------------ Fim de partida

func _ao_morrer(_l: Lutador) -> void:
	if not fim and rede != "convidado":
		call_deferred("_decidir_vencedor")


func _decidir_vencedor() -> void:
	if fim:
		return
	var vivos: Array = jogadores.values().filter(func(j): return j.vivo)
	if vivos.size() == 1:
		vencedor = vivos[0].numero
	elif vivos.is_empty():
		# Os dois caíram juntos: vence quem tinha mais vida antes do golpe final
		var v1: float = _vida_no_quadro.get(1, 0.0)
		var v2: float = _vida_no_quadro.get(2, 0.0)
		vencedor = 1 if v1 > v2 else (2 if v2 > v1 else 0)
	else:
		return
	await _encerrar(true)


func _decidir_por_vida() -> void:
	## Fim do tempo sem Morte Súbita: vence quem tem a maior porcentagem de vida.
	## Empate vence o jogador 2 (na Torre, a CPU).
	if fim:
		return
	var f1: float = jogadores[1].vida / jogadores[1].vida_max
	var f2: float = jogadores[2].vida / jogadores[2].vida_max
	vencedor = 1 if f1 > f2 else 2
	await _encerrar(false)


func _encerrar(camera_lenta: bool) -> void:
	fim = true
	for j in jogadores.values():
		j.ativo = false
	_quadros_impacto = 0
	if camera_lenta:
		_camera_lenta = true
		Engine.time_scale = 0.3
		await get_tree().create_timer(0.7, true, false, true).timeout
		_camera_lenta = false
		Engine.time_scale = 1.0
	Jogo.tocar("vitoria")


func _ready() -> void:
	Jogo.partida = self
	Jogo.pausa_pedida.connect(_ao_pedir_pausa)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if Jogo.partida == self:
		Jogo.partida = null
	if Jogo.pausa_pedida.is_connected(_ao_pedir_pausa):
		Jogo.pausa_pedida.disconnect(_ao_pedir_pausa)


func _ao_pedir_pausa() -> void:
	## Start/Back/Esc/P (Jogo.pausa_pedida). Só ABRE a pausa; o painel fecha a si mesmo
	## com o mesmo sinal. Se acabou de fechar neste quadro, não reabre (um aperto só).
	if fim or pausado or Engine.get_process_frames() == _quadro_despausa:
		return
	pausar()


# ------------------------------------------------------------------ Itens

func _sortear_momentos_bola(_rng: RandomNumberGenerator) -> void:
	## Uma única aparição da Bola, aos MOMENTO_BOLA s de partida (em tempo restante).
	momentos_bola.clear()
	var t := tempo_restante - MOMENTO_BOLA
	if t > 0.0:
		momentos_bola.append(t)


func _atualizar_itens(delta: float) -> void:
	# Itens de efeito: um a cada INTERVALO_ITEM s, no máximo MAX_ITENS no mapa
	_t_item += delta
	var itens := get_tree().get_nodes_in_group("item")
	var efeitos := itens.filter(func(i): return i.tipo == "efeito").size()
	if _t_item >= INTERVALO_ITEM:
		_t_item = 0.0
		if efeitos < MAX_ITENS:
			_criar_item("efeito")
	# Bola: no momento sorteado, se os dois já tiverem classe (senão espera)
	var tem_bola := itens.any(func(i): return i.tipo == "bola")
	if not momentos_bola.is_empty() and tempo_restante <= momentos_bola[0] and not tem_bola and not _tem_recruta():
		momentos_bola.pop_front()
		_criar_item("bola")
		mostrar_anuncio("A BOLA DA TROCA APARECEU!", Color("73eff7"), 2.0)
		Jogo.tocar("bola")
	# Quem encostar pega
	for it in itens:
		if not is_instance_valid(it) or it.is_queued_for_deletion():
			continue
		for l in jogadores.values():
			if it.tocando(l):
				_pegar_item(it, l)
				break


func _criar_item(tipo: String) -> void:
	var it := Item.new()
	it.tipo = tipo
	if tipo == "bola":
		it.duracao = INF  # some só quando alguém pega ou começa a Morte Súbita
		it.position = _ponto_topo_central() + Vector2(0, -2)
		entidades.add_child(it)
		criar_brilho(it.position)
		return
	# Nasce longe dos jogadores
	var pontos: Array = mapa["pontos_monstro"]
	var pos: Vector2 = pontos.pick_random()
	var melhor_d := -1.0
	for tentativa in 10:
		var p: Vector2 = pontos.pick_random()
		var d := INF
		for l in jogadores.values():
			d = minf(d, l.position.distance_to(p))
		if d > melhor_d:
			melhor_d = d
			pos = p
	it.position = pos + Vector2(0, -2)
	entidades.add_child(it)
	criar_brilho(it.position)


func _ponto_topo_central() -> Vector2:
	## Ponto alcançável (onde nascem monstros) no andar mais alto da arena,
	## o mais perto possível do centro na horizontal.
	var pontos: Array = mapa["pontos_monstro"]
	var topo := INF
	for p in pontos:
		topo = minf(topo, (p as Vector2).y)
	var meio := GeradorArena.LARGURA / 2.0
	var melhor := Vector2(INF, INF)
	for p in pontos:
		var v: Vector2 = p
		if v.y <= topo + TAM * 2.0 and absf(v.x - meio) < absf(melhor.x - meio):
			melhor = v
	return melhor


func _pegar_item(it: Item, l: Lutador) -> void:
	it.queue_free()
	criar_brilho(it.position)
	fx("item", it.position)
	if it.tipo == "bola":
		var outro := oponente(l)
		var opcoes: Array[ClasseDados] = []
		for i in Jogo.CLASSES.size():
			var c := Jogo.dados_classe(i)
			if c.nome != l.dados.nome and (outro.eh_recruta or c.nome != outro.dados.nome):
				opcoes.append(c)
		var d: ClasseDados = opcoes.pick_random()
		l.trocar_classe(d)
		fx("classe", l.position, l.numero)
		_anunciar_classe(l.numero, d.nome)
		_evento(["classe", l.numero, Jogo.CLASSES.find(d.nome.to_lower())])
		Jogo.tocar("bola")
	else:
		l.aplicar_efeito(Item.EFEITOS.pick_random())
		mostrar_texto(l.position + Vector2(0, -24), l.nome_efeito(), Color("f4a2f4"))
		Jogo.tocar("item")


# ------------------------------------------------------------------ Rede: anfitrião

func _evento(e: Array) -> void:
	if rede == "anfitriao":
		Rede.evento(e)


func escolher(n: int, op: int) -> void:
	## Escolha de melhoria vinda do HUD (clique/toque na carta).
	if rede == "convidado":
		Rede.enviar_escolha(op)
	else:
		jogadores[n].escolher_melhoria(op)


func e_local(n: int) -> bool:
	## Este jogador é controlado por quem está olhando esta tela?
	if rede != "":
		return n == Rede.numero_local()
	return jogadores[n].controle is ControleHumano


func receber_entrada_remota(estado: Array) -> void:
	var c = jogadores[2].controle
	if c is ControleRede:
		c.receber(estado)


func receber_escolha_remota(op: int) -> void:
	jogadores[2].escolher_melhoria(op)


func _indice_classe(l: Lutador) -> int:
	return -1 if l.eh_recruta else Jogo.CLASSES.find(l.dados.nome.to_lower())


func _montar_estado() -> Dictionary:
	var js: Array = []
	for n in [1, 2]:
		var l: Lutador = jogadores[n]
		var esc: Array = []
		if not l.escolhas.is_empty():
			esc = [l.escolhas[0][0]["id"], l.escolhas[0][1]["id"], l.escolhas.size()]
		js.append([l.position.x, l.position.y, l.sprite.frame, l.sprite.flip_h, l.vida, l.vida_max,
				l.nivel, l.xp, l.xp_para_proximo(), _indice_classe(l), l.vivo, esc, l._flash > 0.0,
				l.efeito, l.efeito_t, Jogo.CLASSES.find(l.ataque.nome.to_lower())])
	var es: Array = []
	for e in entidades.get_children():
		if e is Minion and e.vivo:
			es.append([e.get_instance_id(), e.textura.resource_path.get_file().get_basename(),
					e.position.x, e.position.y, e.sprite.frame, e.sprite.flip_h, 0.0, 1.0])
		elif e is Item:
			es.append([e.get_instance_id(), e.chave_visual(), e.position.x, e.position.y,
					e._sprite.frame if e._sprite != null else 0, false, e._sprite.rotation if e._sprite != null else 0.0, 1.0])
		elif e is Projetil and e._sprite != null:
			es.append([e.get_instance_id(), "orbe" if e.magia else "flecha",
					e.position.x, e.position.y, e._sprite.frame, false, e.rotation, e._sprite.scale.x])
	return {"t": tempo_restante, "c": contagem, "ms": morte_subita, "tm": tempo_morte_subita,
			"nv": nivel_nevoa, "f": fim, "v": vencedor, "pa": portas_abertas, "j": js, "e": es}


func _ao_perder_conexao() -> void:
	if not is_inside_tree():
		return
	mostrar_anuncio("CONEXÃO PERDIDA", Color("b13e53"), 3.0, false)
	await get_tree().create_timer(2.5).timeout
	voltar.emit()


# ------------------------------------------------------------------ Rede: convidado

func _process_convidado(delta: float) -> void:
	_atualizar_enfeites(delta)
	var eu: Lutador = jogadores[2]
	if not eu.escolhas.is_empty() and not pausado:
		if Input.is_action_just_pressed("p1_opcao1"):
			Rede.enviar_escolha(0)
		elif Input.is_action_just_pressed("p1_opcao2"):
			Rede.enviar_escolha(1)
	if fim and _t_fim > 1.5 and Input.is_action_just_pressed("menu_voltar"):
		voltar.emit()


func _physics_convidado() -> void:
	# Comandos deste jogador vão para o anfitrião (o convidado usa os controles do P1)
	if not pausado:
		if Input.is_action_just_pressed("p1_pular"):
			_pulos_enviados += 1
		if Input.is_action_just_pressed("p1_descer"):
			_descidas_enviadas += 1
		if Input.is_action_just_pressed("p1_dash") or Input.is_action_just_pressed("p1_dash_esq") \
				or Input.is_action_just_pressed("p1_dash_dir"):
			_dashes_enviados += 1
			_ultima_dir_dash = (1.0 if Input.is_action_pressed("p1_dash_dir") else 0.0) \
					- (1.0 if Input.is_action_pressed("p1_dash_esq") else 0.0)
		Rede.enviar_entrada([Input.get_axis("p1_esquerda", "p1_direita"), _pulos_enviados,
				Input.is_action_pressed("p1_pular"), _descidas_enviadas, _dashes_enviados, _ultima_dir_dash])
	else:
		Rede.enviar_entrada([0.0, _pulos_enviados, false, _descidas_enviadas, _dashes_enviados, _ultima_dir_dash])
	# Suaviza o movimento entre um pacote e outro
	for no in _alvos.keys():
		if not is_instance_valid(no):
			_alvos.erase(no)
			continue
		var alvo: Vector2 = _alvos[no]
		if no.position.distance_to(alvo) > 48.0:
			no.position = alvo  # teleporte (porta)
		else:
			no.position = no.position.lerp(alvo, 0.5)
	# Enfeites que o convidado gera sozinho (não precisam vir pela rede)
	for f in _fantasmas.values():
		match f.get_meta("tipo", ""):
			"orbe":
				particulas.fx("rastro_orbe", f.position, f.scale.x)
			"flecha":
				particulas.fx("rastro_flecha", f.position)
	_quadro += 1
	if _quadro % 8 == 0:
		for l in jogadores.values():
			if l.vivo and l.sprite.frame >= 2 and l.sprite.frame <= 5:
				particulas.fx("correr", l.position + Vector2(0, 8), 1.0 if l.sprite.flip_h else -1.0)


func aplicar_estado(s: Dictionary) -> void:
	tempo_restante = s["t"]
	contagem = s["c"]
	tempo_morte_subita = s["tm"]
	nivel_nevoa = s["nv"]
	vencedor = s["v"]
	if s["ms"] and not morte_subita:
		morte_subita = true
		Jogo.musica_tensa(true)
	if not s["pa"] and portas_abertas:
		_fechar_portas()
	if s["f"] and not fim:
		fim = true
	for i in 2:
		_aplicar_jogador(jogadores[i + 1], s["j"][i])
	# Monstros, lacaios e projéteis: cria, move e remove "fantasmas"
	var vistos := {}
	for e in s["e"]:
		var id: int = e[0]
		vistos[id] = true
		var f: Sprite2D = _fantasmas.get(id)
		if f == null:
			f = _criar_fantasma(e[1])
			f.position = Vector2(e[2], e[3])
			_fantasmas[id] = f
		_alvos[f] = Vector2(e[2], e[3])
		f.frame = mini(int(e[4]), f.hframes - 1)
		f.flip_h = e[5]
		f.rotation = e[6]
		f.scale = Vector2.ONE * float(e[7])
	for id in _fantasmas.keys():
		if not vistos.has(id):
			_fantasmas[id].queue_free()
			_fantasmas.erase(id)


func _criar_fantasma(tipo: String) -> Sprite2D:
	var f := Sprite2D.new()
	f.set_meta("tipo", tipo)
	if TEX_PROJETIL.has(tipo):
		f.texture = TEX_PROJETIL[tipo]
		f.hframes = 1 if tipo == "flecha" else 2
		f.material = masmorra.material_sem_sombra()
	else:
		f.texture = load("res://assets/sprites/%s.png" % tipo)
		f.hframes = 2
	entidades.add_child(f)
	return f


func _aplicar_jogador(l: Lutador, d: Array) -> void:
	_alvos[l] = Vector2(d[0], d[1])
	var classe: int = d[9]
	if classe >= 0 and (l.eh_recruta or Jogo.CLASSES.find(l.dados.nome.to_lower()) != classe):
		l.eh_recruta = false
		l.dados = Jogo.dados_classe(classe)
		l.sprite.texture = l.dados.textura_p1 if l.numero == 1 else l.dados.textura_p2
	l.sprite.frame = d[2]
	l.sprite.flip_h = d[3]
	l.vida = d[4]
	l.vida_max = d[5]
	l.nivel = d[6]
	l.xp = d[7]
	Jogo.pintar_clarao(l.sprite, d[12])
	# Efeito de item (tamanho, gravidade, ataque trocado)
	if d[13] != l.efeito:
		if d[13] == "":
			l._encerrar_efeito()
		else:
			l.aplicar_efeito(d[13])
	l.efeito_t = d[14]
	if l.efeito == "ataque" and int(d[15]) >= 0:
		l.ataque = Jogo.dados_classe(d[15])
	var esc: Array = d[11]
	l.escolhas.clear()
	if not esc.is_empty():
		var par := [Melhorias.por_id(esc[0]), Melhorias.por_id(esc[1])]
		for k in int(esc[2]):
			l.escolhas.append(par)
	if l.vivo and not d[10]:
		l.vivo = false
		l.desfazer()
	l.queue_redraw()


func aplicar_evento(e: Array) -> void:
	match e[0]:
		"som":
			Jogo.tocar(e[1])
		"texto":
			mostrar_texto(Vector2(e[1], e[2]), e[3], Color(e[4]), e.size() > 5 and e[5])
		"fx":
			fx(e[1], Vector2(e[2], e[3]), e[4], e[5])
		"brilho":
			criar_brilho(Vector2(e[1], e[2]))
		"corte":
			criar_corte(Vector2(e[1], e[2]), e[3])
		"poeira":
			criar_poeira(Vector2(e[1], e[2]))
		"tremer":
			tremer(e[1])
		"anuncio":
			mostrar_anuncio(e[1], Color(e[2]), e[3], false)
		"classe":
			if int(e[2]) >= 0:
				_anunciar_classe(e[1], Jogo.dados_classe(e[2]).nome)
