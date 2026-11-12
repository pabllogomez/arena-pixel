extends Node
## Autoload "Rede": multijogador 1x1 pelo navegador, via WebRTC, sem servidor.
##
## A conexão é combinada "copiando e colando" dois códigos:
##   1. o anfitrião gera o código de convite e manda para o amigo;
##   2. o convidado cola o convite e gera o código de resposta;
##   3. o anfitrião cola a resposta e os dois se conectam direto.
## Os códigos carregam os dados técnicos da conexão (por isso são longos).
##
## Na partida, o anfitrião simula tudo; o convidado só envia seus comandos
## e desenha o estado que recebe (ver partida.gd).

signal codigo_pronto(codigo: String)   ## convite (anfitrião) ou resposta (convidado)
signal conectado
signal desconectado
signal partida_recebida(config: Dictionary)
signal falhou(motivo: String)

const PREFIXO := "AP1"
const ICE := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]}
const ID_ANFITRIAO := 1
const ID_CONVIDADO := 2

## "" (sem rede), "anfitriao" ou "convidado"
var papel := ""
var esta_conectado := false
## Partida em andamento que recebe os dados da rede
var partida: Node = null

var _peer: WebRTCMultiplayerPeer
var _conexao: WebRTCPeerConnection
var _sdp_tipo := ""
var _sdp := ""
var _candidatos: Array = []
var _esperando_codigo := false
var _t_coleta := 0.0
var _eventos: Array = []


func e_anfitriao() -> bool:
	return papel == "anfitriao" and esta_conectado


func e_convidado() -> bool:
	return papel == "convidado"


func numero_local() -> int:
	## Qual jogador é "você" nesta tela (anfitrião = P1, convidado = P2).
	return ID_CONVIDADO if papel == "convidado" else 1


# ------------------------------------------------------------------ Conexão

func _novo_par(e_servidor: bool) -> void:
	desconectar()
	_peer = WebRTCMultiplayerPeer.new()
	var erro := _peer.create_server() if e_servidor else _peer.create_client(ID_CONVIDADO)
	if erro != OK:
		falhou.emit("Este navegador não suporta jogo em rede (WebRTC).")
		return
	_conexao = WebRTCPeerConnection.new()
	_conexao.initialize(ICE)
	_conexao.session_description_created.connect(_ao_criar_descricao)
	_conexao.ice_candidate_created.connect(_ao_criar_candidato)
	_peer.add_peer(_conexao, ID_CONVIDADO if e_servidor else ID_ANFITRIAO)
	multiplayer.multiplayer_peer = _peer
	_sdp = ""
	_candidatos.clear()
	_esperando_codigo = true
	_t_coleta = 0.0


func criar_convite() -> void:
	## Anfitrião: gera o código de convite (chega pelo sinal codigo_pronto).
	_novo_par(true)
	papel = "anfitriao"
	if _conexao != null:
		_conexao.create_offer()


func aceitar_convite(codigo: String) -> bool:
	## Convidado: lê o convite e gera o código de resposta (sinal codigo_pronto).
	var dados := _decodificar(codigo)
	if dados.is_empty() or dados.get("t") != "offer":
		falhou.emit("Código de convite inválido.")
		return false
	_novo_par(false)
	papel = "convidado"
	if _conexao == null:
		return false
	_conexao.set_remote_description("offer", dados["s"])
	for c in dados["c"]:
		_conexao.add_ice_candidate(c[0], int(c[1]), c[2])
	return true


func aceitar_resposta(codigo: String) -> bool:
	## Anfitrião: lê a resposta do convidado e conclui a conexão.
	var dados := _decodificar(codigo)
	if dados.is_empty() or dados.get("t") != "answer" or _conexao == null:
		falhou.emit("Código de resposta inválido.")
		return false
	_conexao.set_remote_description("answer", dados["s"])
	for c in dados["c"]:
		_conexao.add_ice_candidate(c[0], int(c[1]), c[2])
	return true


func conectar_para_teste(peer: MultiplayerPeer, p: String) -> void:
	## Só para os testes automáticos: usa uma conexão ENet local no lugar do
	## WebRTC (o resto do jogo em rede funciona igual).
	desconectar()
	multiplayer.multiplayer_peer = peer
	papel = p


func desconectar() -> void:
	if _peer != null:
		_peer.close()
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer = null
	_peer = null
	_conexao = null
	var estava := esta_conectado
	esta_conectado = false
	papel = ""
	partida = null
	_eventos.clear()
	if estava:
		desconectado.emit()


func _ready() -> void:
	multiplayer.peer_connected.connect(func(_id: int) -> void:
		esta_conectado = true
		conectado.emit())
	multiplayer.peer_disconnected.connect(func(_id: int) -> void:
		var estava := esta_conectado
		esta_conectado = false
		if estava:
			desconectado.emit())


