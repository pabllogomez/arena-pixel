class_name ControleRede
extends Controle
## Comandos do convidado, recebidos pela rede (usado pelo anfitrião).
## O convidado manda o estado dos botões várias vezes por segundo; os
## "apertões" de pulo, descida e dash vêm como contadores, para não se perderem
## se algum pacote não chegar.

var _eixo := 0.0
var _pulos := 0
var _pulos_vistos := 0
var _segurando := false
var _segurando_antes := false
var _descidas := 0
var _descidas_vistas := 0
var _dashes := 0
var _dashes_vistos := 0
var _dir_dash := 0.0


func receber(estado: Array) -> void:
	## [eixo, total de pulos, segurando pulo, total de descidas, total de dashes,
	## direção do último dash]. Estado de 4 elementos (versão antiga) = sem dash.
	if estado.size() < 4:
		return
	_eixo = clampf(float(estado[0]), -1.0, 1.0)
	_pulos = maxi(_pulos, int(estado[1]))
	_segurando = bool(estado[2])
	_descidas = maxi(_descidas, int(estado[3]))
	if estado.size() >= 6:
		_dashes = maxi(_dashes, int(estado[4]))
		_dir_dash = signf(float(estado[5]))


func atualizar(_l, _delta: float) -> void:
	eixo = _eixo
	pulo_apertou = _pulos > _pulos_vistos
	_pulos_vistos = _pulos
	pulo_soltou = _segurando_antes and not _segurando
	_segurando_antes = _segurando
	descer_apertou = _descidas > _descidas_vistas
	_descidas_vistas = _descidas
	dash_apertou = _dashes > _dashes_vistos
	_dashes_vistos = _dashes
	dash_dir = _dir_dash if dash_apertou else 0.0
	opcao = -1  # escolhas chegam por mensagem própria (partida.receber_escolha_remota)


func nome() -> String:
	return "AMIGO"
