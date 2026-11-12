class_name Lutador
extends CharacterBody2D
## Personagem de um jogador (humano ou bot). Começa como Recruta, ganha uma
## classe sorteada no nível 2 e melhorias nos níveis seguintes. Anda, pula e
## ataca sozinho quando um inimigo entra no alcance.

signal morreu(lutador: Lutador)

const GRAVIDADE := 700.0
const QUEDA_MAX := 360.0
const TEMPO_COYOTE := 0.1
const TEMPO_BUFFER := 0.12
## XP que o Recruta precisa para ganhar a classe (~3 monstros iniciais)
const XP_PARA_CLASSE := 16
## Regeneração fora de combate: depois de REGEN_ESPERA s sem tomar dano,
## recupera REGEN_TAXA da vida máxima por segundo.
const REGEN_ESPERA := 5.0
const REGEN_TAXA := 0.03
const QUADROS := {
	"parado": [0, 1],
	"correr": [2, 3, 4, 5],
	"pulo": [6],
	"queda": [7],
}

@onready var sprite: Sprite2D = $Sprite2D

var numero := 1
var equipe := 1
var dados: ClasseDados
var partida: Node
var controle: Controle
var eh_recruta := true

# Atributos atuais (começam iguais aos da classe e crescem com as melhorias)
var vida_max := 100.0
var vida := 100.0
var velocidade := 80.0
var forca_pulo := 290.0
var dano := 10.0
var alcance := 100.0
var intervalo := 1.0
var velocidade_projetil := 200.0
var max_lacaios := 0
var mult_lacaio := 1.0
var flechas_extra := 0
var roubo_vida := 0.0
var raio_explosao := 0.0

var nivel := 1
var xp := 0
## Fila de escolhas de melhoria pendentes; cada item é [opção1, opção2].
var escolhas: Array = []

var vivo := true
## Fica false durante a contagem regressiva e depois do fim da partida.
var ativo := false
var cooldown_porta := 0.0

var _cd_ataque := 0.6
var _coyote := 0.0
var _buffer := 0.0
var _descer := 0.0
var _anim := "parado"
var _anim_t := 0.0
var _flash := 0.0
var _sem_dano := 0.0


func configurar(n: int, d: ClasseDados, p: Node, c: Controle) -> void:
	numero = n
	equipe = n
	partida = p
	controle = c
	_aplicar_classe(d)


func _aplicar_classe(d: ClasseDados) -> void:
	var proporcao := vida / vida_max if dados != null else 1.0
	dados = d
	vida_max = d.vida_max
	vida = vida_max * proporcao
	velocidade = d.velocidade
	forca_pulo = d.forca_pulo
	dano = d.dano
	alcance = d.alcance
	intervalo = d.intervalo_ataque
	velocidade_projetil = d.velocidade_projetil
	max_lacaios = d.max_lacaios
	if sprite != null:
		sprite.texture = d.textura_p1 if numero == 1 else d.textura_p2


func receber_classe(d: ClasseDados) -> void:
	## Recruta vira uma classe (chamado pela partida no nível 2).
	eh_recruta = false
	_aplicar_classe(d)
	curar(vida_max * 0.25)
	_cd_ataque = 0.4


func nome_jogador() -> String:
	## "VOCÊ" e "CPU" no modo solo; "P1" e "P2" no multijogador.
	if controle is ControleBot:
		return "CPU"
	return "VOCÊ" if Jogo.solo else "P%d" % numero


func _ready() -> void:
	add_to_group("alvo")
	add_to_group("viajante")
	sprite.texture = dados.textura_p1 if numero == 1 else dados.textura_p2
	sprite.flip_h = numero == 2


func _physics_process(delta: float) -> void:
	if not vivo:
		return

	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVIDADE * dados.mult_gravidade * delta, QUEDA_MAX)
		_coyote -= delta
	else:
		_coyote = TEMPO_COYOTE

	var dir := 0.0
	if ativo:
		controle.atualizar(self, delta)
		dir = controle.eixo
		_buffer -= delta
		if controle.pulo_apertou:
			_buffer = TEMPO_BUFFER
		if _buffer > 0.0 and _coyote > 0.0:
			velocity.y = -forca_pulo
			_buffer = 0.0
			_coyote = 0.0
			Jogo.tocar("pulo")
		if controle.pulo_soltou and velocity.y < 0.0:
			velocity.y *= 0.5
		if controle.descer_apertou and is_on_floor():
			_atravessar_plataforma()
		_ler_escolhas()

	if _descer > 0.0:
		_descer -= delta
		if _descer <= 0.0:
			set_collision_mask_value(5, true)

	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * velocidade, dados.aceleracao * delta)
		sprite.flip_h = dir < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, dados.atrito * delta)

	var estava_no_ar := not is_on_floor()
	var queda := velocity.y
	move_and_slide()
	if estava_no_ar and is_on_floor() and queda > 200.0 and dados.pouso_pesado:
		partida.tremer(clampf(queda / 150.0, 1.0, 2.5))
		partida.criar_poeira(position + Vector2(0, 8))
	_animar(delta)

	if ativo:
		_cd_ataque -= delta
		if _cd_ataque <= 0.0:
			_tentar_atacar()

	_sem_dano += delta
	if _sem_dano > REGEN_ESPERA and vida < vida_max and not partida.morte_subita:
		curar(vida_max * REGEN_TAXA * delta)

	if _flash > 0.0:
		_flash -= delta
	sprite.modulate = Color(1, 0.35, 0.35) if _flash > 0.0 else Color.WHITE
	queue_redraw()