func _ao_criar_descricao(tipo: String, sdp: String) -> void:
	_conexao.set_local_description(tipo, sdp)
	_sdp_tipo = tipo
	_sdp = sdp


func _ao_criar_candidato(midia: String, indice: int, nome: String) -> void:
	_candidatos.append([midia, indice, nome])
	_t_coleta = 0.0


func _process(delta: float) -> void:
	# Espera os candidatos de rede serem coletados antes de mostrar o código
	if not _esperando_codigo or _sdp == "" or _conexao == null:
		return
	_t_coleta += delta
	var completo := false
	if _conexao.has_method("get_gathering_state"):
		completo = int(_conexao.call("get_gathering_state")) == 2  # 2 = coleta completa
	if completo or (_t_coleta > 1.5 and not _candidatos.is_empty()) or _t_coleta > 4.0:
		_esperando_codigo = false
		codigo_pronto.emit(_codificar({"t": _sdp_tipo, "s": _sdp, "c": _candidatos}))


# ------------------------------------------------------------------ Códigos

func _codificar(dados: Dictionary) -> String:
	var bruto := JSON.stringify(dados).to_utf8_buffer()
	var comprimido := bruto.compress(FileAccess.COMPRESSION_DEFLATE)
	return "%s.%d.%s" % [PREFIXO, bruto.size(), Marshalls.raw_to_base64(comprimido)]


func _decodificar(codigo: String) -> Dictionary:
	var partes := codigo.strip_edges().replace(" ", "").replace("\n", "").split(".")
	if partes.size() != 3 or partes[0] != PREFIXO or not partes[1].is_valid_int():
		return {}
	var comprimido := Marshalls.base64_to_raw(partes[2])
	if comprimido.is_empty():
		return {}
	var bruto := comprimido.decompress(int(partes[1]), FileAccess.COMPRESSION_DEFLATE)
	var dados = JSON.parse_string(bruto.get_string_from_utf8())
	if not (dados is Dictionary) or not dados.has_all(["t", "s", "c"]):
		return {}
	return dados


# ------------------------------------------------------------------ Área de transferência

func copiar(texto: String) -> void:
	DisplayServer.clipboard_set(texto)


func mostrar_para_copiar(texto: String) -> void:
	## Plano B se o "copiar" automático falhar: abre uma caixa com o código selecionável.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.prompt('Copie o código abaixo:', %s)" % JSON.stringify(texto))


func pedir_colagem(mensagem: String) -> String:
	## Abre uma caixa de texto do navegador (no celular dá para colar com toque longo).
	if OS.has_feature("web"):
		var r = JavaScriptBridge.eval("window.prompt(%s) || ''" % JSON.stringify(mensagem))
		return str(r) if r != null else ""
	return DisplayServer.clipboard_get()


# ------------------------------------------------------------------ Mensagens da partida

func iniciar_partida_remota(config: Dictionary) -> void:
	## Anfitrião avisa o convidado para montar a mesma partida.
	if e_anfitriao():
		_r_iniciar.rpc(config)


func enviar_entrada(estado: Array) -> void:
	if esta_conectado and papel == "convidado":
		_r_entrada.rpc_id(ID_ANFITRIAO, estado)


func enviar_escolha(op: int) -> void:
	if esta_conectado and papel == "convidado":
		_r_escolha.rpc_id(ID_ANFITRIAO, op)


func enviar_estado(estado: Dictionary) -> void:
	if e_anfitriao():
		_r_estado.rpc(estado)


func evento(e: Array) -> void:
	## Efeito (som, texto, brilho...) que o convidado também precisa ver/ouvir.
	if e_anfitriao() and partida != null:
		_eventos.append(e)


func _physics_process(_delta: float) -> void:
	if not _eventos.is_empty() and e_anfitriao():
		_r_eventos.rpc(_eventos)
		_eventos = []


@rpc("authority", "call_remote", "reliable")
func _r_iniciar(config: Dictionary) -> void:
	partida_recebida.emit(config)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _r_entrada(estado: Array) -> void:
	if partida != null and papel == "anfitriao":
		partida.receber_entrada_remota(estado)


@rpc("any_peer", "call_remote", "reliable")
func _r_escolha(op: int) -> void:
	if partida != null and papel == "anfitriao":
		partida.receber_escolha_remota(op)


@rpc("authority", "call_remote", "unreliable_ordered")
func _r_estado(estado: Dictionary) -> void:
	if partida != null and papel == "convidado":
		partida.aplicar_estado(estado)


@rpc("authority", "call_remote", "reliable")
func _r_eventos(lista: Array) -> void:
	if partida != null and papel == "convidado":
		for e in lista:
			partida.aplicar_evento(e)
