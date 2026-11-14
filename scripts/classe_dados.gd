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
## Altura do pulo. A altura real é forca_pulo² / (2 × 700 × mult_gravidade);
## abaixo de ~52 px a classe não alcança as plataformas.
@export var forca_pulo := 290.0

@export_group("Peso")
## Quão rápido chega à velocidade máxima (menor = mais pesado).
@export var aceleracao := 1250.0
## Quão rápido para ao soltar o direcional (menor = escorrega mais).
@export var atrito := 1500.0
## Gravidade da classe (maior = cai mais rápido, pulo mais curto).
@export var mult_gravidade := 1.0
## 0 = empurrado normalmente pelos golpes; 1 = não se mexe.
@export_range(0.0, 1.0) var resistencia_empurrao := 0.0
## Treme a tela e levanta poeira ao cair de uma altura.
@export var pouso_pesado := false
## Fração do dano de lacaios ignorada (0 = nenhuma). Classes com valor > 0
## também arremessam lacaios para longe com o golpe.
@export_range(0.0, 1.0) var resistencia_lacaios := 0.0

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
