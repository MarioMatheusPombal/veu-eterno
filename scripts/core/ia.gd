class_name IA
extends RefCounted
## Oponente simples do MVP: joga Fonte, baixa a carta mais cara que conseguir pagar,
## usa o Comando quando faz sentido, ataca com tudo e bloqueia com trocas favoráveis.

## Próxima ação na Fase Principal: {"tipo": "carta"|"comando"|"reliquia"|"passar", ...}
static func proxima_acao(motor: Motor) -> Dictionary:
	var j := motor.jogador_ativo()

	# 1. Jogar Fonte, sempre que possível.
	if not j.fonte_jogada:
		for i in j.mao.size():
			if j.mao[i].get("tipo", "") == "Fonte":
				return {"tipo": "carta", "idx": i, "alvos": {}}

	# 2. Carta jogável mais cara primeiro.
	var melhor_idx := -1
	var melhor_custo := -1
	for i in j.mao.size():
		var dados: Dictionary = j.mao[i]
		if dados.get("tipo", "") == "Fonte" or motor.pode_jogar(i) != "":
			continue
		var custo: int = BancoDados.custo_total(dados.get("custo", {}))
		if custo > melhor_custo:
			melhor_custo = custo
			melhor_idx = i
	if melhor_idx >= 0:
		return {"tipo": "carta", "idx": melhor_idx,
				"alvos": escolher_alvos(motor, j.mao[melhor_idx])}

	# 3. Habilidade de Comando.
	if motor.pode_comando(j) == "" and _comando_vale_a_pena(motor, j):
		var alvos := {}
		var hc: Dictionary = j.comandante["habilidade_comando"]
		if str(hc.get("custo_adicional", "")) == "sacrificar_convocado":
			alvos["sacrificio"] = _pior_convocado(motor, j)
		return {"tipo": "comando", "alvos": alvos}

	# 4. Relíquias ativáveis.
	for inst in j.campo:
		if inst.tipo() == "Relíquia" and not inst.usada:
			var ef := motor.efeito_ativado_de(inst)
			if not ef.is_empty() and motor.pode_pagar(ef.get("custo", {}), j):
				return {"tipo": "reliquia", "inst": inst}

	return {"tipo": "passar"}

static func _comando_vale_a_pena(motor: Motor, j: Jogador) -> bool:
	match str(j.comandante["id"]):
		"ordwyn":
			return j.convocados().size() >= 2  # buff de massa precisa de massa
		"nyx":
			return j.convocados().size() >= 2  # não sacrifica o último corpo
		"sylvaine":
			# Só se existir uma carta na mão que passaria a ser pagável com +1 Essência.
			var disp: Dictionary = motor.essencia_disponivel(j)
			for dados in j.mao:
				if dados.get("tipo", "") == "Fonte":
					continue
				var custo: Dictionary = motor.custo_ajustado(dados, j)
				var total: int = BancoDados.custo_total(custo)
				if total == int(disp["total"]) + 1:
					return true
			return false
		"korrath":
			return true  # dano direto nunca é desperdício
	return true

static func escolher_alvos(motor: Motor, dados: Dictionary) -> Dictionary:
	var j := motor.jogador_ativo()
	var inimigo: Jogador = motor.jogadores[1 - j.indice]
	var alvos := {}
	if str(dados.get("custo_adicional", "")) == "sacrificar_convocado":
		alvos["sacrificio"] = _pior_convocado(motor, j)
	var valor := 0
	for ef in dados.get("efeitos", []):
		if str(ef.get("acao", "")) == "dano":
			valor = int(ef.get("valor", 0))
	match motor.requisito_alvo(dados):
		"convocado_inimigo":
			alvos["convocado"] = _melhor_alvo_de_dano(motor, inimigo, valor)
		"convocado_aliado":
			alvos["convocado"] = _melhor_convocado(motor, j)
		"convocado_qualquer":
			alvos["convocado"] = _melhor_alvo_de_dano(motor, inimigo, valor)
		"qualquer_inimigo":
			if inimigo.vida <= valor:
				alvos["comandante"] = true
			else:
				var inst = _melhor_alvo_de_dano(motor, inimigo, valor, true)
				if inst != null:
					alvos["convocado"] = inst
				else:
					alvos["comandante"] = true
		"cemiterio_convocado":
			var melhor := -1
			var melhor_custo := -1
			for i in j.cemiterio.size():
				if j.cemiterio[i].get("tipo", "") != "Convocado":
					continue
				var c: int = BancoDados.custo_total(j.cemiterio[i].get("custo", {}))
				if c > melhor_custo:
					melhor_custo = c
					melhor = i
			alvos["cemiterio_idx"] = melhor
	return alvos

