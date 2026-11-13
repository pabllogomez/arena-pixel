extends Node2D
## Texto que salta de um personagem (dano, XP, melhoria), na fonte pixel.

var texto := ""
var tam := UI.P
var cor := Color.WHITE


func _draw() -> void:
	UI.texto(self, Vector2.ZERO, texto, tam, cor)
