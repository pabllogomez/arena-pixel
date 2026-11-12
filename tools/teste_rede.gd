extends SceneTree
## Teste do jogo em rede com DUAS instâncias do jogo conectadas por ENet
## (localhost). O WebRTC do navegador só troca o "cano" da conexão; o resto
## (comandos, estado, efeitos, cartas, fim de partida) é o que este teste cobre.
##
##   PAPEL=anfitriao godot --headless --path . -s tools/teste_rede.gd &
##   PAPEL=convidado godot --headless --path . -s tools/teste_rede.gd
## Cada instância termina imprimindo "REDE OK" ou "REDE FALHA: ...".

const PORTA := 47123
var papel := ""
var main
var falhas: Array[String] = []


func _log(t: String) -> void:
	print("[", papel, "] ", t)


func _checar(ok: bool, msg: String) -> void:
	if not ok:
		falhas.append(msg)
		_log("FALHOU: " + msg)


func _esperar(cond: Callable, limite: float) -> bool:
	var t := 0.0
	while not cond.call():
		await create_timer(0.1).timeout
		t += 0.1
		if t > limite:
			return false
	return true


func _initialize() -> void:
	papel = OS.get_environment("PAPEL")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var rede = root.get_node("Rede")
	var jogo = root.get_node("Jogo")

	# Códigos de conexão: ida e volta
	var amostra := {"t": "offer", "s": "v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\n" + "a=x\r\n".repeat(40),
			"c": [["0", 0, "candidate:1 1 udp 2122260223 192.168.0.10 50000 typ host"]]}
	var volta: Dictionary = rede._decodificar(rede._codificar(amostra))
	_checar(volta.get("s") == amostra["s"] and volta.get("t") == "offer", "código não decodifica igual")
	_checar(rede._decodificar("lixo").is_empty(), "código inválido deveria ser recusado")

	var enet := ENetMultiplayerPeer.new()
	if papel == "anfitriao":
		enet.create_server(PORTA, 1)
		rede.conectar_para_teste(enet, "anfitriao")
		_checar(await _esperar(func(): return rede.esta_conectado, 15.0), "convidado não conectou")
		main._nova_partida(jogo.config_rede())
		var p = main._atual
		await create_timer(8.0).timeout
		_checar(p.jogadores[2].position.distance_to(p.mapa["inicio"][2]) > 20.0, "comandos do convidado não moveram o P2")
		p.jogadores[2].ganhar_xp(16)
		p.jogadores[2].ganhar_xp(12)
		_checar(await _esperar(func(): return p.jogadores[2].escolhas.is_empty(), 8.0), "escolha de melhoria do convidado não chegou")
		p.jogadores[1].receber_dano(9999, null)
		await create_timer(3.0).timeout
	else:
		await create_timer(0.5).timeout
		enet.create_client("127.0.0.1", PORTA)
		rede.conectar_para_teste(enet, "convidado")
		_checar(await _esperar(func(): return main._atual != null and main._atual.get("rede") == "convidado", 15.0), "partida não chegou ao convidado")
		var p = main._atual
		await create_timer(3.5).timeout
		Input.action_press("p1_direita")
		await create_timer(1.0).timeout
		Input.action_release("p1_direita")
		Input.action_press("p1_pular")
		await create_timer(0.25).timeout
		Input.action_release("p1_pular")
		await create_timer(1.0).timeout
		_checar(p.tempo_restante < 179.0, "cronômetro não chega ao convidado")
		_checar(p.jogadores[2].nome_jogador() == "VOCÊ" and p.jogadores[1].nome_jogador() == "AMIGO", "rótulos errados no convidado")
		_checar(await _esperar(func(): return p.hud.mostra_cartas(2), 10.0), "cartas de melhoria não apareceram no convidado")
		_checar(not p.jogadores[2].eh_recruta, "classe do convidado não sincronizou")
		p.escolher(2, 0)
		_checar(await _esperar(func(): return p.fim, 10.0), "fim de partida não chegou ao convidado")
		_checar(p.vencedor == 2, "vencedor errado no convidado")
	print("REDE OK" if falhas.is_empty() else "REDE FALHA: " + ", ".join(falhas))
	quit(0 if falhas.is_empty() else 1)
