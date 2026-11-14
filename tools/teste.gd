extends SceneTree
## Teste automático (sem janela). Também roda no GitHub Actions antes de cada build.
##
##   godot --headless --fixed-fps 60 --path . -s tools/teste.gd
##   godot --headless --fixed-fps 60 --path . -s tools/teste.gd -- --equilibrio 60
##
## 1) Gera muitos mapas e confere portas e alcance de todos os lugares.
## 2) Simula partidas bot contra bot (com tempo curto, para passar pela Morte Súbita).
## Com --equilibrio N, roda N partidas e mostra a taxa de vitória de cada classe.

const MAPAS := 1500
const NOMES_DIF := ["FÁCIL", "NORMAL", "DIFÍCIL"]

var _falhas := 0
## Scripts que dependem do autoload Jogo: carregados em _initialize (não dá para citar a classe aqui)
var _torre_script: GDScript
var _bot_script: GDScript


func _initialize() -> void:
	_torre_script = load("res://scripts/torre.gd")
	_bot_script = load("res://scripts/controle_bot.gd")
	var args := OS.get_cmdline_user_args()
	var i := args.find("--equilibrio")
	if i >= 0:
		await _equilibrio(int(args[i + 1]) if args.size() > i + 1 else 40)
		quit(0)
		return
	i = args.find("--confrontos")
	if i >= 0:
		var j := args.find("--par")
		var par: Array = [] if j < 0 else [int(args[j + 1]), int(args[j + 2])]
		await _confrontos(int(args[i + 1]) if args.size() > i + 1 else 8, par)
		quit(0)
		return
	_testar_mapas()
	await _testar_pulos_e_itens()
	await _testar_dinamica()
	await _testar_dash()
	_testar_dash_rede()
	_testar_mapeamento_controle()
	_testar_controle_mapa()
	await _testar_controle_menus()
	await _testar_pausa_partida()
	await _testar_cartas_layout()
	_testar_bot_muito_dificil()
	await _testar_menu_navegacao()
	await _testar_torre()
	await _testar_torre_fim_do_tempo()
	await _testar_partidas()
	print("RESULTADO: ", "OK" if _falhas == 0 else "%d FALHA(S)" % _falhas)
	quit(1 if _falhas else 0)


func _falha(msg: String) -> void:
	_falhas += 1
	printerr("FALHA: ", msg)


# ------------------------------------------------------------------ Mapas

func _testar_mapas() -> void:
	var tentativas := 0
	var tetos := 0
	for semente in MAPAS:
		var rng := RandomNumberGenerator.new()
		rng.seed = semente
		var m := GeradorArena.gerar(rng)
		if m.is_empty():
			_falha("semente %d: gerador desistiu" % semente)
			continue
		tentativas += m["tentativas"]
		var g: Array = m["grade"]
		var nav: Navegacao = m["nav"]
		var portas: Array = m["portas"]
		var esq := portas.filter(func(p): return p["tipo"] == "esq").size()
		var dir := portas.filter(func(p): return p["tipo"] == "dir").size()
		var teto := portas.filter(func(p): return p["tipo"] == "teto").size()
		tetos += teto
		if maxi(esq, dir) < GeradorArena.MIN_PARES_PORTAS:
			_falha("semente %d: menos de 2 pares de portas" % semente)
		if maxi(esq, dir) != mini(esq, dir) + teto:
			_falha("semente %d: conta das portas não fecha" % semente)
		for p in portas:
			var par: Dictionary = portas[p["par"]]
			if portas[par["par"]] != p or par["tipo"] == p["tipo"]:
				_falha("semente %d: par de portas inválido" % semente)
			if not nav.nos.has(p["no_saida"]):
				_falha("semente %d: saída de porta sem chão" % semente)
		# Todo lugar alcançável a partir dos dois inícios, e com caminho de volta
		for n in [1, 2]:
			var inicio: Vector2i = GeradorArena.NO_INICIO[n]
			var ida := nav.distancias(inicio)
			var volta := nav.alcanca_de_volta(inicio)
			if ida.size() != nav.nos.size() or volta.size() != nav.nos.size():
				_falha("semente %d: há lugares inalcançáveis a partir do P%d" % [semente, n])
		# Nenhuma plataforma "fantasma" (sem lugar para pisar em cima)
		for y in range(1, GeradorArena.LINHAS - 1):
			for x in range(1, GeradorArena.COLUNAS - 1):
				if g[y][x] == GeradorArena.PLATAFORMA and g[y - 1][x] == GeradorArena.VAZIO \
						and not nav.nos.has(Vector2i(x, y - 1)):
					_falha("semente %d: plataforma sem nó em (%d,%d)" % [semente, x, y])
	print("Mapas: %d válidos, %.2f tentativas em média, %d portas no teto" % [
			MAPAS, float(tentativas) / MAPAS, tetos])


# ------------------------------------------------------------------ Partidas

func _jogar(main, config: Dictionary, max_quadros: int) -> Dictionary:
	main._nova_partida(config)
	await process_frame
	var p = main._atual
	# Se algum script quebrou, a partida não monta: isso tem que reprovar o teste
	if p == null or p.get("mapa") == null or p.mapa.is_empty() or p.jogadores.size() != 2:
		_falha("a partida não foi montada (erro de script?)")
		return {}
	var max_nivel := 0
	var teleportes := 0
	var pos_antes := {}
	var viu_classe := {1: false, 2: false}
	for f in max_quadros:
		await physics_frame
		for n in [1, 2]:
			var l = p.jogadores[n]
			if pos_antes.has(n) and l.position.distance_to(pos_antes[n]) > 100:
				teleportes += 1
			pos_antes[n] = l.position
			max_nivel = maxi(max_nivel, l.nivel)
			if not l.eh_recruta:
				viu_classe[n] = true
			if l.vivo and (l.position.y > GeradorArena.ALTURA or l.position.x < -40 or l.position.x > GeradorArena.LARGURA + 40):
				_falha("jogador %d fora da arena em %s" % [n, l.position])
		if p.fim:
			break
	var classes := {}
	for n in [1, 2]:
		classes[n] = p.jogadores[n].dados.nome
	if not p.jogadores[1].eh_recruta and not p.jogadores[2].eh_recruta and classes[1] == classes[2]:
		_falha("os dois jogadores receberam a mesma classe (%s)" % classes[1])
	return {
		"fim": p.fim, "vencedor": p.vencedor, "classes": classes, "nivel": max_nivel,
		"teleportes": teleportes, "morte_subita": p.morte_subita, "viu_classe": viu_classe,
		"tempo": p.tempo_restante,
	}


func _testar_partidas() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var duelos := [[0, 0], [1, 1], [2, 2], [2, 0]]
	var jogadas := 0
	if main.get("_toque") == null:
		_falha("main.gd não criou os controles na tela (erro de script?)")
	for d in duelos:
		var config := {"semente": 1000 + d[0] * 10 + d[1], "tempo": 45.0, "bots": {1: d[0], 2: d[1]}}
		var r: Dictionary = await _jogar(main, config, 60 * 140)
		if r.is_empty():
			continue
		jogadas += 1
		print("bot %s x bot %s | %-9s x %-9s | nível máx %d | portas %d | súbita: %s | fim: %s" % [
			NOMES_DIF[d[0]], NOMES_DIF[d[1]], r["classes"][1], r["classes"][2],
			r["nivel"], r["teleportes"], r["morte_subita"],
			("P%d venceu" % r["vencedor"]) if r["fim"] else "NÃO"])
		if not r["fim"]:
			_falha("partida não terminou mesmo com a Morte Súbita")
	if jogadas != duelos.size():
		_falha("só %d de %d partidas rodaram" % [jogadas, duelos.size()])
	main.queue_free()


