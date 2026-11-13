extends Control
## Transição entre telas: a tela nova aparece por trás de uma cortina de
## blocos que encolhem em diagonal.

const BLOCO := 16.0
const DURACAO := 0.45

var _t := DURACAO


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE


func abrir() -> void:
	_t = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if _t < DURACAO:
		# Não desacelera junto com a câmera lenta do fim de partida
		_t += delta / maxf(Engine.time_scale, 0.05)
		queue_redraw()


func _draw() -> void:
	if _t >= DURACAO:
		return
	var colunas := int(ceilf(size.x / BLOCO))
	var linhas := int(ceilf(size.y / BLOCO))
	var avanco := _t / DURACAO
	for by in linhas:
		for bx in colunas:
			var atraso := float(bx + by) / float(colunas + linhas) * 0.6
			var p := clampf((avanco - atraso) / 0.4, 0.0, 1.0)
			var lado := roundf(BLOCO * (1.0 - p) / 2.0) * 2.0
			if lado <= 0.0:
				continue
			var centro := Vector2(bx + 0.5, by + 0.5) * BLOCO
			draw_rect(Rect2(centro - Vector2(lado, lado) / 2.0, Vector2(lado, lado)), UI.TINTA)