func _atravessar_plataforma() -> void:
	_descer = 0.25
	set_collision_mask_value(5, false)
	velocity.y = 40.0


# ------------------------------------------------------------------ Combate

func _tentar_atacar() -> void:
	if dados.tipo_ataque == ClasseDados.TipoAtaque.INVOCAR:
		if partida.contar_lacaios(self) < max_lacaios:
			partida.criar_lacaio(self)
			_cd_ataque = intervalo
		else:
			_cd_ataque = 0.3
		return

	var alvo = _escolher_alvo()
	if alvo == null:
		_cd_ataque = 0.05
		return
	_cd_ataque = intervalo
	var dir_alvo: Vector2 = (alvo.global_position - global_position).normalized()
	if absf(velocity.x) < 5.0:
		sprite.flip_h = dir_alvo.x < 0.0
	_investida(dir_alvo.x)

	match dados.tipo_ataque:
		ClasseDados.TipoAtaque.FLECHA:
			var n := 1 + flechas_extra
			for i in n:
				var ang := (i - (n - 1) / 2.0) * 0.12
				partida.criar_projetil(self, global_position, dir_alvo.rotated(ang) * velocidade_projetil,
						dano, alcance * 1.5, false)
			Jogo.tocar("flecha")
		ClasseDados.TipoAtaque.CORPO_A_CORPO:
			_golpear(dir_alvo.x)
		ClasseDados.TipoAtaque.MAGIA:
			partida.criar_projetil(self, global_position + dir_alvo * 4.0, dir_alvo * velocidade_projetil,
					dano, alcance * 1.3, true)
			Jogo.tocar("magia")


func _escolher_alvo():
	## Inimigo mais próximo dentro do alcance. Com classe, o jogador inimigo
	## tem prioridade; o Recruta prefere monstros.
	var melhor = null
	var melhor_d := INF
	var corpo_a_corpo := dados.tipo_ataque == ClasseDados.TipoAtaque.CORPO_A_CORPO
	for a in get_tree().get_nodes_in_group("alvo"):
		if a == self or not Jogo.hostis(self, a) or not a.esta_vivo():
			continue
		var dif: Vector2 = a.global_position - global_position
		var d := dif.length()
		if d > alcance + (6.0 if corpo_a_corpo else 0.0):
			continue
		if corpo_a_corpo and absf(dif.y) > 18.0:
			continue
		if not corpo_a_corpo and not _linha_livre(a.global_position):
			continue
		if a is Lutador:
			d *= 3.0 if eh_recruta else 0.6
		if d < melhor_d:
			melhor_d = d
			melhor = a
	return melhor


func _linha_livre(destino: Vector2) -> bool:
	var consulta := PhysicsRayQueryParameters2D.create(global_position, destino, 1)
	return get_world_2d().direct_space_state.intersect_ray(consulta).is_empty()


func _golpear(lado: float) -> void:
	var s := signf(lado) if lado != 0.0 else (-1.0 if sprite.flip_h else 1.0)
	for a in get_tree().get_nodes_in_group("alvo"):
		if a == self or not Jogo.hostis(self, a) or not a.esta_vivo():
			continue
		var dif: Vector2 = a.global_position - global_position
		if absf(dif.y) <= 18.0 and dif.x * s >= -6.0 and absf(dif.x) <= alcance + 6.0:
			causar_dano(a, dano)
	partida.criar_corte(global_position + Vector2(s * 12.0, 0.0), s < 0.0)
	Jogo.tocar("espada")


func causar_dano(alvo, qtd: float) -> void:
	alvo.receber_dano(qtd, self)
	if roubo_vida > 0.0:
		curar(qtd * roubo_vida)


