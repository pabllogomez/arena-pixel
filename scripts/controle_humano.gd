class_name ControleHumano
extends Controle
## Lê teclado/controle do jogador `numero`.

var numero := 1


func _init(n: int) -> void:
	numero = n


func atualizar(l, _delta: float) -> void:
	# Em rede a pausa não congela o jogo: os botões que navegam no painel
	# (direcional, A, B) não podem andar, pular ou dar dash.
	if l != null and l.partida != null and l.partida.pausado:
		eixo = 0.0
		pulo_apertou = false
		pulo_soltou = false
		descer_apertou = false
		dash_apertou = false
		dash_dir = 0.0
		opcao = -1
		return
	eixo = Input.get_axis(_a("esquerda"), _a("direita"))
	pulo_apertou = Input.is_action_just_pressed(_a("pular"))
	pulo_soltou = Input.is_action_just_released(_a("pular"))
	descer_apertou = Input.is_action_just_pressed(_a("descer"))
	# Teclado/controle: dash_dir = 0 (usa o eixo). O toque aperta dash_esq/dash_dir
	# para indicar o sentido do arraste.
	var dash_esq := Input.is_action_pressed(_a("dash_esq"))
	var dash_dire := Input.is_action_pressed(_a("dash_dir"))
	dash_apertou = Input.is_action_just_pressed(_a("dash")) \
			or Input.is_action_just_pressed(_a("dash_esq")) or Input.is_action_just_pressed(_a("dash_dir"))
	dash_dir = (1.0 if dash_dire else 0.0) - (1.0 if dash_esq else 0.0)
	opcao = -1  # melhorias de humanos são escolhidas pela partida (funciona até pausado)


func _a(nome_acao: String) -> String:
	return Jogo.acao(numero, nome_acao)
