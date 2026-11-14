extends Node
## Alterna entre o menu, a tela de rede e a partida.

const CENA_MENU := preload("res://scenes/menu.tscn")
const CENA_PARTIDA := preload("res://scenes/partida.tscn")

var _atual: Node
var _toque: Control
var _cortina: Control
## Torre da Tormenta em andamento (null fora do modo)
var _torre: Torre


func _ready() -> void:
	# Controles na tela para celular (ficam por cima de tudo)
	var camada := CanvasLayer.new()
	camada.layer = 10
	add_child(camada)
	_toque = preload("res://scripts/controles_toque.gd").new()
	camada.add_child(_toque)
	# Cortina de blocos que abre a cada troca de tela (por cima de tudo)
	var camada_cortina := CanvasLayer.new()
	camada_cortina.layer = 20
	add_child(camada_cortina)
	_cortina = preload("res://scripts/cortina.gd").new()
	camada_cortina.add_child(_cortina)
	# Convidado em rede: a partida começa quando o anfitrião manda
	Rede.partida_recebida.connect(_nova_partida, CONNECT_DEFERRED)
	_abrir_menu()


func _trocar(nova: Node) -> void:
	if _atual != null:
		_atual.queue_free()
	_atual = nova
	add_child(nova)
	_cortina.abrir()


func _abrir_menu() -> void:
	Rede.desconectar()  # sair para o menu encerra o jogo em rede
	var m = CENA_MENU.instantiate()
	m.jogar.connect(_nova_partida, CONNECT_DEFERRED)
	m.jogar_rede.connect(_abrir_lobby, CONNECT_DEFERRED)
	m.jogar_torre.connect(_iniciar_torre, CONNECT_DEFERRED)
	_encerrar_torre()
	_toque.partida = null
	_trocar(m)
	Jogo.tocar_musica("menu")


func _abrir_lobby() -> void:
	var l = preload("res://scripts/lobby.gd").new()
	l.voltar.connect(_abrir_menu, CONNECT_DEFERRED)
	l.iniciar_como_anfitriao.connect(_nova_partida, CONNECT_DEFERRED)
	_toque.partida = null
	_trocar(l)


func _nova_partida(config: Dictionary = {}) -> void:
	if config.is_empty():
		# Revanche ou partida nova: em rede quem decide é o anfitrião
		config = Jogo.config_rede() if Rede.e_anfitriao() else Jogo.config_partida()
	if config.get("rede", "") == "" and Rede.papel != "":
		return  # convidado não começa partida sozinho
	var p = CENA_PARTIDA.instantiate()
	_trocar(p)
	_toque.partida = p
	p.iniciar(config)
	p.revanche.connect(_nova_partida, CONNECT_DEFERRED)
	p.voltar.connect(_abrir_menu, CONNECT_DEFERRED)
	p.fim_de_luta.connect(_ao_fim_de_luta.bind(p), CONNECT_DEFERRED)


# ------------------------------------------------------------------ Torre da Tormenta

func _iniciar_torre(personagem: int, dificuldade: int) -> void:
	_encerrar_torre()
	Jogo.solo = true
	_torre = Torre.new()
	add_child(_torre)
	_torre.comecar(personagem, dificuldade)
	_nova_partida(_torre.config_andar())


func _encerrar_torre() -> void:
	if _torre != null:
		_torre.queue_free()
		_torre = null


func _ao_fim_de_luta(vencedor: int, p: Node) -> void:
	if _torre == null or p != _atual:
		return
	_torre.registrar(vencedor, p)
	if _torre.estado == "andar":
		_nova_partida(_torre.config_andar())
		return
	var t: Control = preload("res://scripts/torre_fim.gd").new()
	t.torre = _torre
	t.de_novo.connect(func() -> void: _iniciar_torre(_torre.personagem, _torre.dificuldade), CONNECT_DEFERRED)
	t.menu.connect(_abrir_menu, CONNECT_DEFERRED)
	_toque.partida = null
	_trocar(t)
	Jogo.tocar_musica("menu")