func _testar_pulos_e_itens() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._nova_partida({"semente": 77, "tempo": 180.0, "bots": {1: -1, 2: -1}})
	await process_frame
	var p = main._atual
	p.contagem = 0.0
	p._congelar(false)
	var l = p.jogadores[1]
	var jogo = root.get_node("Jogo")
	var nomes: Array = ["recruta"] + Array(jogo.CLASSES)
	var alturas := []
	for nome in nomes:
		l.receber_classe(load("res://resources/classes/%s.tres" % nome))
		l.eh_recruta = nome == "recruta"
		l.position = p.mapa["inicio"][1]
		l.velocity = Vector2.ZERO
		for f in 30:
			await physics_frame
		var chao: float = l.position.y
		l.velocity.y = -l.forca_pulo
		var menor := chao
		for f in 90:
			await physics_frame
			menor = minf(menor, l.position.y)
		var blocos := (chao - menor) / 16.0
		alturas.append("%s %.1f" % [nome, blocos])
		if blocos < 3.5:
			_falha("%s pula só %.2f blocos (mínimo 3,5)" % [nome, blocos])
	print("Pulo (blocos): ", ", ".join(alturas))

	# Efeitos de item: aplicam e voltam ao normal
	l.receber_classe(load("res://resources/classes/orc.tres"))
	l.eh_recruta = false
	var dano0: float = l.atk_dano()
	for ef in ["pequeno", "grande", "gravidade", "ataque"]:
		l.aplicar_efeito(ef)
		var mudou: bool = l.escala != 1.0 or l.gravidade_invertida or l.ataque != l.dados
		if not mudou:
			_falha("efeito %s não mudou nada" % ef)
		l.efeito_t = 0.01
		for f in 3:
			await physics_frame
		if l.efeito != "" or l.escala != 1.0 or l.gravidade_invertida or l.ataque != l.dados or l.atk_dano() != dano0:
			_falha("efeito %s não voltou ao normal" % ef)
	# Bola: troca de classe mantendo nível e melhorias, sem repetir a do oponente
	var o = p.jogadores[2]
	o.receber_classe(load("res://resources/classes/mago.tres"))
	o.eh_recruta = false
	l.nivel = 5
	jogo_melhoria(l, "forca")
	jogo_melhoria(l, "sangue")
	for k in 12:
		var bola = load("res://scripts/item.gd").new()
		bola.tipo = "bola"
		bola.position = l.position
		p.entidades.add_child(bola)
		p._pegar_item(bola, l)
		if l.dados.nome == "Mago":
			_falha("a Bola deu a mesma classe do oponente")
		if l.nivel != 5 or not ("forca" in l.historico) or l.historico.size() != 2:
			_falha("a Bola perdeu nível/melhorias: nível %d, %s" % [l.nivel, l.historico])
		if not Melhorias.e_especial(l.historico[1]) or Melhorias.ESPECIAIS[l.dados.tipo_ataque]["id"] != l.historico[1]:
			_falha("a melhoria especial não virou a da classe nova")
	print("Itens e Bola: ok")
	main.queue_free()
	await process_frame


func _testar_dinamica() -> void:
	## Bola única aos 2 min no topo central, que some na Morte Súbita; PvP +35%.
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._nova_partida({"semente": 31, "tempo": 180.0, "bots": {1: -1, 2: -1}})
	await process_frame
	var p = main._atual
	if p.momentos_bola.size() != 1 or absf(p.momentos_bola[0] - 60.0) > 0.01:
		_falha("Bola deveria aparecer uma vez com 60 s restantes: %s" % [p.momentos_bola])
	var pos: Vector2 = p._ponto_topo_central()
	var topo := INF
	for q in p.mapa["pontos_monstro"]:
		topo = minf(topo, (q as Vector2).y)
	if pos.y > topo + p.TAM * 2.0:
		_falha("Bola não nasceu no alto da arena (y %.0f, topo %.0f)" % [pos.y, topo])
	for l in p.jogadores.values():
		l.eh_recruta = false
	p._criar_item("bola")
	var bolas := root.get_tree().get_nodes_in_group("item").filter(func(i): return i.tipo == "bola")
	if bolas.size() != 1 or bolas[0].position.distance_to(pos) > 4.0:
		_falha("Bola não apareceu no topo central")
	for f in 120:  # 2 s: continua no lugar (só flutua)
		await physics_frame
	if is_instance_valid(bolas[0]) and bolas[0].position.distance_to(pos) > 6.0:
		_falha("Bola saiu do topo central: %s" % bolas[0].position)
	p._iniciar_morte_subita()
	await process_frame
	if root.get_tree().get_nodes_in_group("item").any(func(i): return is_instance_valid(i) and i.tipo == "bola" and not i.is_queued_for_deletion()):
		_falha("Bola continuou depois da Morte Súbita")
	p.morte_subita = false
	var a = p.jogadores[1]
	var b = p.jogadores[2]
	if absf(p.mult_pvp(a, b) - p.PVP_BASE * 1.35) > 0.001:
		_falha("PvP deveria ser 0,4 x 1,35: %.3f" % p.mult_pvp(a, b))
	if a.XP_PARA_CLASSE != 8 or a.CURA_NIVEL != 0.02:
		_falha("Recruta/cura com valores inesperados")
	print("Dinâmica (Bola, PvP, Recruta): ok")
	main.queue_free()
	await process_frame


func _testar_dash() -> void:
	## Dash: desloca bem mais que andar, tem recarga e só um no ar até pousar.
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._nova_partida({"semente": 77, "tempo": 180.0, "bots": {1: -1, 2: -1}})
	await process_frame
	var p = main._atual
	p.contagem = 0.0
	p._congelar(false)
	var l = p.jogadores[1]
	l.receber_classe(load("res://resources/classes/orc.tres"))
	l.eh_recruta = false
	var c := ControleTeste.new()
	l.controle = c
	l.ativo = true
	p.jogadores[2].ativo = false
	var base: Vector2 = p.mapa["inicio"][1]

	# (a) andar x dash, mesmo tempo (0,4 s)
	l.position = base
	l.velocity = Vector2.ZERO
	for f in 30:
		await physics_frame
	var x0: float = l.position.x
	c.eixo = 1.0
	for f in 24:
		await physics_frame
	var andou: float = l.position.x - x0
	c.eixo = 0.0
	l._dash_cd = 0.0
	for f in 30:
		await physics_frame
	l.velocity = Vector2.ZERO
	x0 = l.position.x
	c.eixo = 1.0
	c.dash_apertou = true
	await physics_frame
	c.dash_apertou = false
	for f in 23:
		await physics_frame
	var dashou: float = l.position.x - x0
	c.eixo = 0.0
	if dashou < andou * 1.5:
		_falha("dash deslocou %.1f px, andar %.1f px (esperado bem mais)" % [dashou, andou])

	# (b) recarga: segundo dash logo depois não acontece; depois de 1,2 s acontece
	for f in 30:
		await physics_frame
	var posicoes := []
	var comeca := func() -> bool:
		c.dash_apertou = true
		c.dash_dir = 1.0
		return true
	l._dash_cd = 0.0
	comeca.call()
	await physics_frame
	c.dash_apertou = false
	for f in 15:  # a arrancada acaba (0,15 s)
		await physics_frame
	if l._dash_t > 0.0:
		_falha("a arrancada não terminou depois de DASH_DURACAO")
	comeca.call()
	await physics_frame
	c.dash_apertou = false
	if l._dash_t > 0.0:
		_falha("segundo dash saiu antes da recarga")
	for f in 60 * 12 / 10:  # passa de 1,2 s no total
		await physics_frame
	comeca.call()
	await physics_frame
	c.dash_apertou = false
	if l._dash_t <= 0.0:
		_falha("dash não saiu depois da recarga")
	c.dash_dir = 0.0

	# (c) no ar só um dash até tocar o chão
	for f in 60:
		await physics_frame
	l.position = base + Vector2(0, -40)
	l.velocity = Vector2.ZERO
	l._dash_cd = 0.0
	l._dash_ar_usado = false
	await physics_frame
	if l.is_on_floor():
		_falha("teste do dash no ar: o lutador estava no chão")
	c.dash_apertou = true
	await physics_frame
	c.dash_apertou = false
	if l._dash_t <= 0.0:
		_falha("o primeiro dash no ar não saiu")
	l._dash_t = 0.0
	l._dash_cd = 0.0
	l.position.y = minf(l.position.y, base.y - 40)
	l.velocity = Vector2.ZERO
	c.dash_apertou = true
	await physics_frame
	c.dash_apertou = false
	if l._dash_t > 0.0 and not l.is_on_floor():
		_falha("saiu um segundo dash no ar sem tocar o chão")
	l._dash_t = 0.0
	l.velocity = Vector2.ZERO
	for f in 90:
		await physics_frame
	if not l.is_on_floor():
		_falha("o lutador não pousou no teste do dash")
	l._dash_cd = 0.0
	c.dash_apertou = true
	await physics_frame
	c.dash_apertou = false
	if l._dash_t <= 0.0:
		_falha("o dash não recarregou ao tocar o chão")
	print("Dash: andou %.1f px, dashou %.1f px: ok" % [andou, dashou])
	main.queue_free()
	await process_frame


