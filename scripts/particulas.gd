class_name Particulas
extends Node2D
## Partículas em pixel art: quadradinhos de 1 ou 2 px presos à grade, com
## gravidade, arrasto e quique no cenário. Um nó só desenha todas (leve no
## celular). Nada aqui interfere nas regras: é só enfeite.
##
## As cores não somem por transparência: cada partícula percorre uma "rampa"
## de cores da paleta do jogo e pisca um instante antes de sumir.

const MAX := 700
const TAM := GeradorArena.TAM

# Rampas de cor (da mais quente/clara para a mais apagada)
enum {FAISCA, POEIRA, MAGIA, VERDE, OURO, ROXO, BRASA, AGUA, TOXICO, LASCA, AZUL, LARANJA, BRANCO, FIXA}
const RAMPAS := {
	FAISCA: ["f4f4f4", "ffcd75", "ffcd75", "ef7d57", "b13e53"],
	POEIRA: ["94b0c2", "566c86", "566c86", "333c57"],
	MAGIA: ["f4f4f4", "73eff7", "41a6f6", "3b5dc9", "29366f"],
	VERDE: ["f4f4f4", "a7f070", "a7f070", "38b764", "257179"],
	OURO: ["f4f4f4", "ffcd75", "ffcd75", "ef7d57"],
	ROXO: ["f4f4f4", "f4a2f4", "b13e53", "5d275d"],
	BRASA: ["ffcd75", "ef7d57", "ef7d57", "b13e53", "5d275d"],
	AGUA: ["f4f4f4", "73eff7", "41a6f6", "3b5dc9"],
	TOXICO: ["f4f4f4", "a7f070", "38b764", "257179"],
	LASCA: ["f4f4f4", "94b0c2", "566c86"],
	AZUL: ["f4f4f4", "73eff7", "41a6f6", "3b5dc9"],
	LARANJA: ["f4f4f4", "ffcd75", "ef7d57", "b13e53"],
	BRANCO: ["f4f4f4", "f4f4f4", "94b0c2"],
}
## Rampa "da cor do time" (1 = azul, 2 = laranja; 0 = monstros)
const RAMPA_TIME := {0: ROXO, 1: AZUL, 2: LARANJA}

## Grade do mapa (para as partículas quicarem no chão e nas paredes)
var grade: Array = []

var _rampas: Array[PackedColorArray] = []
var _n := 0
var _x := PackedFloat32Array()
var _y := PackedFloat32Array()
var _vx := PackedFloat32Array()
var _vy := PackedFloat32Array()
var _t := PackedFloat32Array()      # vida restante
var _tmax := PackedFloat32Array()
var _g := PackedFloat32Array()      # gravidade
var _arr := PackedFloat32Array()    # arrasto (freia com o tempo)
var _tam := PackedByteArray()
var _rampa := PackedByteArray()
var _quica := PackedByteArray()
var _cor := PackedColorArray()      # só para a rampa FIXA (pixels de sprites)
var _quadro := 0
var _imagens := {}                  # cache: textura -> Image


func _init() -> void:
	for chave in RAMPAS.size():
		var cores := PackedColorArray()
		for c in RAMPAS[chave]:
			cores.append(Color(c))
		_rampas.append(cores)
	_x.resize(MAX)
	_y.resize(MAX)
	_vx.resize(MAX)
	_vy.resize(MAX)
	_t.resize(MAX)
	_tmax.resize(MAX)
	_g.resize(MAX)
	_arr.resize(MAX)
	_tam.resize(MAX)
	_rampa.resize(MAX)
	_quica.resize(MAX)
	_cor.resize(MAX)
	z_index = 6
	material = CanvasItemMaterial.new()
	(material as CanvasItemMaterial).light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED


func quantidade() -> int:
	return _n


