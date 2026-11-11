extends Node
## Alterna entre a tela de seleção e a partida.

const CENA_SELECAO := preload("res://scenes/selecao.tscn")
const CENA_PARTIDA := preload("res://scenes/partida.tscn")

var _atual: Node


func _ready() -> void:
	_abrir_selecao()


func _trocar(nova: Node) -> void:
	if _atual != null:
		_atual.queue_free()
	_atual = nova
	add_child(nova)


func _abrir_selecao() -> void:
	var s = CENA_SELECAO.instantiate()
	s.pronto.connect(_nova_partida)
	_trocar(s)


func _nova_partida() -> void:
	var p = CENA_PARTIDA.instantiate()
	_trocar(p)
	p.iniciar(Jogo.dados_classe(Jogo.escolha[1]), Jogo.dados_classe(Jogo.escolha[2]), randi())
	p.revanche.connect(_nova_partida, CONNECT_DEFERRED)
	p.voltar.connect(_abrir_selecao, CONNECT_DEFERRED)