class ControleTeste extends Controle:
	## Controle manual para os testes: os campos são preenchidos pelo teste.
	func atualizar(_l, _delta: float) -> void:
		pass


func _testar_dash_rede() -> void:
	## ControleRede: um dash por contador; estado antigo (4 elementos) não quebra.
	var c := ControleRede.new()
	c.receber([0.0, 0, false, 0, 0, 0.0])
	c.atualizar(null, 0.016)
	if c.dash_apertou:
		_falha("ControleRede: dash sem contador subir")
	c.receber([0.5, 0, false, 0, 1, -1.0])
	c.atualizar(null, 0.016)
	if not c.dash_apertou or c.dash_dir != -1.0:
		_falha("ControleRede: dash do contador não chegou (apertou=%s, dir=%s)" % [c.dash_apertou, c.dash_dir])
	c.atualizar(null, 0.016)
	if c.dash_apertou:
		_falha("ControleRede: o mesmo dash saiu duas vezes")
	c.receber([0.5, 0, false, 0, 1, -1.0])  # pacote repetido
	c.atualizar(null, 0.016)
	if c.dash_apertou:
		_falha("ControleRede: pacote repetido gerou dash")
	c.receber([0.0, 0, false, 0, 3, 1.0])   # perdeu um pacote: conta como um apertão só
	c.atualizar(null, 0.016)
	if not c.dash_apertou or c.dash_dir != 1.0:
		_falha("ControleRede: contador que pulou não gerou dash")
	var antigo := ControleRede.new()
	antigo.receber([1.0, 2, true, 0])
	antigo.atualizar(null, 0.016)
	if antigo.dash_apertou or antigo.eixo != 1.0 or not antigo.pulo_apertou:
		_falha("ControleRede: estado de 4 elementos quebrou")
	print("ControleRede (dash): ok")


func _botao_joy(dev: int, botao: JoyButton, apertado := true) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.device = dev
	ev.button_index = botao
	ev.pressed = apertado
	return ev


func _testar_mapeamento_controle() -> void:
	## Controle: A pula, B dash, LB/RB melhorias (X/Y livres); último dispositivo usado.
	var casos := [
		[0, JOY_BUTTON_A, "p1_pular", true], [0, JOY_BUTTON_B, "p1_dash", true],
		[0, JOY_BUTTON_LEFT_SHOULDER, "p1_opcao1", true], [0, JOY_BUTTON_RIGHT_SHOULDER, "p1_opcao2", true],
		[0, JOY_BUTTON_LEFT_SHOULDER, "p1_dash", false], [0, JOY_BUTTON_RIGHT_SHOULDER, "p1_dash", false],
		[0, JOY_BUTTON_X, "p1_opcao1", false], [0, JOY_BUTTON_Y, "p1_opcao2", false],
		[0, JOY_BUTTON_X, "p1_opcao2", false], [0, JOY_BUTTON_Y, "p1_opcao1", false],
		[1, JOY_BUTTON_B, "p2_dash", true], [1, JOY_BUTTON_A, "p2_pular", true],
		[1, JOY_BUTTON_LEFT_SHOULDER, "p2_opcao1", true], [1, JOY_BUTTON_RIGHT_SHOULDER, "p2_opcao2", true],
		[1, JOY_BUTTON_B, "p1_dash", false], [0, JOY_BUTTON_B, "p2_dash", false],
		[0, JOY_BUTTON_A, "menu_ok", true], [0, JOY_BUTTON_B, "menu_voltar", true],
	]
	for c in casos:
		var ok := InputMap.event_is_action(_botao_joy(c[0], c[1]), c[2])
		if ok != c[3]:
			_falha("controle: dispositivo %d botão %d ação %s (esperava %s)" % [c[0], c[1], c[2], c[3]])
	var jogo = root.get_node("Jogo")
	jogo.usando_controle = false
	jogo._input(_botao_joy(0, JOY_BUTTON_A))
	if not jogo.usando_controle:
		_falha("usando_controle não ligou com botão do controle")
	var tecla := InputEventKey.new()
	tecla.keycode = KEY_A
	tecla.pressed = true
	jogo._input(tecla)
	if jogo.usando_controle:
		_falha("usando_controle não desligou com tecla")
	var eixo := InputEventJoypadMotion.new()
	eixo.axis = JOY_AXIS_LEFT_X
	eixo.axis_value = 0.2
	jogo._input(eixo)
	if jogo.usando_controle:
		_falha("usando_controle ligou com movimento pequeno do analógico")
	eixo.axis_value = 0.9
	jogo._input(eixo)
	if not jogo.usando_controle:
		_falha("usando_controle não ligou com analógico")
	jogo._input(InputEventScreenTouch.new())
	if jogo.usando_controle:
		_falha("usando_controle não desligou com toque")
	jogo.usando_controle = false
	print("Controle (mapeamento e último dispositivo): ok")