func emitir(pos: Vector2, vel: Vector2, vida: float, rampa: int, tam := 1, grav := 0.0,
		arrasto := 0.0, quica := false, cor := Color.WHITE) -> void:
	if _n >= MAX:
		return
	var i := _n
	_n += 1
	_x[i] = pos.x
	_y[i] = pos.y
	_vx[i] = vel.x
	_vy[i] = vel.y
	_t[i] = vida
	_tmax[i] = vida
	_g[i] = grav
	_arr[i] = arrasto
	_tam[i] = tam
	_rampa[i] = rampa
	_quica[i] = 1 if quica else 0
	_cor[i] = cor


func _solido(x: float, y: float, descendo: bool) -> bool:
	if grade.is_empty():
		return false
	var cx := int(floorf(x / TAM))
	var cy := int(floorf(y / TAM))
	if cy < 0 or cy >= grade.size() or cx < 0 or cx >= grade[cy].size():
		return false
	var v: int = grade[cy][cx]
	if v == GeradorArena.SOLIDO:
		return true
	# Plataformas finas: só seguram o que vem caindo, na parte de cima
	return v == GeradorArena.PLATAFORMA and descendo and fmod(y, TAM) < 4.0


func _process(delta: float) -> void:
	_quadro += 1
	if _n == 0:
		return
	var i := _n - 1
	while i >= 0:
		var t := _t[i] - delta
		if t <= 0.0:
			_remover(i)
			i -= 1
			continue
		_t[i] = t
		var vx := _vx[i]
		var vy := _vy[i] + _g[i] * delta
		var a := _arr[i]
		if a > 0.0:
			var f := maxf(0.0, 1.0 - a * delta)
			vx *= f
			vy *= f
		var x := _x[i]
		var y := _y[i]
		var nx := x + vx * delta
		var ny := y + vy * delta
		if _quica[i] == 1:
			if _solido(nx, y, false):
				vx = -vx * 0.45
				nx = x
			if _solido(nx, ny, vy > 0.0):
				ny = y
				vx *= 0.7
				vy = -vy * 0.4 if absf(vy) > 30.0 else 0.0
		_x[i] = nx
		_y[i] = ny
		_vx[i] = vx
		_vy[i] = vy
		i -= 1
	queue_redraw()


func _remover(i: int) -> void:
	_n -= 1
	var u := _n
	if i == u:
		return
	_x[i] = _x[u]
	_y[i] = _y[u]
	_vx[i] = _vx[u]
	_vy[i] = _vy[u]
	_t[i] = _t[u]
	_tmax[i] = _tmax[u]
	_g[i] = _g[u]
	_arr[i] = _arr[u]
	_tam[i] = _tam[u]
	_rampa[i] = _rampa[u]
	_quica[i] = _quica[u]
	_cor[i] = _cor[u]


func _draw() -> void:
	for i in _n:
		var resta := _t[i] / _tmax[i]
		# Pisca no finalzinho em vez de ficar transparente
		if resta < 0.18 and (_quadro + i) % 2 == 0:
			continue
		var cor: Color
		var r := _rampa[i]
		if r == FIXA:
			cor = _cor[i]
		else:
			var cores := _rampas[r]
			cor = cores[mini(int((1.0 - resta) * cores.size()), cores.size() - 1)]
		var tam := float(_tam[i])
		if tam > 1.0 and resta < 0.35:
			tam -= 1.0
		draw_rect(Rect2(floorf(_x[i]), floorf(_y[i]), tam, tam), cor)


# ------------------------------------------------------------------ Efeitos prontos

func _leque(pos: Vector2, qtd: int, angulo: float, abertura: float, vmin: float, vmax: float,
		vida: float, rampa: int, tam := 1, grav := 0.0, arrasto := 0.0, quica := false) -> void:
	for i in qtd:
		var ang := angulo + randf_range(-abertura, abertura)
		var vel := Vector2.from_angle(ang) * randf_range(vmin, vmax)
		emitir(pos, vel, vida * randf_range(0.6, 1.0), rampa, tam, grav, arrasto, quica)


