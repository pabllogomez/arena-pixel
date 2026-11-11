class_name Controle
extends RefCounted
## "Botões" de um lutador. O jogador humano e o bot preenchem os mesmos
## campos, então o personagem usa exatamente o mesmo código nos dois casos.

var eixo := 0.0                ## -1 esquerda .. 1 direita
var pulo_apertou := false      ## apertou neste quadro
var pulo_soltou := false       ## soltou neste quadro (corta o pulo)
var descer_apertou := false
var opcao := -1                ## melhoria escolhida neste quadro (0 ou 1)


func atualizar(_l, _delta: float) -> void:
	pass


func nome() -> String:
	return ""
