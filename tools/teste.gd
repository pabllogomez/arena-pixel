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
		await _confrontos(int(args[i + 1]) if args.size() > i + 1 else 8)
		quit(0)
		return
	_testar_mapas()
	await _testar_pulos_e_itens()
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


func jogo_melhoria(l, id: String) -> void:
	Melhorias.aplicar(l, Melhorias.por_id(id))


func _confrontos(n: int) -> void:
	## Tabela de vitórias entre classes (bot difícil x bot difícil, já com classe).
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var nomes := ["Arqueiro", "Orc", "Mago", "Rei"]
	var vitorias := {}
	for a in 4:
		for b in range(a + 1, 4):
			var va := 0
			var vb := 0
			for k in n:
				# Alterna os lados para não favorecer ninguém
				var lado_a := 1 if k % 2 == 0 else 2
				var classes := {lado_a: a, 3 - lado_a: b}
				# Sem itens: a Bola e o "ataque trocado" mudariam as classes no meio da partida
				var config := {"semente": 9000 + a * 100 + b * 10 + k, "tempo": 180.0, "bots": {1: 2, 2: 2}, "classes": classes, "itens": false}
				var r: Dictionary = await _jogar(main, config, 60 * 300)
				if r.get("vencedor", 0) == lado_a:
					va += 1
				elif r.get("vencedor", 0) == 3 - lado_a:
					vb += 1
			print("%-8s x %-8s : %d x %d" % [nomes[a], nomes[b], va, vb])
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
