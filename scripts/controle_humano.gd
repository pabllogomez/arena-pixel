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
	opcao = -1
	if Input.is_action_just_pressed(_a("opcao1")):
		opcao = 0
	elif Input.is_action_just_pressed(_a("opcao2")):
		opcao = 1


func _a(nome_acao: String) -> String:
	return Jogo.acao(numero, nome_acao)
