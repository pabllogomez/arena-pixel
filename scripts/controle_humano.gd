class_name ControleHumano
extends Controle
## Lê teclado/controle do jogador `numero`.

var numero := 1


func _init(n: int) -> void:
	numero = n


func atualizar(_l, _delta: float) -> void:
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
