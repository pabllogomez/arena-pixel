class_name Torre
extends Node
## Controlador da Torre da Tormenta (modo single player): guarda o que passa de
## uma luta para a seguinte e decide o que vem depois.
##
## Subida: 4 andares (1 a 3 = as outras 3 classes em ordem aleatória; 4 = luta
## espelhada, a mesma classe do jogador). Etapa final (andar 5): UMA luta de 4:00
## contra as 4 classes em sequência, em ordem aleatória, na mesma arena. O jogador
## só usa o personagem escolhido e começa no nível 2; a CPU tem sempre o MESMO
## nível do jogador (e as melhorias desse nível), de vida cheia. Quem monta a
## partida é o main.gd (config_andar) e quem devolve o resultado também (registrar).

const ANDARES_SUBIDA := 4
const ANDARES := 5
const ADVERSARIOS_FINAL := 4
const NIVEL_INICIAL := 2   ## nível de quem acabou de ganhar a classe
const TEMPO_LUTA := 90.0
const TEMPO_FINAL := 240.0
## Vida máxima recuperada ao vencer um andar da subida
const CURA_VITORIA := 0.3
## Vida máxima recuperada ao entrar na etapa final (no lugar dos 30% do andar 4)
const CURA_ETAPA_FINAL := 0.5
const NOMES_DIFICULDADE := ["NORMAL", "DIFÍCIL", "INSANO"]
## Bot da CPU por dificuldade da torre (INSANO = o Difícil "cheio")
const DIFICULDADES_BOT := [
	ControleBot.Dificuldade.NORMAL, ControleBot.Dificuldade.DIFICIL, ControleBot.Dificuldade.DIFICIL,
]
## Ajuste da CPU por dificuldade: NORMAL = -1 nível, DIFÍCIL = -0,5 nível, INSANO = sem ajuste.
## `atributos` multiplica vida, velocidade e dano (inclusive lacaios); `reacao` e `erro`
## deixam o bot um pouco menos esperto (reação mais lenta, mais erros).
const AJUSTE_CPU := [
	{"atributos": 0.90, "reacao": 1.3, "erro": 0.03},
	{"atributos": 0.95, "reacao": 1.15, "erro": 0.015},
	{},
]

var personagem := 0        ## índice em Jogo.CLASSES
var dificuldade := 0       ## 0 normal, 1 difícil, 2 insano
## "andar" (próxima luta), "game_over" ou "campeao"
var estado := "andar"
var andar := 1             ## 1 a 5 (5 = etapa final)
## Classe do adversário de cada andar da subida (índice em Jogo.CLASSES)
var ordem: Array[int] = []
## Classes dos 4 adversários da etapa final, na ordem em que entram
var ordem_final: Array[int] = []
## Estado do jogador entre as lutas (ver Lutador.exportar_estado) + "pendente":
## ganhou uma melhoria no andar anterior e ainda vai escolher.
var jogador := {}
# Estatísticas acumuladas
var tempo_total := 0.0
var dano_causado := 0.0
var dano_recebido := 0.0
var maior_golpe := 0.0
var abates := 0
## Adversários derrotados na etapa final (para a tela de fim)
var derrotados_final := 0
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
	jogador = {"classe": personagem, "nivel": NIVEL_INICIAL, "historico": [], "vida": 1.0}
	tempo_total = 0.0
	dano_causado = 0.0
	dano_recebido = 0.0
	maior_golpe = 0.0
	abates = 0
	nivel_final = NIVEL_INICIAL
	derrotados_final = 0
	melhorias_finais = []
	andar_alcancado = 1
	desbloqueou_agora = false
	# Subida: as outras 3 classes em ordem aleatória e a luta espelhada (a mesma
	# classe do jogador) sempre por último, no andar 4, antes da etapa final.
	ordem = _embaralhar_classes()
	ordem.erase(personagem)
	ordem.append(personagem)
	ordem_final = _embaralhar_classes()


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


func _estado_cpu(classe: int) -> Dictionary:
	## CPU no mesmo nível do jogador, com as melhorias desse nível (sorteadas como o
	## bot escolhe) e vida cheia.
	var nivel := int(jogador["nivel"])
	return {
		"classe": classe, "nivel": nivel, "vida": 1.0,
		"dif": DIFICULDADES_BOT[dificuldade], "auto_melhorias": maxi(0, nivel - NIVEL_INICIAL),
		"ajuste": AJUSTE_CPU[dificuldade],
	}


func config_andar() -> Dictionary:
	## Config para Partida.iniciar com o andar atual (mapa novo a cada andar).
	var config := {
		"semente": _rng.randi(),
		"bots": {1: -1, 2: DIFICULDADES_BOT[dificuldade]},
		"itens": false, "monstros": false, "morte_subita": false, "xp": false,
	}
	var info := {"andar": andar, "final": e_final()}
	if e_final():
		var sequencia: Array = []
		for c in ordem_final:
			sequencia.append(_estado_cpu(c))
		config["tempo"] = TEMPO_FINAL
		config["lutadores"] = {1: jogador.duplicate(true), 2: sequencia[0]}
		config["sequencia"] = sequencia
		info["tempo"] = TEMPO_FINAL
		info["adversario"] = Jogo.dados_classe(ordem_final[0]).nome
		info["nivel_adversario"] = sequencia[0]["nivel"]
		info["adversarios"] = ADVERSARIOS_FINAL
	else:
		var cpu := _estado_cpu(ordem[andar - 1])
		config["tempo"] = TEMPO_LUTA
		config["lutadores"] = {1: jogador.duplicate(true), 2: cpu}
		info["tempo"] = TEMPO_LUTA
		info["adversario"] = Jogo.dados_classe(ordem[andar - 1]).nome
		info["nivel_adversario"] = cpu["nivel"]
	config["torre"] = info
	return config


func registrar(vencedor: int, p: Node) -> void:
	## Resultado da luta do andar atual: soma as estatísticas e avança (ou termina).
	## Empate (vencedor 0) conta como derrota.
	var eu: Lutador = p.jogadores[1]
	var cpu: Lutador = p.jogadores[2]
	tempo_total += float(p.torre["tempo"]) - p.tempo_restante
	dano_causado += eu.dano_causado
	dano_recebido += eu.dano_recebido
	maior_golpe = maxf(maior_golpe, eu.maior_golpe)
	andar_alcancado = andar
	if e_final():
		derrotados_final = p.derrotados
		abates += p.derrotados
	elif vencedor == 1 and not cpu.vivo:
		abates += 1
	if vencedor != 1:
		estado = "game_over"
		_guardar_final(eu)
		return
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
	## Vitória na subida: +1 nível, cura e uma melhoria a escolher.
	jogador["nivel"] = int(jogador["nivel"]) + 1
	jogador["pendente"] = true
	var cura := CURA_VITORIA
	if andar == ANDARES_SUBIDA:
		cura = CURA_ETAPA_FINAL  # antes da etapa final: só os 50% (não soma com os 30%)
	jogador["vida"] = minf(float(jogador["vida"]) + cura, 1.0)


func _guardar_final(eu: Lutador) -> void:
	nivel_final = eu.nivel
	melhorias_finais.clear()
	for id in eu.historico:
		melhorias_finais.append(Melhorias.por_id(id)["nome"])
