class_name MapaControle
extends RefCounted
## Números dos botões do controle. No desktop o SDL já entrega os
## índices do Godot (JoyButton). No NAVEGADOR o Godot 4.4 entrega os índices
## crus do mapeamento "standard" do W3C, que são outros: 6 é o gatilho LT (no
## Godot é START) e 12 é o direcional para cima (no Godot é DPAD_BAIXO).
## Em vez de traduzir cada evento (a ação do Input já seria acionada com o
## índice errado), os atalhos (InputMap, cadastrados em Jogo._criar_controles) é que usam os índices certos da
## plataforma. Tudo passa por botao(); os gatilhos (W3C 6 e 7) não são ligados
## a nada. Para testar fora do navegador, ligue `web`.

## W3C "standard": 0 A, 1 B, 2 X, 3 Y, 4 LB, 5 RB, 6 LT, 7 RT, 8 Back, 9 Start,
## 10 LS, 11 RS, 12 cima, 13 baixo, 14 esquerda, 15 direita, 16 Guide.
const W3C := {
	JOY_BUTTON_A: 0, JOY_BUTTON_B: 1, JOY_BUTTON_X: 2, JOY_BUTTON_Y: 3,
	JOY_BUTTON_LEFT_SHOULDER: 4, JOY_BUTTON_RIGHT_SHOULDER: 5,
	JOY_BUTTON_BACK: 8, JOY_BUTTON_START: 9,
	JOY_BUTTON_LEFT_STICK: 10, JOY_BUTTON_RIGHT_STICK: 11,
	JOY_BUTTON_DPAD_UP: 12, JOY_BUTTON_DPAD_DOWN: 13,
	JOY_BUTTON_DPAD_LEFT: 14, JOY_BUTTON_DPAD_RIGHT: 15,
	JOY_BUTTON_GUIDE: 16,
}

static var web := OS.has_feature("web")


## O índice que o evento traz nesta plataforma para o botão do Godot.
static func botao(b: JoyButton) -> JoyButton:
	return (W3C.get(b, b) as int) as JoyButton if web else b

