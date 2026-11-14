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


func _initialize() -> void:
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
	await _testar_dash()
	_testar_dash_rede()
	_testar_mapeamento_controle()
	await _testar_cartas_layout()
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
