class_name Torre
extends Node
## Controlador da Torre da Tormenta (modo single player): guarda o que passa de
## uma luta para a seguinte e decide o que vem depois.
##
## Subida: 5 andares (1 = Recruta x Recruta; 2 a 5 = as 4 classes em ordem
## aleatória). Etapa final: 4 andares com as 4 classes em outra ordem. O
## jogador só usa o personagem escolhido; a CPU de cada andar >= 2 tem sempre
## o nível do jogador + 1. Quem monta a partida é o main.gd (config_andar) e
## quem devolve o resultado também (registrar).

const ANDARES_SUBIDA := 5
const ANDARES := 9
const TEMPO_LUTA := 90.0
## Vida máxima recuperada ao vencer um andar da subida
const CURA_VITORIA := 0.3
## Vida máxima recuperada ao entrar na etapa final (soma com a do andar 5)
const CURA_ETAPA_FINAL := 0.5
const NOMES_DIFICULDADE := ["NORMAL", "DIFÍCIL", "MUITO DIFÍCIL"]
const DIFICULDADES_BOT := [
	ControleBot.Dificuldade.NORMAL, ControleBot.Dificuldade.DIFICIL, ControleBot.Dificuldade.MUITO_DIFICIL,
]

var personagem := 0        ## índice em Jogo.CLASSES
var dificuldade := 0       ## 0 normal, 1 difícil, 2 muito difícil
## "andar" (próxima luta), "game_over" ou "campeao"
var estado := "andar"
var andar := 1             ## 1 a 9
## Classe do adversário de cada andar (índice em Jogo.CLASSES; -1 = Recruta no andar 1)
var ordem: Array[int] = []
## Estado do jogador entre as lutas (ver Lutador.exportar_estado) + "pendente":
## ganhou uma melhoria no andar anterior e ainda vai escolher.
var jogador := {}
# Estatísticas acumuladas
var tempo_total := 0.0
var dano_causado := 0.0
var dano_recebido := 0.0
var maior_golpe := 0.0
var abates := 0
## Fim da torre: nível e melhorias com que o jogador terminou
var nivel_final := 1
var melhorias_finais: Array[String] = []
var andar_alcancado := 1
var desbloqueou_agora := false

var _rng := RandomNumberGenerator.new()


func comecar(p_personagem: int, p_dificuldade: int, semente := -1) -> void:
	personagem = p_personagem
	dificuldade = p_dificuldade
	if semente < 0:
		_rng.randomize()
	else:
		_rng.seed = semente
	estado = "andar"
	andar = 1
	jogador = {"classe": -1, "nivel": 1, "historico": [], "vida": 1.0}
	tempo_total = 0.0
	dano_causado = 0.0
	dano_recebido = 0.0
	maior_golpe = 0.0
	abates = 0
	nivel_final = 1
	melhorias_finais = []
	andar_alcancado = 1
	desbloqueou_agora = false
	ordem = [-1]
	ordem.append_array(_embaralhar_classes())
	ordem.append_array(_embaralhar_classes())


func _embaralhar_classes() -> Array[int]:
	var r: Array[int] = []
	for i in Jogo.CLASSES.size():
		r.append(i)
	for i in range(r.size() - 1, 0, -1):  # Fisher-Yates com o sorteio da torre (semente fixa nos testes)
		var j := _rng.randi_range(0, i)
		var t := r[i]
		r[i] = r[j]
		r[j] = t
	return r


func e_final() -> bool:
	return andar > ANDARES_SUBIDA


func nome_personagem() -> String:
	return Jogo.dados_classe(personagem).nome


func nome_dificuldade() -> String:
	return NOMES_DIFICULDADE[dificuldade]


func config_andar() -> Dictionary:
	## Config para Partida.iniciar com o andar atual (mapa novo a cada andar).
	var cpu := {
		"classe": ordem[andar - 1], "nivel": 1, "vida": 1.0,
		"dif": DIFICULDADES_BOT[dificuldade],
	}
	if andar >= 2:
		cpu["nivel"] = int(jogador["nivel"]) + 1
		cpu["auto_melhorias"] = maxi(0, int(cpu["nivel"]) - 2)
	var adversario := "Recruta" if ordem[andar - 1] < 0 else Jogo.dados_classe(ordem[andar - 1]).nome
	return {
		"semente": _rng.randi(),
		"tempo": TEMPO_LUTA,
		"bots": {1: -1, 2: DIFICULDADES_BOT[dificuldade]},
		"itens": false, "monstros": false, "morte_subita": false, "regen": false, "xp": false,
		"lutadores": {1: jogador.duplicate(true), 2: cpu},
		"torre": {
			"andar": andar, "final": e_final(), "tempo": TEMPO_LUTA,
			"adversario": adversario, "nivel_adversario": cpu["nivel"],
		},
	}


func registrar(vencedor: int, p: Node) -> void:
	## Resultado da luta do andar atual: soma as estatísticas e avança (ou termina).
	## Empate (vencedor 0) conta como derrota.
	var eu: Lutador = p.jogadores[1]
	var cpu: Lutador = p.jogadores[2]
	tempo_total += TEMPO_LUTA - p.tempo_restante
	dano_causado += eu.dano_causado
	dano_recebido += eu.dano_recebido
	maior_golpe = maxf(maior_golpe, eu.maior_golpe)
	andar_alcancado = andar
	if vencedor != 1:
		estado = "game_over"
		_guardar_final(eu)
		return
	if not cpu.vivo:
		abates += 1
	if andar >= ANDARES:
		estado = "campeao"
		_guardar_final(eu)
		var classe: String = Jogo.CLASSES[personagem]
		if not Jogo.torre_muito_dificil(classe):
			Jogo.desbloquear_torre_muito_dificil(classe)
			desbloqueou_agora = true
		return
	jogador = eu.exportar_estado()
	if not e_final():
		_subir_de_nivel()
	andar += 1


func _subir_de_nivel() -> void:
	## Vitória na subida: +1 nível, cura e (do andar 2 em diante) uma melhoria a escolher.
	jogador["nivel"] = int(jogador["nivel"]) + 1
	var cura := CURA_VITORIA
	if andar == 1:
		jogador["classe"] = personagem  # o Recruta vira o personagem, sem melhoria
	else:
		jogador["pendente"] = true
	if andar == ANDARES_SUBIDA:
		cura = CURA_ETAPA_FINAL  # antes da etapa final: só os 50% (não soma com os 30%)
	jogador["vida"] = minf(float(jogador["vida"]) + cura, 1.0)


func _guardar_final(eu: Lutador) -> void:
	nivel_final = eu.nivel
	melhorias_finais.clear()
	for id in eu.historico:
		melhorias_finais.append(Melhorias.por_id(id)["nome"])