func _anel(pos: Vector2, qtd: int, vel: float, vida: float, rampa: int, tam := 1, arrasto := 3.0) -> void:
	var fase := randf() * TAU
	for i in qtd:
		var ang := fase + TAU * i / qtd
		emitir(pos, Vector2.from_angle(ang) * vel, vida, rampa, tam, 0.0, arrasto)


func fx(nome: String, pos: Vector2, a = 0.0, b = 0.0) -> void:
	## Efeitos nomeados (o anfitrião manda o nome pela rede e o convidado repete).
	match nome:
		"acerto":
			# a = ângulo do golpe, b = dano (mais dano, mais faíscas)
			var forca := clampf(float(b) / 12.0, 0.4, 2.2)
			_leque(pos, int(4 + 5 * forca), a, 0.9, 40.0, 70.0 + 50.0 * forca, 0.36, FAISCA, 2, 260.0, 1.5, true)
			_leque(pos, int(2 + 2 * forca), a, 0.4, 20.0, 50.0, 0.22, BRANCO, 2, 0.0, 4.0)
		"faisca_escudo":
			# escudo do Guarda real barrou o golpe (a = ângulo de quem bateu)
			_leque(pos, 6, a, 0.6, 40.0, 100.0, 0.3, FAISCA, 2, 200.0, 1.5, true)
			_leque(pos, 3, a, 0.3, 20.0, 50.0, 0.18, BRANCO, 2, 0.0, 4.0)
		"acerto_time":
			# pixels da cor de quem apanhou (a = ângulo, b = time)
			_leque(pos, 5, a, 0.7, 40.0, 110.0, 0.45, RAMPA_TIME.get(int(b), ROXO), 1, 320.0, 0.5, true)
		"golpe":
			# arco do golpe corpo a corpo (a = lado: -1 ou 1)
			for i in 9:
				var ang := lerpf(-1.1, 1.1, i / 8.0)
				var dir := Vector2(float(a) * cos(ang), sin(ang))
				emitir(pos + dir * 7.0, dir * randf_range(30.0, 70.0), randf_range(0.12, 0.22), BRANCO, 2 if i % 2 == 0 else 1, 0.0, 5.0)
		"pulo":
			for lado in [-1.0, 1.0]:
				_leque(pos, 3, 0.0 if lado > 0.0 else PI, 0.3, 14.0, 34.0, 0.26, POEIRA, 1, -20.0, 3.0)
		"dash":
			# a = sentido do dash: a poeira sai para trás
			_leque(pos, 6, 0.0 if float(a) < 0.0 else PI, 0.35, 20.0, 70.0, 0.24, POEIRA, 1, -10.0, 3.0)
		"pouso":
			# a = velocidade da queda
			var forca := clampf(float(a) / 240.0, 0.5, 1.8)
			for lado in [-1.0, 1.0]:
				_leque(pos, int(2 + 3 * forca), (-0.25 if lado > 0.0 else PI + 0.25), 0.3, 20.0, 40.0 + 30.0 * forca, 0.34, POEIRA, 2 if forca > 1.0 else 1, -30.0, 3.5)
		"pouso_pesado":
			for lado in [-1.0, 1.0]:
				_leque(pos, 9, (-0.3 if lado > 0.0 else PI + 0.3), 0.4, 30.0, 110.0, 0.5, POEIRA, 2, -20.0, 3.0)
				_leque(pos, 5, (-1.0 if lado > 0.0 else PI + 1.0), 0.4, 60.0, 130.0, 0.6, LASCA, 1, 420.0, 0.0, true)
		"onda_choque":
			# a = raio da onda: anel de poeira rente ao chão
			for lado in [-1.0, 1.0]:
				for i in 5:
					emitir(pos + Vector2(lado * 3.0, 0.0), Vector2(lado * (float(a) * 2.6) * randf_range(0.6, 1.0), randf_range(-14.0, -2.0)), 0.3, POEIRA, 2, 0.0, 3.0)
		"furia":
			_anel(pos, 14, 70.0, 0.35, BRASA, 2, 4.0)
		"brasa_furia":
			emitir(pos + Vector2(randf_range(-4.0, 4.0), -2.0), Vector2(randf_range(-8.0, 8.0), randf_range(-40.0, -18.0)), randf_range(0.3, 0.5), BRASA, 1, 0.0, 1.0)
		"correr":
			# a = sentido da poeira (oposto ao movimento)
			emitir(pos + Vector2(randf_range(-1.0, 1.0), 0.0), Vector2(float(a) * randf_range(8.0, 20.0), randf_range(-16.0, -4.0)), randf_range(0.2, 0.32), POEIRA, 1, 0.0, 3.0)
		"conjurar":
			_leque(pos, 6, a, 0.8, 20.0, 60.0, 0.25, MAGIA, 1, 0.0, 4.0)
		"disparo":
			_leque(pos, 3, a, 0.5, 20.0, 50.0, 0.14, BRANCO, 1, 0.0, 5.0)
		"rastro_orbe":
			# a = escala do orbe
			if (_quadro % 2) == 0:
				var raio := 4.0 * float(a)
				emitir(pos + Vector2(randf_range(-raio, raio), randf_range(-raio, raio)), Vector2(randf_range(-6.0, 6.0), randf_range(-14.0, 2.0)), randf_range(0.25, 0.45), MAGIA, 1)
		"rastro_flecha":
			if (_quadro % 3) == 0:
				emitir(pos, Vector2.ZERO, 0.12, LASCA, 1)
		"orbe_estouro":
			# a = escala do orbe (de perto estoura maior)
			var e := clampf(float(a), 0.5, 1.3)
			_anel(pos, int(10 * e) + 6, 70.0 + 50.0 * e, 0.3, MAGIA, 2, 4.0)
			_leque(pos, int(10 * e), 0.0, PI, 20.0, 90.0, 0.5, MAGIA, 1, 60.0, 2.0, true)
		"orbe_some":
			_leque(pos, 6, 0.0, PI, 8.0, 30.0, 0.3, MAGIA, 1, 0.0, 3.0)
		"flecha_quebra":
			# a = ângulo da flecha: as lascas voltam para trás
			_leque(pos, 5, float(a) + PI, 0.8, 30.0, 90.0, 0.4, LASCA, 1, 380.0, 0.0, true)
		"invocar":
			_anel(pos + Vector2(0, 6), 10, 46.0, 0.3, ROXO, 1, 5.0)
			for i in 12:
				emitir(pos + Vector2(randf_range(-6.0, 6.0), randf_range(0.0, 8.0)), Vector2(randf_range(-6.0, 6.0), randf_range(-70.0, -25.0)), randf_range(0.3, 0.6), RAMPA_TIME.get(int(a), ROXO), 1 + i % 2, 0.0, 2.0)
		"nasce":
			for i in 10:
				emitir(pos + Vector2(randf_range(-7.0, 7.0), 6.0), Vector2(randf_range(-10.0, 10.0), randf_range(-60.0, -20.0)), randf_range(0.3, 0.55), ROXO, 1 + i % 2, 0.0, 2.5)
		"porta":
			_anel(pos, 12, 60.0, 0.3, AGUA, 1, 5.0)
			_leque(pos, 8, 0.0, PI, 10.0, 40.0, 0.5, MAGIA, 1, 0.0, 3.0)
		"nivel":
			# coluna de luz subindo (a = time)
			for i in 22:
				var x := randf_range(-7.0, 7.0)
				emitir(pos + Vector2(x, randf_range(-4.0, 8.0)), Vector2(0.0, randf_range(-120.0, -40.0)), randf_range(0.35, 0.7), VERDE, 1 + i % 2, 0.0, 1.5)
			_anel(pos + Vector2(0, 6), 12, 55.0, 0.3, VERDE, 1, 5.0)
		"classe":
			# ganhou (ou trocou de) classe: estouro grande na cor do time (a = time)
			var r: int = RAMPA_TIME.get(int(a), OURO)
			_anel(pos, 18, 120.0, 0.4, OURO, 2, 4.0)
			_anel(pos, 14, 70.0, 0.5, r, 2, 3.0)
			_leque(pos, 24, -PI / 2.0, 1.2, 60.0, 170.0, 0.8, r, 1, 340.0, 0.5, true)
			_leque(pos, 12, -PI / 2.0, 0.9, 40.0, 120.0, 0.7, OURO, 1, 300.0, 0.5, true)
		"melhoria":
			_anel(pos, 10, 60.0, 0.3, OURO, 1, 5.0)
			_leque(pos, 8, -PI / 2.0, 0.6, 40.0, 90.0, 0.45, OURO, 1, 200.0, 1.0)
		"item":
			_anel(pos, 14, 80.0, 0.35, ROXO, 2, 4.5)
			_leque(pos, 12, -PI / 2.0, PI, 30.0, 90.0, 0.55, ROXO, 1, 120.0, 1.5, true)
		"cura":
			for i in 6:
				emitir(pos + Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 6.0)), Vector2(0.0, randf_range(-40.0, -18.0)), randf_range(0.35, 0.6), VERDE, 1, 0.0, 1.0)
		"brasa":
			emitir(pos + Vector2(randf_range(-2.0, 2.0), 0.0), Vector2(randf_range(-7.0, 7.0), randf_range(-26.0, -12.0)), randf_range(0.6, 1.3), BRASA, 1, -6.0, 0.6)
		"pingo":
			for i in 5:
				emitir(pos, Vector2(randf_range(-34.0, 34.0), randf_range(-70.0, -30.0)), randf_range(0.2, 0.34), AGUA, 1, 380.0)
		"bolha":
			emitir(pos, Vector2(randf_range(-5.0, 5.0), randf_range(-26.0, -10.0)), randf_range(0.5, 1.1), TOXICO, 1 + randi() % 2, 0.0, 0.8)
		"veneno":
			_leque(pos, 4, -PI / 2.0, 0.8, 14.0, 40.0, 0.4, TOXICO, 1, 0.0, 2.0)
		"porta_fecha":
			_leque(pos, 10, PI / 2.0, 1.2, 20.0, 80.0, 0.5, POEIRA, 1 + randi() % 2, 300.0, 0.5, true)
		"confete":
			# a = time vencedor
			var r2: int = RAMPA_TIME.get(int(a), OURO)
			for i in 3:
				emitir(pos, Vector2(randf_range(-30.0, 30.0), randf_range(-150.0, -70.0)), randf_range(0.8, 1.4), r2 if i > 0 else OURO, 1 + i % 2, 260.0, 0.8, true)


