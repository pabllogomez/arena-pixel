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
	_testar_mapas()
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
	for d in duelos:
		var config := {"semente": 1000 + d[0] * 10 + d[1], "tempo": 45.0, "bots": {1: d[0], 2: d[1]}}
		var r: Dictionary = await _jogar(main, config, 60 * 140)
		print("bot %s x bot %s | %-9s x %-9s | nível máx %d | portas %d | súbita: %s | fim: %s" % [
			NOMES_DIF[d[0]], NOMES_DIF[d[1]], r["classes"][1], r["classes"][2],
			r["nivel"], r["teleportes"], r["morte_subita"],
			("P%d venceu" % r["vencedor"]) if r["fim"] else "NÃO"])
		if not r["fim"]:
			_falha("partida não terminou mesmo com a Morte Súbita")
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
