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

@export_group("Investida, fúria e pouso")
## Investida: fração do dano da classe causada ao encostar num hostil durante
## o dash (1 acerto por alvo por dash). 0 = dash normal, sem dano.
@export var dano_investida := 0.0
## Empurrão (px/s) dado pela investida na direção do dash.
@export var empurrao_investida := 0.0
## Fúria: abaixo desta fração da vida máxima a classe ganha os multiplicadores
## abaixo. 0 = sem fúria.
@export_range(0.0, 1.0) var furia_limite := 0.0
@export var furia_mult_vel := 1.0
@export var furia_mult_dano := 1.0
## Pouso pesado: onda de choque que fere hostis neste raio (px); 0 = sem onda.
@export var raio_pouso := 0.0
## Fração do dano da classe causada pela onda de choque do pouso.
@export var dano_pouso := 0.0
@export var empurrao_pouso := 0.0

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

@export_group("Cetro (Rei)")
## Golpe corpo a corpo secundário, automático: sai quando um hostil (lutador,
## monstro ou lacaio inimigo) chega perto. 0 = sem cetro. Não depende da
## recarga de invocação nem entra nela.
@export var alcance_cetro := 0.0
## Segundos entre cetradas (sem contar as do dash).
@export var intervalo_cetro := 1.0
## Fração do dano do golpe de um lacaio (dano do Rei x mult_lacaio).
@export var dano_cetro := 0.5
## Múltiplo do empurrão base de um golpe (70 px/s x resistência x mult_empurrao).
@export var empurrao_cetro := 2.0
## Dash com cetro: encostar num hostil golpeia na hora (ignora a recarga, 1 por
## alvo por dash) e o empurrão vira este múltiplo a mais.
@export var mult_empurrao_cetro_dash := 1.0