func estilhacar(tex: Texture2D, regiao: Rect2i, pos: Vector2, espelhar: bool, escala := 1.0,
		impulso := Vector2.ZERO, passo := 1) -> void:
	## Desfaz um sprite em pixels das próprias cores (morte de personagem ou monstro).
	## `pos` é o centro do sprite; `passo` 2 usa um pixel sim, um não.
	if tex == null:
		return
	var img: Image = _imagens.get(tex)
	if img == null:
		img = tex.get_image()
		if img == null:
			return
		if img.is_compressed():
			img.decompress()
		_imagens[tex] = img
	var meio := Vector2(regiao.size) / 2.0
	for py in range(0, regiao.size.y, passo):
		for px in range(0, regiao.size.x, passo):
			var cor := img.get_pixel(regiao.position.x + px, regiao.position.y + py)
			if cor.a < 0.5:
				continue
			var rel := Vector2(px, py) - meio
			if espelhar:
				rel.x = -rel.x - 1.0
			var vel := rel.normalized() * randf_range(15.0, 70.0) + impulso * randf_range(0.5, 1.0)
			vel.y -= randf_range(30.0, 90.0)
			emitir(pos + rel * escala, vel, randf_range(0.7, 1.5), FIXA, 2 if escala > 1.2 else 1, 420.0, 0.3, true, Color(cor, 1.0))
