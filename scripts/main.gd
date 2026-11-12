extends Node
## Alterna entre o menu, a tela de rede e a partida.

const CENA_MENU := preload("res://scenes/menu.tscn")
const CENA_PARTIDA := preload("res://scenes/partida.tscn")

var _atual: Node
var _toque: Control


func _ready() -> void:
	# Controles na tela para celular (ficam por cima de tudo)
	var camada := CanvasLayer.new()
	camada.layer = 10
	add_child(camada)
	_toque = preload("res://scripts/controles_toque.gd").new()
	camada.add_child(_toque)
	# Convidado em rede: a partida começa quando o anfitrião manda
	Rede.partida_recebida.connect(_nova_partida, CONNECT_DEFERRED)
	_abrir_menu()


func _trocar(nova: Node) -> void:
	if _atual != null:
		_atual.queue_free()
	_atual = nova
	add_child(nova)


func _abrir_menu() -> void:
	Rede.desconectar()  # sair para o menu encerra o jogo em rede
	var m = CENA_MENU.instantiate()
	m.jogar.connect(_nova_partida, CONNECT_DEFERRED)
	m.jogar_rede.connect(_abrir_lobby, CONNECT_DEFERRED)
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
