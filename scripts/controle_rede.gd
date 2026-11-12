class_name ControleRede
extends Controle
## Comandos do convidado, recebidos pela rede (usado pelo anfitrião).
## O convidado manda o estado dos botões várias vezes por segundo; os
## "apertões" de pulo e descida vêm como contadores, para não se perderem
## se algum pacote não chegar.

var _eixo := 0.0
var _pulos := 0
var _pulos_vistos := 0
var _segurando := false
var _segurando_antes := false
var _descidas := 0
var _descidas_vistas := 0


func receber(estado: Array) -> void:
	## [eixo, total de pulos, segurando pulo, total de descidas]
	if estado.size() < 4:
		return
	_eixo = clampf(float(estado[0]), -1.0, 1.0)
	_pulos = maxi(_pulos, int(estado[1]))
	_segurando = bool(estado[2])
	_descidas = maxi(_descidas, int(estado[3]))


func atualizar(_l, _delta: float) -> void:
	eixo = _eixo
	pulo_apertou = _pulos > _pulos_vistos
	_pulos_vistos = _pulos
	pulo_soltou = _segurando_antes and not _segurando
	_segurando_antes = _segurando
	descer_apertou = _descidas > _descidas_vistas
	_descidas_vistas = _descidas
	opcao = -1  # escolhas chegam por mensagem própria (partida.receber_escolha_remota)


func nome() -> String:
	return "AMIGO"