func _evento_eixo(dev: int, eixo: JoyAxis, valor: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.device = dev
	ev.axis = eixo
	ev.axis_value = valor
	return ev


func _testar_controle_mapa() -> void:
	## Índices crus: no navegador (W3C) e no PC (Godot). Os atalhos são refeitos a cada troca.
	var jogo = root.get_node("Jogo")
	var web_antes: bool = MapaControle.web
	# (a) navegador: índices W3C
	MapaControle.web = true
	jogo._criar_controles()
	var w3c := [
		[0, 4, "p1_opcao1", true], [0, 5, "p1_opcao2", true], [1, 4, "p2_opcao1", true], [1, 5, "p2_opcao2", true],
		[0, 0, "p1_pular", true], [0, 0, "menu_ok", true], [1, 0, "p2_pular", true],
		[0, 1, "p1_dash", true], [0, 1, "menu_voltar", true], [1, 1, "p2_dash", true],
		[0, 9, "pausar", true], [0, 8, "pausar", true], [1, 9, "pausar", true],
		[0, 12, "menu_cima", true], [0, 13, "menu_baixo", true], [0, 13, "p1_descer", true],
		[0, 14, "p1_esquerda", true], [0, 15, "p1_direita", true], [1, 14, "p2_esquerda", true], [1, 15, "p2_direita", true],
		[1, 13, "p2_descer", true], [1, 13, "p1_descer", false], [1, 1, "p1_dash", false],
		# gatilhos W3C não fazem nada (principalmente não pausam)
		[0, 6, "pausar", false], [0, 7, "pausar", false], [0, 6, "p1_opcao1", false], [0, 7, "p1_opcao2", false],
		[0, 6, "p1_pular", false], [0, 7, "p1_dash", false], [0, 6, "menu_ok", false], [0, 7, "menu_voltar", false],
		# os índices do Godot não valem no navegador (6 e 7 seriam Start/gatilho; 11 e 12 direcional)
		[0, 10, "p1_opcao2", false], [0, 11, "menu_cima", false], [0, 12, "menu_baixo", false],
		[0, 3, "p1_opcao1", false], [0, 2, "p1_opcao2", false],
	]
	for c in w3c:
		if InputMap.event_is_action(_botao_joy(c[0], c[1]), c[2]) != c[3]:
			_falha("navegador: dispositivo %d botão cru %d ação %s (esperava %s)" % [c[0], c[1], c[2], c[3]])
	# traduzir o índice de volta (tela de teste)
	var teste = load("res://scripts/teste_controle.gd")
	if teste.logico(4) != JOY_BUTTON_LEFT_SHOULDER or teste.logico(9) != JOY_BUTTON_START or teste.logico(12) != JOY_BUTTON_DPAD_UP or teste.logico(6) != -1:
		_falha("teste_controle: tradução W3C -> botão lógico errada")
	if not teste.nome_entrada(_botao_joy(0, 4)).begins_with("LB (botão 4)"):
		_falha("teste_controle: nome no navegador: %s" % teste.nome_entrada(_botao_joy(0, 4)))
	# (b) PC: índices do Godot de sempre
	MapaControle.web = false
	jogo._criar_controles()
	var pc := [
		[0, JOY_BUTTON_LEFT_SHOULDER, "p1_opcao1", true], [0, JOY_BUTTON_RIGHT_SHOULDER, "p1_opcao2", true],
		[0, JOY_BUTTON_START, "pausar", true], [0, JOY_BUTTON_BACK, "pausar", true],
		[0, JOY_BUTTON_DPAD_UP, "menu_cima", true], [0, JOY_BUTTON_DPAD_DOWN, "menu_baixo", true],
		[0, JOY_BUTTON_DPAD_DOWN, "p1_descer", true], [1, JOY_BUTTON_B, "p2_dash", true],
		[0, JOY_BUTTON_DPAD_LEFT, "p1_esquerda", true], [0, JOY_BUTTON_DPAD_RIGHT, "p1_direita", true],
		[0, 8, "pausar", false], [0, 12, "menu_cima", false],  # 8 = Guide e 12 = direcional baixo no PC
		[0, JOY_BUTTON_GUIDE, "pausar", false],
	]
	for c in pc:
		if InputMap.event_is_action(_botao_joy(c[0], c[1]), c[2]) != c[3]:
			_falha("PC: dispositivo %d botão %d ação %s (esperava %s)" % [c[0], c[1], c[2], c[3]])
	# Gatilhos (eixos 4 e 5) e analógico: sem função de menu/pausa; o analógico anda no jogo (zona morta 0,2)
	if InputMap.event_is_action(_evento_eixo(0, JOY_AXIS_TRIGGER_LEFT, 1.0), "pausar"):
		_falha("gatilho (eixo) não deveria pausar")
	if not InputMap.event_is_action(_evento_eixo(0, JOY_AXIS_LEFT_X, 0.9), "p1_direita"):
		_falha("analógico X não anda no jogo")
	if not is_equal_approx(InputMap.action_get_deadzone("p1_direita"), 0.2) or not is_equal_approx(InputMap.action_get_deadzone("p2_descer"), 0.2):
		_falha("zona morta do movimento deveria ser 0,2")
	for a in ["menu_cima", "menu_baixo"]:
		if InputMap.event_is_action(_evento_eixo(0, JOY_AXIS_LEFT_Y, -1.0), a) or InputMap.event_is_action(_evento_eixo(0, JOY_AXIS_LEFT_Y, 1.0), a):
			_falha("analógico não pode estar no InputMap de %s (é tratado pelo Jogo)" % a)
	MapaControle.web = web_antes
	jogo._criar_controles()
	print("Controle (índices W3C no navegador e do Godot no PC): ok")


func _testar_controle_menus() -> void:
	## Pausa (Start/Back/Esc/P), analógico nos menus e repetição ao segurar.
	var jogo = root.get_node("Jogo")
	var web_antes: bool = MapaControle.web
	MapaControle.web = true
	jogo._criar_controles()
	# (a) pausa: Start e Back (W3C 9 e 8) emitem uma vez; gatilhos (6 e 7) nunca
	var pedidos := [0]
	var conta := func() -> void: pedidos[0] += 1
	jogo.pausa_pedida.connect(conta)
	for c in [[9, 1], [8, 1], [6, 0], [7, 0], [0, 0], [4, 0], [12, 0]]:
		pedidos[0] = 0
		jogo._input(_botao_joy(0, c[0]))
		if pedidos[0] != c[1]:
			_falha("pausa: botão cru %d emitiu %d vez(es) (esperava %d)" % [c[0], pedidos[0], c[1]])
	pedidos[0] = 0
	jogo._input(_botao_joy(0, 9, false))
	if pedidos[0] != 0:
		_falha("pausa: soltar o Start não deveria pausar")
	var tecla := InputEventKey.new()
	tecla.physical_keycode = KEY_P
	tecla.pressed = true
	jogo._input(tecla)
	tecla = InputEventKey.new()
	tecla.physical_keycode = KEY_ESCAPE
	tecla.pressed = true
	jogo._input(tecla)
	tecla.echo = true  # repetição de tecla não conta
	jogo._input(tecla)
	if pedidos[0] != 2:
		_falha("pausa: P e Esc deveriam emitir 2 vezes (emitiu %d)" % pedidos[0])
	jogo.pausa_pedida.disconnect(conta)
	MapaControle.web = web_antes
	jogo._criar_controles()
	# (b) analógico esquerdo nos menus: passo único acima de 0,5, solta abaixo de 0,3, repete 0,4 / 0,15
	jogo.partida = null
	jogo._eixos = {JOY_AXIS_LEFT_X: 0.0, JOY_AXIS_LEFT_Y: 0.0}
	jogo._direcao = Vector2i.ZERO
	jogo._pulso.clear()
	var p0: int = jogo.passos_analogico
	jogo._input(_evento_eixo(0, JOY_AXIS_LEFT_Y, 0.45))
	if jogo.passos_analogico != p0:
		_falha("analógico: 0,45 está na zona morta e não deveria dar passo")
	jogo._input(_evento_eixo(0, JOY_AXIS_LEFT_Y, 0.9))
	if jogo.passos_analogico != p0 + 1 or not jogo.menu_pulso("menu_baixo") or jogo.menu_pulso("menu_cima"):
		_falha("analógico: empurrar para baixo deveria dar 1 passo em menu_baixo")
	jogo._input(_evento_eixo(0, JOY_AXIS_LEFT_Y, 1.0))
	jogo._input(_evento_eixo(0, JOY_AXIS_LEFT_Y, 0.35))  # ainda acima de 0,3: segue empurrado
	if jogo.passos_analogico != p0 + 1:
		_falha("analógico: mexer sem soltar não deveria dar passo novo")
	jogo._pulso.clear()
	jogo._atualizar_analogico(0.39)
	if jogo.passos_analogico != p0 + 1:
		_falha("analógico: repetiu antes de 0,4 s")
	jogo._atualizar_analogico(0.02)
	if jogo.passos_analogico != p0 + 2 or not jogo.menu_pulso("menu_baixo"):
		_falha("analógico: deveria repetir aos 0,4 s")
	jogo._pulso.clear()
	jogo._atualizar_analogico(0.12)
	if jogo.passos_analogico != p0 + 2:
		_falha("analógico: repetiu antes de 0,15 s")
	jogo._atualizar_analogico(0.03)
	if jogo.passos_analogico != p0 + 3:
		_falha("analógico: deveria repetir a cada 0,15 s")
	jogo._input(_evento_eixo(0, JOY_AXIS_LEFT_Y, 0.25))  # soltou (abaixo de 0,3)
	jogo._atualizar_analogico(1.0)
	if jogo.passos_analogico != p0 + 3:
		_falha("analógico: continuou repetindo depois de soltar")
	jogo._input(_evento_eixo(0, JOY_AXIS_LEFT_Y, -0.8))
	if jogo.passos_analogico != p0 + 4 or not jogo.menu_pulso("menu_cima"):
		_falha("analógico: empurrar para cima deveria dar 1 passo em menu_cima")
	jogo._input(_evento_eixo(0, JOY_AXIS_LEFT_Y, 0.0))
	# Na partida sem pausa o analógico anda e não navega; pausada, navega
	var falsa := Node.new()
	var gd := GDScript.new()
	gd.source_code = "extends Node\nvar pausado := false\n"
	gd.reload()
	falsa.set_script(gd)
	root.add_child(falsa)
	jogo.partida = falsa
	var p1: int = jogo.passos_analogico
	jogo._input(_evento_eixo(0, JOY_AXIS_LEFT_Y, 0.9))
	if jogo.passos_analogico != p1:
		_falha("analógico: não deveria navegar com a partida rodando")
	jogo._input(_evento_eixo(0, JOY_AXIS_LEFT_Y, 0.0))
	falsa.pausado = true
	jogo._input(_evento_eixo(0, JOY_AXIS_LEFT_Y, 0.9))
	if jogo.passos_analogico != p1 + 1:
		_falha("analógico: deveria navegar com a partida pausada")
	jogo._input(_evento_eixo(0, JOY_AXIS_LEFT_Y, 0.0))
	jogo.partida = null
	falsa.queue_free()
	# (c) repetição ao segurar: 1 pulso ao apertar, nada até 0,4 s, depois a cada 0,15 s
	Input.action_press("menu_baixo")
	var pulsos: Array[float] = []
	var t := 0.0
	for i in 70:
		await process_frame
		t += 1.0 / 60.0
		if jogo.menu_pulso("menu_baixo"):
			pulsos.append(t)
	Input.action_release("menu_baixo")
	await process_frame
	if jogo.menu_pulso("menu_baixo"):
		_falha("repetição: continuou disparando depois de soltar")
	if pulsos.size() < 5 or pulsos.size() > 8:
		_falha("repetição: %d pulsos em ~1,1 s (esperava 5 a 8)" % pulsos.size())
	elif pulsos[1] - pulsos[0] < 0.35 or pulsos[2] - pulsos[1] > 0.2:
		_falha("repetição: intervalos errados %s" % [pulsos])
	# Tela de teste: nomes amigáveis e o que o jogo entende
	var teste = load("res://scripts/teste_controle.gd")
	var lb := _botao_joy(0, JOY_BUTTON_LEFT_SHOULDER)
	if not teste.nome_entrada(lb).begins_with("LB (botão") or not teste.entendimento(lb).contains("escolher melhoria 1"):
		_falha("teste_controle: LB → %s / %s" % [teste.nome_entrada(lb), teste.entendimento(lb)])
	print("Controle (pausa, analógico e repetição nos menus): ok")


func _testar_pausa_partida() -> void:
	## A pausa abre e fecha por Jogo.pausa_pedida, uma vez por aperto (sem abrir e fechar junto).
	var jogo = root.get_node("Jogo")
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._nova_partida({"semente": 77, "tempo": 180.0, "bots": {1: -1, 2: -1}})
	await process_frame
	var partida = main._atual
	if jogo.partida != partida:
		_falha("pausa: a partida não se registrou no Jogo")
	jogo.pausa_pedida.emit()
	await process_frame
	if not partida.pausado or partida._painel_pausa == null:
		_falha("pausa: o pedido não abriu a pausa")
	for i in 4:
		await process_frame
	if not jogo.em_menu():
		_falha("pausa: com a partida pausada o analógico deveria navegar nos menus")
	# Esc: chega como pausa_pedida e como menu_voltar no mesmo quadro; fecha uma vez só
	Input.action_press("menu_voltar")
	jogo.pausa_pedida.emit()
	await process_frame
	Input.action_release("menu_voltar")
	await process_frame
	if partida.pausado or partida._painel_pausa != null:
		_falha("pausa: o pedido não fechou a pausa")
	for i in 3:
		await process_frame
	if partida.pausado:
		_falha("pausa: reabriu sozinha no mesmo aperto")
	if jogo.em_menu():
		_falha("pausa: com a partida rodando o analógico não deveria navegar")
	main.queue_free()
	await process_frame
	if jogo.partida != null:
		_falha("pausa: o Jogo ainda aponta para a partida destruída")
	print("Pausa na partida (abrir e fechar por Start/Esc): ok")


func _testar_cartas_layout() -> void:
	## Um humano local: cartas lado a lado (mesmo y); dois humanos: empilhadas (mesmo x).
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for humanos in [1, 2]:
		main._nova_partida({"semente": 77, "tempo": 180.0, "bots": {1: -1, 2: -1 if humanos == 2 else 1}})
		await process_frame
		var hud = main._atual.hud
		for n in [1, 2]:
			var r: Array = hud.rects_cartas(n)
			if humanos == 1:
				if n == 1 and (r[0].position.x >= r[1].position.x or not is_equal_approx(r[0].position.y, r[1].position.y)):
					_falha("cartas (1 humano): não ficaram lado a lado na mesma altura: %s" % [r])
				if n == 1 and (r[0].intersects(r[1]) or r[0].position.x > 10.0 or r[1].end.x < hud.size.x - 10.0):
					_falha("cartas (1 humano): não ficaram uma em cada lateral: %s" % [r])
			else:
				if not is_equal_approx(r[0].position.x, r[1].position.x) or r[0].position.y >= r[1].position.y:
					_falha("cartas (2 humanos, P%d): não ficaram empilhadas: %s" % [n, r])
		if humanos == 2 and hud.rects_cartas(1)[0].position.x >= hud.rects_cartas(2)[0].position.x:
			_falha("cartas (2 humanos): P1 deveria ficar à esquerda de P2")
	main.queue_free()
	await process_frame
	print("Cartas (layout 1 e 2 humanos): ok")


# ------------------------------------------------------------------ Torre da Tormenta

func _perto(a: float, b: float, tol := 0.01) -> bool:
	return absf(a - b) <= tol


func _testar_bot_muito_dificil() -> void:
	var P: Dictionary = _bot_script.PARAMS
	var d = _bot_script.Dificuldade
	if P.size() != 4 or _bot_script.NOMES.size() != 4:
		_falha("bot: esperava 4 dificuldades em PARAMS e NOMES")
	var mdif: Dictionary = P[d.MUITO_DIFICIL]
	if not (_perto(mdif["reacao"], 0.05) and mdif["erro"] == 0.0 and mdif["portas"] and mdif["foge"] and mdif["melhor_melhoria"] == 1.0):
		_falha("bot: parâmetros do MUITO_DIFICIL errados: %s" % [mdif])
	# As três antigas continuam iguais
	if not (_perto(P[d.FACIL]["reacao"], 0.5) and _perto(P[d.FACIL]["erro"], 0.2) and not P[d.FACIL]["portas"] \
			and _perto(P[d.NORMAL]["reacao"], 0.25) and _perto(P[d.NORMAL]["erro"], 0.07) and _perto(P[d.NORMAL]["melhor_melhoria"], 0.7) \
			and _perto(P[d.DIFICIL]["reacao"], 0.1) and _perto(P[d.DIFICIL]["erro"], 0.02) and P[d.DIFICIL]["melhor_melhoria"] == 1.0):
		_falha("bot: as dificuldades antigas foram alteradas")
	if d.MUITO_DIFICIL != 3 or d.DIFICIL != 2 or d.FACIL != 0:
		_falha("bot: valores do enum mudaram")
	print("Bot (MUITO_DIFICIL e as três antigas): ok")


func _evento_clique(pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	return e


func _testar_menu_navegacao() -> void:
	## Menu: SINGLE PLAYER > (TORRE > personagem > dificuldade | CONTRA A CPU > dificuldade),
	## DUELO > (LOCAL | REDE), OPÇÕES; "voltar" sobe um nível; MUITO DIFÍCIL trancado.
	var jogo = root.get_node("Jogo")
	var desbloqueadas_antes: Array[String] = jogo.torre_desbloqueada.duplicate()
	jogo.torre_desbloqueada.clear()
	var menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var eventos: Array = []
	menu.jogar.connect(func() -> void: eventos.append(["jogar", jogo.solo, jogo.dificuldade]))
	menu.jogar_rede.connect(func() -> void: eventos.append(["rede"]))
	menu.jogar_torre.connect(func(c: int, d: int) -> void: eventos.append(["torre", c, d]))
	if menu.PRINCIPAL != ["SINGLE PLAYER", "DUELO", "OPÇÕES"] or menu.SINGLE != ["TORRE DA TORMENTA", "CONTRA A CPU"] \
			or menu.DUELO != ["LOCAL", "REDE"] or menu.DIFICULDADES.size() != 3 or menu.DIFICULDADES_TORRE != ["NORMAL", "DIFÍCIL", "MUITO DIFÍCIL"]:
		_falha("menu: listas de opções erradas")
	if menu._tela != "principal":
		_falha("menu: deveria abrir na tela principal")
	# SINGLE PLAYER > CONTRA A CPU > dificuldade
	menu._sel = 0
	menu._confirmar()
	if menu._tela != "single":
		_falha("menu: SINGLE PLAYER não abriu a tela single (%s)" % menu._tela)
	menu._sel = 1
	menu._confirmar()
	if menu._tela != "dificuldade" or not jogo.solo:
		_falha("menu: CONTRA A CPU deveria abrir a dificuldade")
	menu._sel = 2
	menu._confirmar()
	if eventos != [["jogar", true, 2]]:
		_falha("menu: CPU difícil → %s" % [eventos])
	menu._voltar()
	if menu._tela != "single" or menu._sel != 1:
		_falha("menu: voltar da dificuldade deveria ir para single/CONTRA A CPU (%s, %d)" % [menu._tela, menu._sel])
	jogo.dificuldade = 1
	menu._voltar()
	if menu._tela != "principal" or menu._sel != 0:
		_falha("menu: voltar de single deveria ir para a principal")
	menu._voltar()
	if menu._tela != "principal":
		_falha("menu: voltar na principal não deveria sair dela")
	# DUELO
	eventos.clear()
	menu._sel = 1
	menu._confirmar()
	if menu._tela != "duelo":
		_falha("menu: DUELO não abriu a tela duelo")
	menu._sel = 0
	menu._confirmar()
	if eventos.size() != 1 or eventos[0][0] != "jogar" or eventos[0][1]:
		_falha("menu: DUELO > LOCAL deveria emitir jogar com solo = false (%s)" % [eventos])
	menu._sel = 1
	menu._confirmar()
	if eventos.size() != 2 or eventos[1] != ["rede"]:
		_falha("menu: DUELO > REDE deveria emitir jogar_rede (%s)" % [eventos])
	menu._voltar()
	if menu._tela != "principal" or menu._sel != 1:
		_falha("menu: voltar de duelo deveria ir para a principal/DUELO")
	# OPÇÕES
	menu._sel = 2
	menu._confirmar()
	if menu._painel == null:
		_falha("menu: OPÇÕES não abriu o painel")
	else:
		menu._painel.queue_free()
		menu._painel = null
	# TORRE > personagem > dificuldade (MUITO DIFÍCIL trancado até vencer com o personagem)
	eventos.clear()
	menu._mudar_tela("principal", 0)
	menu._confirmar()
	menu._sel = 0
	menu._confirmar()
	if menu._tela != "personagem" or menu._opcoes() != ["ARQUEIRO", "ORC", "MAGO", "REI"]:
		_falha("menu: TORRE DA TORMENTA deveria abrir a escolha de personagem (%s %s)" % [menu._tela, menu._opcoes()])
	menu._sel = 2  # mago
	menu._confirmar()
	if menu._tela != "torre_dif" or menu._personagem != 2:
		_falha("menu: personagem escolhido não levou à dificuldade da torre")
	menu._sel = 2
	menu._confirmar()
	if not eventos.is_empty() or menu._tela != "torre_dif" or not menu._bloqueada(2) or menu._bloqueada(1):
		_falha("menu: MUITO DIFÍCIL deveria estar trancado para o Mago (%s)" % [eventos])
	jogo.torre_desbloqueada.append("orc")  # outro personagem desbloqueado não vale para o Mago
	if not menu._bloqueada(2):
		_falha("menu: o desbloqueio do Orc não deveria valer para o Mago")
	jogo.torre_desbloqueada.append("mago")
	menu._confirmar()
	menu._sel = 0
	menu._confirmar()
	menu._sel = 1
	menu._confirmar()
	if eventos != [["torre", 2, 2], ["torre", 2, 0], ["torre", 2, 1]]:
		_falha("menu: torre emitiu %s" % [eventos])
	menu._voltar()
	if menu._tela != "personagem" or menu._sel != 2:
		_falha("menu: voltar da dificuldade da torre deveria ir para o personagem (%s, %d)" % [menu._tela, menu._sel])
	# Clique/toque: opção e botão VOLTAR
	menu._mudar_tela("principal", 0)
	var desl: Vector2 = menu._deslocamento()
	menu._gui_input(_evento_clique(menu._rect_opcao(1).get_center() + desl))
	if menu._tela != "duelo":
		_falha("menu: clique em DUELO não abriu a tela")
	menu._gui_input(_evento_clique(menu._rect_voltar().get_center() + desl))
	if menu._tela != "principal":
		_falha("menu: clique em VOLTAR não subiu um nível")
	menu._mudar_tela("personagem", 0)
	menu._gui_input(_evento_clique(Vector2(menu._x_classe(menu.size.x / 2.0, 3), 100.0) + desl))
	if menu._tela != "torre_dif" or menu._personagem != 3:
		_falha("menu: clique no personagem (Rei) não o escolheu")
	# Esc/B (menu_voltar) sobe um nível
	Input.action_press("menu_voltar")
	await process_frame
	Input.action_release("menu_voltar")
	if menu._tela != "personagem":
		_falha("menu: menu_voltar não subiu um nível (%s)" % menu._tela)
	menu.queue_free()
	jogo.torre_desbloqueada = desbloqueadas_antes
	await process_frame
	print("Menu (single, duelo, torre, voltar, cadeado): ok")


func _esperar_andar(main, andar: int) -> Node:
	## Espera o main montar a partida do andar (as trocas de tela são adiadas).
	for i in 900:
		await process_frame
		var a = main._atual
		if a != null and a.get("torre") != null and not a.torre.is_empty() and a.torre["andar"] == andar:
			await process_frame
			return a
	_falha("a torre não chegou ao andar %d" % andar)
	return null


func _esperar_tela_fim(main) -> Node:
	for i in 900:
		await process_frame
		if main._atual != null and main._atual.has_signal("de_novo"):
			return main._atual
	_falha("a tela final da torre não apareceu")
	return null


func _testar_torre() -> void:
	## Campanha completa pelo main com vitórias forçadas (oponente com vida 0).
	var jogo = root.get_node("Jogo")
	var desbloqueadas_antes: Array[String] = jogo.torre_desbloqueada.duplicate()
	jogo.arquivo_opcoes = "user://opcoes_teste_torre.cfg"
	jogo.torre_desbloqueada.clear()
	# (a) ordem dos adversários
	for semente in 50:
		var t = _torre_script.new()
		t.comecar(1, 0, semente)
		var sub: Array = t.ordem.slice(1, 5)
		var fin: Array = t.ordem.slice(5, 9)
		sub.sort()
		fin.sort()
		if t.ordem.size() != 9 or t.ordem[0] != -1 or sub != [0, 1, 2, 3] or fin != [0, 1, 2, 3]:
			_falha("torre: ordem inválida %s" % [t.ordem])
		t.free()
	var ordens := {}
	for semente in 30:
		var t = _torre_script.new()
		t.comecar(0, 0, semente)
		ordens[str(t.ordem)] = true
		t.free()
	if ordens.size() < 5:
		_falha("torre: a ordem dos adversários não varia (%d ordens em 30 sementes)" % ordens.size())

	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._iniciar_torre(1, 0)  # Orc, NORMAL
	var torre = main._torre
	var p = await _esperar_andar(main, 1)
	if p == null:
		main.queue_free()
		return
	var classe_jogador := 1
	var nivel_jogador := [1, 2, 3, 4, 5, 6, 6, 6, 6]
	var nivel_cpu := [1, 3, 4, 5, 6, 7, 7, 7, 7]
	var vida_antes := [0.2, 0.4, 0.5, 0.65, 0.1, 0.6, 0.35, 0.8, 0.5]
	var vida_esperada := [0.0, 0.5, 0.7, 0.8, 0.95, 0.6, 0.6, 0.35, 0.8]  # no começo de cada andar (índice 0 = andar 1, não usado)  # andar 6: só os 50% da etapa final (não soma com os 30%)
	var classes_cpu: Array[int] = []
	var dano_somado := 0.0
	for a in range(1, 10):
		var eu = p.jogadores[1]
		var cpu = p.jogadores[2]
		var rotulo := "torre andar %d" % a
		if p.torre["andar"] != a or p.torre["final"] != (a > 5):
			_falha("%s: dados do andar errados %s" % [rotulo, p.torre])
		# níveis, classes, vida, melhorias
		if eu.nivel != nivel_jogador[a - 1]:
			_falha("%s: jogador nível %d (esperava %d)" % [rotulo, eu.nivel, nivel_jogador[a - 1]])
		if cpu.nivel != nivel_cpu[a - 1]:
			_falha("%s: CPU nível %d (esperava %d)" % [rotulo, cpu.nivel, nivel_cpu[a - 1]])
		if a >= 2 and cpu.nivel != eu.nivel + 1:
			_falha("%s: CPU deveria ter o nível do jogador + 1" % rotulo)
		if a == 1:
			if not eu.eh_recruta or not cpu.eh_recruta or eu.indice_classe() != -1 or cpu.indice_classe() != -1:
				_falha("%s: o andar 1 é Recruta x Recruta" % rotulo)
		else:
			if eu.eh_recruta or eu.indice_classe() != classe_jogador:
				_falha("%s: o jogador deveria ser o personagem escolhido (índice %d)" % [rotulo, eu.indice_classe()])
			if cpu.eh_recruta or cpu.indice_classe() != torre.ordem[a - 1]:
				_falha("%s: CPU com a classe errada" % rotulo)
			classes_cpu.append(cpu.indice_classe())
			if cpu.historico.size() != maxi(0, cpu.nivel - 2):
				_falha("%s: CPU com %d melhorias (nível %d)" % [rotulo, cpu.historico.size(), cpu.nivel])
			if not _perto(float(eu.vida) / eu.vida_max, vida_esperada[a - 1], 0.015):
				_falha("%s: vida do jogador %.3f no começo (esperava %.3f)" % [rotulo, eu.vida / eu.vida_max, vida_esperada[a - 1]])
		if not _perto(cpu.vida, cpu.vida_max):
			_falha("%s: a CPU deveria começar com a vida cheia" % rotulo)
		if eu.escolhas.size() != (1 if (a >= 3 and a <= 6) else 0):
			_falha("%s: %d escolhas de melhoria pendentes" % [rotulo, eu.escolhas.size()])
		if cpu.controle.get_script() != _bot_script or cpu.controle.dificuldade != _bot_script.Dificuldade.NORMAL:
			_falha("%s: CPU deveria ser bot NORMAL" % rotulo)
		# regras da partida
		if p.tempo_restante != 90.0 or p.monstros_ligados or p.itens_ligados or p.morte_subita_ligada or p.regen or p.xp_ligado:
			_falha("%s: flags da partida erradas" % rotulo)
		if p.get_tree().get_nodes_in_group("alvo").size() != 2:
			_falha("%s: deveria haver só os 2 lutadores (sem monstros)" % rotulo)
		# apresentação do andar e escolha de melhoria antes da contagem
		if a == 3:
			for i in 30:
				await process_frame
			if p.contagem != 3.0 or not p.espera_inicio():
				_falha("%s: a contagem não deveria começar antes da escolha da melhoria" % rotulo)
			p.escolher(1, 0)
			if not eu.escolhas.is_empty() or eu.historico.size() != 1:
				_falha("%s: a escolha da melhoria não foi aplicada" % rotulo)
			for i in 150:
				await process_frame
			if p.contagem >= 3.0:
				_falha("%s: a contagem deveria ter começado depois da apresentação" % rotulo)
		elif a == 2:
			for i in 60:
				await process_frame
			if p.contagem != 3.0 or p.intro_t <= 0.0:
				_falha("%s: a apresentação do andar deveria segurar a contagem" % rotulo)
		elif a >= 4 and a <= 6:
			p.escolher(1, 1)
		# estatísticas: um golpe de 10 de dano base na CPU
		var antes: float = cpu.vida
		cpu.receber_dano(10.0, eu)
		var tirou: float = antes - cpu.vida
		if tirou <= 0.0 or not _perto(eu.dano_causado, tirou, 0.001) or not _perto(cpu.dano_recebido, tirou, 0.001) or eu.maior_golpe < tirou - 0.001:
			_falha("%s: estatísticas de dano erradas (tirou %.3f, causado %.3f)" % [rotulo, tirou, eu.dano_causado])
		dano_somado += tirou
		# o nível não sobe por XP (abater lacaios, por exemplo)
		var nivel_antes: int = eu.nivel
		eu.ganhar_xp(500)
		if eu.nivel != nivel_antes or eu.xp != 0:
			_falha("%s: XP não deveria contar na torre" % rotulo)
		eu.vida = eu.vida_max * vida_antes[a - 1]
		# vence o andar
		cpu.receber_dano(99999.0, eu)
		dano_somado += cpu.dano_recebido - tirou
		if a < 9:
			p = await _esperar_andar(main, a + 1)
		else:
			p = await _esperar_tela_fim(main)
		if p == null:
			main.queue_free()
			return
	var perm := classes_cpu.slice(0, 4)
	perm.sort()
	var perm2 := classes_cpu.slice(4, 8)
	perm2.sort()
	if perm != [0, 1, 2, 3] or perm2 != [0, 1, 2, 3]:
		_falha("torre: andares 2-5 e 6-9 deveriam ter as 4 classes cada (%s)" % [classes_cpu])
	# Campeão
	if torre.estado != "campeao" or torre.abates != 9 or torre.nivel_final != 6 or torre.melhorias_finais.size() != 4:
		_falha("torre: estado final errado (%s, abates %d, nível %d, melhorias %s)" % [torre.estado, torre.abates, torre.nivel_final, torre.melhorias_finais])
	if torre.dano_causado <= 0.0 or torre.dano_recebido != 0.0 or torre.tempo_total < 0.0 or torre.maior_golpe <= 0.0:
		_falha("torre: estatísticas finais erradas (causado %.1f, tempo %.1f)" % [torre.dano_causado, torre.tempo_total])
	if not torre.desbloqueou_agora or not jogo.torre_muito_dificil("orc") or jogo.torre_muito_dificil("arqueiro"):
		_falha("torre: vencer deveria desbloquear MUITO DIFÍCIL só para o Orc")
	var cfg := ConfigFile.new()
	if cfg.load(jogo.arquivo_opcoes) != OK or not cfg.get_value("torre", "muito_dificil_orc", false) or cfg.get_value("torre", "muito_dificil_mago", false):
		_falha("torre: o desbloqueio não foi salvo no arquivo")
	jogo._carregar_opcoes()
	if not jogo.torre_muito_dificil("orc") or jogo.torre_desbloqueada.size() != 1:
		_falha("torre: o desbloqueio não foi lido de volta (%s)" % [jogo.torre_desbloqueada])
	if main._atual.torre != torre:
		_falha("tela final: não recebeu a torre")
	if main._atual._linhas().size() != 6 or main._atual._rotulos() != ["JOGAR DE NOVO", "MENU"] or main._atual.formatar_tempo(125.4) != "2:05":
		_falha("tela final: linhas/rótulos do campeão errados")
	# Vencer de novo com o personagem já desbloqueado: sem o aviso
	main._atual.de_novo.emit()
	p = await _esperar_andar(main, 1)
	torre = main._torre
	if torre.andar != 1 or torre.personagem != 1 or torre.dificuldade != 0 or torre.estado != "andar" or torre.dano_causado != 0.0:
		_falha("torre: TENTAR DE NOVO deveria recomeçar do zero com o mesmo personagem e dificuldade")
	torre.andar = 9
	torre.jogador = {"classe": 1, "nivel": 6, "historico": [], "vida": 1.0}
	main._nova_partida(torre.config_andar())
	p = await _esperar_andar(main, 9)
	p.jogadores[2].receber_dano(99999.0, p.jogadores[1])
	var fim = await _esperar_tela_fim(main)
	if torre.estado != "campeao" or torre.desbloqueou_agora:
		_falha("torre: segunda vitória não deveria mostrar o desbloqueio de novo")
	# Derrota → game over → TENTAR DE NOVO / MENU
	fim.de_novo.emit()
	p = await _esperar_andar(main, 1)
	torre = main._torre
	torre.andar = 4
	torre.jogador = {"classe": 1, "nivel": 4, "historico": [], "vida": 1.0}
	main._nova_partida(torre.config_andar())
	p = await _esperar_andar(main, 4)
	p.jogadores[1].receber_dano(99999.0, p.jogadores[2])
	fim = await _esperar_tela_fim(main)
	if torre.estado != "game_over" or torre.andar_alcancado != 4 or torre.abates != 0:
		_falha("torre: derrota deveria levar ao game over no andar 4 (%s, %d)" % [torre.estado, torre.andar_alcancado])
	if fim._rotulos() != ["TENTAR DE NOVO", "MENU"]:
		_falha("tela final: o game over deveria oferecer TENTAR DE NOVO e MENU")
	fim.de_novo.emit()
	p = await _esperar_andar(main, 1)
	if main._torre == null or main._torre.andar != 1 or main._torre.personagem != 1:
		_falha("torre: depois do game over, TENTAR DE NOVO deveria recomeçar")
	# Pausa durante a luta funciona; voltar ao menu encerra a torre
	jogo.pausa_pedida.emit()
	await process_frame
	if not p.pausado:
		_falha("torre: a pausa não abriu")
	p.voltar.emit()
	for i in 4:
		await process_frame
	if main._torre != null or main._atual == null or not main._atual.has_signal("jogar_torre"):
		_falha("torre: voltar ao menu pela pausa deveria encerrar a torre")
	# Game over → MENU
	main._iniciar_torre(0, 1)
	p = await _esperar_andar(main, 1)
	var dif_cpu = p.jogadores[2].controle.dificuldade
	p.jogadores[1].receber_dano(99999.0, p.jogadores[2])
	fim = await _esperar_tela_fim(main)
	if main._torre.estado != "game_over" or dif_cpu != _bot_script.Dificuldade.DIFICIL:
		_falha("torre: derrota no andar 1 / dificuldade DIFÍCIL (%s)" % main._torre.estado)
	fim.menu.emit()
	for i in 4:
		await process_frame
	if main._torre != null or not main._atual.has_signal("jogar_torre"):
		_falha("torre: MENU do game over não voltou ao menu")
	# MUITO DIFÍCIL usa o bot MUITO_DIFICIL
	main._iniciar_torre(2, 2)
	p = await _esperar_andar(main, 1)
	if p.jogadores[2].controle.dificuldade != _bot_script.Dificuldade.MUITO_DIFICIL:
		_falha("torre: dificuldade 2 deveria usar o bot MUITO_DIFICIL")
	main.queue_free()
	await process_frame
	# Restaura o arquivo de opções do jogador
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://opcoes_teste_torre.cfg"))
	jogo.arquivo_opcoes = jogo.ARQUIVO_OPCOES
	jogo.torre_desbloqueada = desbloqueadas_antes
	print("Torre (9 andares, níveis, vida, melhorias, campeão, game over, desbloqueio): ok")


func _testar_torre_fim_do_tempo() -> void:
	## Sem Morte Súbita: no fim dos 90 s vence quem tem maior % de vida; empate = CPU.
	## Também: sem regeneração lenta, sem monstros, sem itens, sem a Bola.
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var casos := [["jogador na frente", 0.8, 0.5, 1], ["CPU na frente", 0.3, 0.6, 2], ["empate", 0.5, 0.5, 2]]
	for c in casos:
		var t = _torre_script.new()
		t.comecar(0, 1, 7)
		t.andar = 3
		t.jogador = {"classe": 0, "nivel": 3, "historico": [], "vida": 1.0}
		var config: Dictionary = t.config_andar()
		main._nova_partida(config)
		await process_frame
		var p = main._atual
		if p.torre.is_empty() or p.tempo_restante != 90.0:
			_falha("fim do tempo (%s): partida da torre não montou" % c[0])
			continue
		var eu = p.jogadores[1]
		var cpu = p.jogadores[2]
		eu.vida = eu.vida_max * c[1]
		cpu.vida = cpu.vida_max * c[2]
		var vida_eu: float = eu.vida
		# começa a luta sem ninguém agindo; força itens/monstros a "vencerem" o relógio
		p.contagem = -5.0
		p._congelar(false)
		eu.ativo = false
		cpu.ativo = false
		eu._sem_dano = 100.0
		cpu._sem_dano = 100.0
		p._t_monstro = 100.0
		p._t_item = 100.0
		p.momentos_bola.clear()
		p.momentos_bola.append(p.tempo_restante)
		for i in 20:
			await physics_frame
		if not _perto(eu.vida, vida_eu, 0.0001):
			_falha("fim do tempo (%s): a vida regenerou na torre (%.2f → %.2f)" % [c[0], vida_eu, eu.vida])
		if p.get_tree().get_nodes_in_group("alvo").size() != 2 or not p.get_tree().get_nodes_in_group("item").is_empty():
			_falha("fim do tempo (%s): apareceram monstros ou itens" % c[0])
		p.tempo_restante = 0.01
		for i in 5:
			await physics_frame
		if not p.fim or p.vencedor != c[3] or p.morte_subita:
			_falha("fim do tempo (%s): vencedor %d, fim %s, súbita %s (esperava %d, sem súbita)" % [c[0], p.vencedor, p.fim, p.morte_subita, c[3]])
		# O controlador soma o tempo e decide: vitória avança, derrota/empate = game over
		t.registrar(p.vencedor, p)
		if not _perto(t.tempo_total, 89.99, 0.1) or t.estado != ("andar" if c[3] == 1 else "game_over") or t.andar != (4 if c[3] == 1 else 3):
			_falha("fim do tempo (%s): controlador com estado %s, andar %d, tempo %.2f" % [c[0], t.estado, t.andar, t.tempo_total])
		t.free()
	main.queue_free()
	await process_frame
	print("Torre (fim do tempo por % de vida, empate = CPU, sem regen/monstros/itens): ok")


func jogo_melhoria(l, id: String) -> void:
	Melhorias.aplicar(l, Melhorias.por_id(id))


func _confrontos(n: int, so_par: Array = []) -> void:
	## Tabela de vitórias entre classes (bot difícil x bot difícil, já com classe).
	## Com so_par = [a, b], roda só esse confronto (o tools/confrontos.sh roda os
	## pares em paralelo e soma).
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var nomes := ["Arqueiro", "Orc", "Mago", "Rei"]
	var vitorias := {}
	for a in 4:
		for b in range(a + 1, 4):
			if not so_par.is_empty() and (so_par[0] != a or so_par[1] != b):
				continue
			var va := 0
			var vb := 0
			var duracao := 0.0
			var subitas := 0
			for k in n:
				# Alterna os lados para não favorecer ninguém
				var lado_a := 1 if k % 2 == 0 else 2
				var classes := {lado_a: a, 3 - lado_a: b}
				# Sem itens: a Bola e o "ataque trocado" mudariam as classes no meio da partida
				var config := {"semente": 9000 + a * 100 + b * 10 + k, "tempo": 180.0, "bots": {1: 2, 2: 2}, "classes": classes, "itens": false}
				var r: Dictionary = await _jogar(main, config, 60 * 300)
				duracao += 180.0 - r.get("tempo", 0.0)
				if r.get("morte_subita", false):
					subitas += 1
				if r.get("vencedor", 0) == lado_a:
					va += 1
				elif r.get("vencedor", 0) == 3 - lado_a:
					vb += 1
			print("%-8s x %-8s : %d x %d" % [nomes[a], nomes[b], va, vb])
			print("PAR %s %s %d %d %.0f %d" % [nomes[a], nomes[b], va, vb, duracao / n, subitas])
			vitorias[nomes[a]] = vitorias.get(nomes[a], 0) + va
			vitorias[nomes[b]] = vitorias.get(nomes[b], 0) + vb
	print("\n=== CONFRONTOS (%d partidas por par) ===" % n)
	for c in nomes:
		print("%-8s %d vitórias em %d (%d%%)" % [c, vitorias.get(c, 0), n * 3, roundi(100.0 * vitorias.get(c, 0) / (n * 3))])
	main.queue_free()


func _equilibrio(n: int) -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var vitorias := {}
	var jogos := {}
	var subitas := 0
	var duracao := 0.0
	var recrutas_mortos := 0
	for i in n:
		var config := {"semente": 5000 + i, "tempo": 180.0, "bots": {1: 2, 2: 2}}
		var r: Dictionary = await _jogar(main, config, 60 * 300)
		if r["morte_subita"]:
			subitas += 1
		duracao += 180.0 - r["tempo"]
		for lado in [1, 2]:
			var c: String = r["classes"][lado]
			jogos[c] = jogos.get(c, 0) + 1
			if r["vencedor"] == lado:
				vitorias[c] = vitorias.get(c, 0) + 1
		print("partida %d: %s x %s -> %s aos %.0f s" % [i + 1, r["classes"][1], r["classes"][2],
				("P%d" % r["vencedor"]) if r["fim"] else "sem fim", 180.0 - r["tempo"]])
		if r["classes"][1] == "Recruta" or r["classes"][2] == "Recruta":
			recrutas_mortos += 1
	print("\n=== EQUILÍBRIO (%d partidas, bot difícil x bot difícil) ===" % n)
	for c in jogos:
		print("%-9s %2d vitórias em %2d partidas (%d%%)" % [c, vitorias.get(c, 0), jogos[c],
				roundi(100.0 * vitorias.get(c, 0) / jogos[c])])
	print("Foram para a Morte Súbita: %d de %d" % [subitas, n])
	print("Terminaram com alguém ainda Recruta: %d de %d" % [recrutas_mortos, n])
	print("Tempo médio até a Morte Súbita/fim: %.0f s" % (duracao / n))
	main.queue_free()
