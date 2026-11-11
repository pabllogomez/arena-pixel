extends SceneTree
## Teste automático (sem janela):
##   godot --headless --path . -s tools/teste.gd
## 1) Gera muitos mapas e confere se as portas estão consistentes.
## 2) Simula partidas com todas as combinações de classes e entradas aleatórias.

var _falhas := 0


func _initialize() -> void:
	_testar_mapas()
	await _testar_partidas()
	print("RESULTADO: ", "OK" if _falhas == 0 else "%d FALHA(S)" % _falhas)
	quit(1 if _falhas else 0)


func _falha(msg: String) -> void:
	_falhas += 1
	printerr("FALHA: ", msg)


func _testar_mapas() -> void:
	var tetos := 0
	for semente in 2000:
		var rng := RandomNumberGenerator.new()
		rng.seed = semente
		var m := GeradorArena.gerar(rng)
		var g: Array = m["grade"]
		var portas: Array = m["portas"]
		var esq := portas.filter(func(p): return p["tipo"] == "esq").size()
		var dir := portas.filter(func(p): return p["tipo"] == "dir").size()
		var teto := portas.filter(func(p): return p["tipo"] == "teto").size()
		tetos += teto
		if esq < 1 or dir < 1 or esq > 3 or dir > 3:
			_falha("semente %d: %d esq / %d dir" % [semente, esq, dir])
		if maxi(esq, dir) != mini(esq, dir) + teto:
			_falha("semente %d: conta não fecha (%d x %d + %d teto)" % [semente, esq, dir, teto])
		for i in portas.size():
			var p: Dictionary = portas[i]
			var par: Dictionary = portas[p["par"]]
			if portas[par["par"]] != p:
				_falha("semente %d: par não é recíproco" % semente)
			if par["tipo"] == p["tipo"]:
				_falha("semente %d: porta ligada ao mesmo lado" % semente)
			# a saída tem que estar livre (2 tiles de altura) e ter chão embaixo
			var s: Vector2 = p["saida"]
			var cx := int(s.x / 16)
			var cy := int(s.y / 16)
			if g[cy][cx] != GeradorArena.VAZIO:
				_falha("semente %d: saída da porta %s bloqueada" % [semente, p["tipo"]])
			if p["tipo"] != "teto" and g[cy + 1][cx] == GeradorArena.VAZIO:
				_falha("semente %d: saída lateral sem chão" % semente)
		if (m["pontos_monstro"] as Array).is_empty():
			_falha("semente %d: sem pontos de monstro" % semente)
	print("Mapas: 2000 gerados, %d portas no teto no total" % tetos)


func _testar_partidas() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var acoes := ["esquerda", "direita", "pular", "descer", "opcao1", "opcao2"]
	for c1 in 4:
		for c2 in 4:
			var jogo = root.get_node("Jogo")
			jogo.escolha[1] = c1
			jogo.escolha[2] = c2
			main._nova_partida()
			await process_frame
			var p = main._atual
			var max_nivel := 0
			var teleportes := 0
			var pos_antes := {}
			# ~40 s de jogo a 60 fps, com entradas aleatórias
			for f in 2400:
				if f % 12 == 0:
					for n in [1, 2]:
						for a in acoes:
							Input.action_release("p%d_%s" % [n, a])
						var a2: String = acoes.pick_random()
						Input.action_press("p%d_%s" % [n, a2])
				for n in [1, 2]:
					var l = p.jogadores[n]
					if pos_antes.has(n) and l.position.distance_to(pos_antes[n]) > 100:
						teleportes += 1
					pos_antes[n] = l.position
					max_nivel = maxi(max_nivel, l.nivel)
				await physics_frame
				if p.fim:
					break
			var v1 = p.jogadores[1]
			var v2 = p.jogadores[2]
			print("%-8s x %-8s | vida %3d / %3d | nível máx %d | teleportes %d | fim: %s" % [
				jogo.CLASSES[c1], jogo.CLASSES[c2], v1.vida, v2.vida, max_nivel, teleportes,
				("P%d venceu" % p.vencedor) if p.fim else "não"])
			for n in [1, 2]:
				var l = p.jogadores[n]
				if l.position.y > 13 * 16 or l.position.x < -40 or l.position.x > 24 * 16 + 40:
					_falha("jogador %d fora da arena em %s" % [n, l.position])
	for n in [1, 2]:
		for a in acoes:
			Input.action_release("p%d_%s" % [n, a])
