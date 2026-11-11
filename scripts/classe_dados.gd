class_name ClasseDados
extends Resource
## Atributos de uma classe. Edite os arquivos em resources/classes/
## pelo Inspector do Godot para balancear o jogo.

enum TipoAtaque { FLECHA, CORPO_A_CORPO, MAGIA, INVOCAR }

@export var nome := ""
@export_multiline var descricao := ""
@export var textura_p1: Texture2D
@export var textura_p2: Texture2D

@export_group("Atributos")
@export var vida_max := 100.0
@export var velocidade := 80.0
## Altura do pulo. Abaixo de ~280 a classe não alcança as plataformas.
@export var forca_pulo := 290.0

@export_group("Ataque")
@export var tipo_ataque: TipoAtaque = TipoAtaque.FLECHA
@export var dano := 10.0
## Distância em que o ataque automático dispara.
@export var alcance := 100.0
## Segundos entre ataques (no Rei: entre um lacaio e outro).
@export var intervalo_ataque := 1.0
@export var velocidade_projetil := 200.0
## Mago: fração do dano que sobra quando o orbe chega ao alcance máximo.
@export_range(0.0, 1.0) var dano_minimo_magia := 0.25

@export_group("Lacaios (Rei)")
@export var max_lacaios := 0
@export var vida_lacaio := 25.0
@export var velocidade_lacaio := 55.0
