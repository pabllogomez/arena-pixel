class_name Melhorias
extends RefCounted
## Melhorias oferecidas ao subir de nível (o jogador escolhe 1 de 2).

const GERAIS := [
	{"id": "forca", "nome": "Força", "desc": "+20% de dano"},
	{"id": "vigor", "nome": "Vigor", "desc": "+25 de vida máx."},
	{"id": "frenesi", "nome": "Frenesi", "desc": "ataca 15% mais rápido"},
	{"id": "alcance", "nome": "Mira", "desc": "+15% de alcance"},
	{"id": "agilidade", "nome": "Agilidade", "desc": "+10% de velocidade"},
]

const ESPECIAIS := {
	ClasseDados.TipoAtaque.FLECHA: {"id": "multi", "nome": "Chuva", "desc": "+1 flecha por tiro"},
	ClasseDados.TipoAtaque.CORPO_A_CORPO: {"id": "sangue", "nome": "Sede de sangue", "desc": "cura 20% do dano"},
	ClasseDados.TipoAtaque.MAGIA: {"id": "explosao", "nome": "Explosão", "desc": "orbe explode em área"},
	ClasseDados.TipoAtaque.INVOCAR: {"id": "exercito", "nome": "Exército", "desc": "+1 lacaio, +25% força"},
}


static func sortear(l) -> Array:
	var tipo: ClasseDados.TipoAtaque = l.dados.tipo_ataque
	var opcoes: Array = []
	for m in GERAIS:
		# Para o Rei, "Frenesi" = lacaios mais frequentes; "Mira" não faz sentido.
		if m["id"] == "alcance" and tipo == ClasseDados.TipoAtaque.INVOCAR:
			continue
		opcoes.append(m)
	opcoes.append(ESPECIAIS[tipo])
	opcoes.shuffle()
	return [opcoes[0], opcoes[1]]


static func aplicar(l, m: Dictionary) -> void:
	match m["id"]:
		"forca":
			l.dano *= 1.2
		"vigor":
			l.vida_max += 25.0
			l.curar(25.0)
		"frenesi":
			l.intervalo *= 0.85
		"alcance":
			l.alcance *= 1.15
		"agilidade":
			l.velocidade *= 1.1
			l.forca_pulo *= 1.03
		"multi":
			l.flechas_extra += 1
		"sangue":
			l.roubo_vida += 0.2
		"explosao":
			l.raio_explosao += 20.0
		"exercito":
			l.max_lacaios += 1
			l.mult_lacaio *= 1.25
