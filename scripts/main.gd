extends Node
## Alterna entre o menu e a partida.

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
	_abrir_menu()


func _trocar(nova: Node) -> void:
	if _atual != null:
		_atual.queue_free()
	_atual = nova
	add_child(nova)


func _abrir_menu() -> void:
	var m = CENA_MENU.instantiate()
	m.jogar.connect(_nova_partida, CONNECT_DEFERRED)
	_toque.partida = null
	_trocar(m)
	Jogo.tocar_musica("menu")


func _nova_partida(config: Dictionary = {}) -> void:
	var p = CENA_PARTIDA.instantiate()
	_trocar(p)
	_toque.partida = p
	p.iniciar(config if not config.is_empty() else Jogo.config_partida())
	p.revanche.connect(_nova_partida, CONNECT_DEFERRED)
	p.voltar.connect(_abrir_menu, CONNECT_DEFERRED)