func _investida(lado: float) -> void:
	var tw := create_tween()
	tw.tween_property(sprite, "position:x", signf(lado) * 2.0, 0.05)
	tw.tween_property(sprite, "position:x", 0.0, 0.1)


func receber_dano(qtd: float, origem) -> void:
	if not vivo:
		return
	var origem_valida: bool = origem != null and is_instance_valid(origem)
	# Dano entre jogadores passa pelas regras da partida (Recruta, PvP, morte súbita)
	if origem_valida and origem is Lutador and origem != self:
		qtd *= partida.mult_pvp(origem, self)
	if qtd <= 0.0:
		return
	vida -= qtd
	_sem_dano = 0.0
	_flash = 0.12
	Jogo.tocar("acerto")
	var texto := str(roundi(qtd)) if qtd >= 1.0 else "%.1f" % qtd
	partida.mostrar_texto(global_position + Vector2(0, -12), texto, Color("ffcd75"))
	if origem_valida:
		var empurrao := 70.0 * (1.0 - dados.resistencia_empurrao)
		velocity.x += signf(global_position.x - origem.global_position.x) * empurrao
	if vida <= 0.0:
		vida = 0.0
		_morrer()


func curar(qtd: float) -> void:
	vida = minf(vida + qtd, vida_max)


func _morrer() -> void:
	vivo = false
	ativo = false
	remove_from_group("viajante")
	Jogo.tocar("morte")
	sprite.frame = 7
	var tw := create_tween()
	tw.tween_property(sprite, "rotation", PI * 0.5 * (-1.0 if sprite.flip_h else 1.0), 0.3)
	tw.parallel().tween_property(sprite, "position:y", 4.0, 0.3)
	tw.tween_property(sprite, "modulate:a", 0.3, 0.6)
	queue_redraw()
	morreu.emit(self)


func esta_vivo() -> bool:
	return vivo


func hitbox() -> Rect2:
	return Rect2(global_position + Vector2(-5, -6), Vector2(10, 14))


# ------------------------------------------------------------------ Experiência

func xp_para_proximo() -> int:
	if eh_recruta:
		return XP_PARA_CLASSE
	return 4 + nivel * 2


func ganhar_xp(qtd: int) -> void:
	if not vivo:
		return
	# Quem está atrás em nível ganha 50% a mais (ajuda a alcançar o oponente)
	var outro: Lutador = partida.oponente(self)
	if outro.nivel > nivel:
		qtd = ceili(qtd * 1.5)
	xp += qtd
	while xp >= xp_para_proximo():
		xp -= xp_para_proximo()
		nivel += 1
		curar(vida_max * 0.15)
		Jogo.tocar("nivel")
		if eh_recruta:
			partida.sortear_classe(self)
		else:
			escolhas.append(Melhorias.sortear(self))
			partida.mostrar_texto(global_position + Vector2(0, -20), "NÍVEL %d!" % nivel, Color("a7f070"))


func _ler_escolhas() -> void:
	if escolhas.is_empty() or controle.opcao < 0:
		return
	var par: Array = escolhas.pop_front()
	var m: Dictionary = par[controle.opcao]
	Melhorias.aplicar(self, m)
	partida.mostrar_texto(global_position + Vector2(0, -20), m["nome"], Color.WHITE)


# ------------------------------------------------------------------ Visual

func _animar(delta: float) -> void:
	var nova := "parado"
	if not is_on_floor():
		nova = "pulo" if velocity.y < 0.0 else "queda"
	elif absf(velocity.x) > 10.0:
		nova = "correr"
	if nova != _anim:
		_anim = nova
		_anim_t = 0.0
	_anim_t += delta
	var quadros: Array = QUADROS[_anim]
	var fps := 10.0 if _anim == "correr" else 2.0
	sprite.frame = quadros[int(_anim_t * fps) % quadros.size()]


func _draw() -> void:
	if not vivo:
		return
	var cor: Color = Jogo.COR_TIME[equipe]
	# Rótulo ("VOCÊ", "CPU", "P1"...), seta e barra de vida acima da cabeça
	var fonte := ThemeDB.fallback_font
	var rotulo := nome_jogador()
	var larg := fonte.get_string_size(rotulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	var pos := Vector2(-larg / 2.0, -21)
	draw_string_outline(fonte, pos, rotulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, 3, Color("1a1c2c"))
	draw_string(fonte, pos, rotulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, cor)
	draw_colored_polygon(PackedVector2Array([Vector2(-3, -19), Vector2(3, -19), Vector2(0, -16)]), cor)
	draw_rect(Rect2(-8, -14, 16, 3), Color("1a1c2c"))
	draw_rect(Rect2(-7, -13, 14.0 * vida / vida_max, 1), cor)