## Melhor Convocado inimigo para receber `valor` de dano: o mais forte que morre com ele;
## se `so_se_mata`, retorna null quando nenhum morreria.
static func _melhor_alvo_de_dano(motor: Motor, inimigo: Jogador, valor: int, so_se_mata := false) -> Variant:
	var melhor: Variant = null
	var melhor_poder := -1
	for inst in inimigo.convocados():
		var mata: bool = valor == 0 or motor.res_de(inst) - inst.dano_marcado <= valor
		if so_se_mata and not mata:
			continue
		var nota: int = motor.poder_de(inst) + (100 if mata else 0)
		if nota > melhor_poder:
			melhor_poder = nota
			melhor = inst
	return melhor

static func _melhor_convocado(motor: Motor, j: Jogador) -> Variant:
	var melhor: Variant = null
	var melhor_poder := -1
	for inst in j.convocados():
		if motor.poder_de(inst) > melhor_poder:
			melhor_poder = motor.poder_de(inst)
			melhor = inst
	return melhor

static func _pior_convocado(motor: Motor, j: Jogador) -> Variant:
	var pior: Variant = null
	var pior_nota := 9999
	for inst in j.convocados():
		var nota := motor.poder_de(inst) + motor.res_de(inst)
		if nota < pior_nota:
			pior_nota = nota
			pior = inst
	return pior

static func escolher_atacantes(motor: Motor) -> Array:
	var lista: Array = []
	for inst in motor.atacantes_elegiveis():
		if motor.poder_de(inst) > 0:
			lista.append(inst)
	return lista

static func escolher_bloqueios(motor: Motor) -> Dictionary:
	var def := motor.defensor()
	var bloqueios := {}
	var livres: Array = def.convocados().filter(
			func(b: InstanciaCarta) -> bool: return not b.usada)
	var restantes: Array = motor.atacantes.duplicate()
	restantes.sort_custom(func(a, b): return motor.poder_de(a) > motor.poder_de(b))

	# 1. Guardas são obrigados a bloquear se puderem.
	for b in livres.duplicate():
		if not motor.tem_kw(b, "Guarda"):
			continue
		for a in restantes:
			if motor.pode_bloquear(b, a):
				bloqueios[a] = b
				livres.erase(b)
				restantes.erase(a)
				break

	# 2. Trocas favoráveis: mata o atacante e sobrevive, ou troca por algo maior.
	for a in restantes.duplicate():
		var escolhido: Variant = null
		for b in livres:
			if not motor.pode_bloquear(b, a):
				continue
			var mata: bool = motor.poder_de(b) >= motor.res_de(a)
			var sobrevive: bool = motor.res_de(b) > motor.poder_de(a)
			if mata and sobrevive:
				escolhido = b
				break
			if mata and escolhido == null and motor.poder_de(a) >= motor.poder_de(b):
				escolhido = b
		if escolhido != null:
			bloqueios[a] = escolhido
			livres.erase(escolhido)
			restantes.erase(a)

	# 3. Se o dano livre é letal, sacrifica corpos para sobreviver.
	var dano_livre := 0
	for a in restantes:
		dano_livre += motor.poder_de(a)
	if dano_livre >= def.vida:
		for a in restantes.duplicate():
			if livres.is_empty():
				break
			for b in livres:
				if motor.pode_bloquear(b, a):
					bloqueios[a] = b
					livres.erase(b)
					restantes.erase(a)
					break
	return bloqueios

static func escolher_descarte(motor: Motor) -> int:
	var j := motor.jogador_ativo()
	var pior := 0
	var pior_custo := -1
	for i in j.mao.size():
		var custo: int = BancoDados.custo_total(j.mao[i].get("custo", {}))
		if custo > pior_custo:
			pior_custo = custo
			pior = i
	return pior
