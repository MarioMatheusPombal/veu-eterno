class_name Motor
extends RefCounted
## Motor de regras do Véu Eterno (MVP): fonte da verdade é docs/game_design/02_regras_nucleo.md.
## Lógica pura, sem UI. A interface (partida.gd) e a IA conversam só por esta API.

signal registro(texto: String)
signal estado_mudou
signal partida_terminou(vencedor: int)
## Eventos para a camada de animação da UI. Tipos: "ataque" {origem, alvo_inst|alvo_jogador},
## "projetil" {origem_jogador, alvo_inst|alvo_jogador}, "dano_comandante" {jogador, valor},
## "dano_convocado" {inst, valor}, "cura" {jogador, valor}.
signal evento_visual(tipo: String, info: Dictionary)

enum Fase {PRINCIPAL_1, BLOQUEIO, PRINCIPAL_2, DESCARTE, FIM}

const LIMITE_MAO := 7
const MAO_INICIAL := 5  # não definido nos docs; decisão de implementação

var jogadores: Array = []       # 2x Jogador
var ativo := 0
var turno := 0                  # conta turnos de jogador (1 = primeiro turno do jogador inicial)
var fase: int = Fase.PRINCIPAL_1
var combate_feito := false
var atacantes: Array = []       # InstanciaCarta, definidos entre declarar_atacantes e a resolução
var rng := RandomNumberGenerator.new()  # semeado em iniciar(); mantém partidas em rede idênticas


# ---------------------------------------------------------------- preparação

func iniciar(configs: Array, semente: int = 0) -> void:
	# configs: [{"comandante": id, "eh_ia": bool}, ...] — usa o baralho pré-construído do Comandante.
	if semente == 0:
		semente = randi()
	rng.seed = semente
	for i in 2:
		var j := Jogador.new()
		j.indice = i
		j.eh_ia = bool(configs[i].get("eh_ia", false))
		j.comandante = BancoDados.comandantes[configs[i]["comandante"]]
		j.vida = int(j.comandante["vida"])
		var lista: Array = BancoDados.baralhos[configs[i]["comandante"]]["lista"].duplicate()
		_embaralhar(lista)
		for entrada in lista:
			var dados: Dictionary = BancoDados.cartas[entrada["id"]]
			if str(entrada.get("acabamento", "normal")) != "normal":
				dados = dados.duplicate()  # cópia foil/holo carrega o acabamento consigo
				dados["acabamento"] = entrada["acabamento"]
			j.baralho.append(dados)
		jogadores.append(j)
	for j in jogadores:
		for _k in MAO_INICIAL:
			j.mao.append(j.baralho.pop_back())
	_emitir("=== %s  VS  %s ===" % [jogadores[0].nome(), jogadores[1].nome()])
	ativo = 0
	_comecar_turno()


# ---------------------------------------------------------------- consultas

func jogador_ativo() -> Jogador:
	return jogadores[ativo]

func oponente() -> Jogador:
	return jogadores[1 - ativo]

func defensor() -> Jogador:
	return oponente()

func em_fase_principal() -> bool:
	return fase == Fase.PRINCIPAL_1 or fase == Fase.PRINCIPAL_2

func essencia_disponivel(j: Jogador) -> Dictionary:
	var fontes := 0
	for inst in j.campo:
		if inst.tipo() == "Fonte" and not inst.usada:
			fontes += 1
	return {"total": fontes + j.bonus_neutra + j.bonus_faccao, "faccao": fontes + j.bonus_faccao}

func custo_ajustado(dados: Dictionary, j: Jogador) -> Dictionary:
	var custo: Dictionary = dados.get("custo", {}).duplicate()
	# Passiva de Sylvaine: Convocados com Poder 5+ custam 1 a menos.
	if j.comandante["id"] == "sylvaine" and dados.get("tipo", "") == "Convocado" \
			and int(dados.get("poder", 0)) >= 5:
		custo["incolor"] = maxi(int(custo.get("incolor", 0)) - 1, 0)
	return custo

func pode_pagar(custo: Dictionary, j: Jogador) -> bool:
	var disp := essencia_disponivel(j)
	var fac := BancoDados.custo_faccao(custo)
	return int(disp["faccao"]) >= fac and int(disp["total"]) >= fac + int(custo.get("incolor", 0))

func tem_kw(inst: InstanciaCarta, kw: String) -> bool:
	if kw in inst.kw_temporarias or kw in inst.dados.get("palavras_chave", []):
		return true
	# Passiva de Korrath: Convocados de custo total 2 ou menos ganham Investida.
	if kw == "Investida" and jogadores[inst.dono].comandante["id"] == "korrath" \
			and inst.eh_convocado() and BancoDados.custo_total(inst.dados.get("custo", {})) <= 2:
		return true
	return false

func poder_de(inst: InstanciaCarta) -> int:
	if not inst.eh_convocado():
		return 0
	var p := int(inst.dados.get("poder", 0)) + inst.buff_poder_perm + inst.buff_poder_turno
	p += _bonus_de_auras(inst, "poder")
	return maxi(p, 0)

func res_de(inst: InstanciaCarta) -> int:
	if not inst.eh_convocado():
		return 0
	var r := int(inst.dados.get("resiliencia", 0)) + inst.buff_res_perm + inst.buff_res_turno
	r += _bonus_de_auras(inst, "resiliencia")
	return maxi(r, 0)

func _bonus_de_auras(inst: InstanciaCarta, atributo: String) -> int:
	var total := 0
	for fonte_aura in jogadores[inst.dono].campo:
		for ef in fonte_aura.dados.get("efeitos", []):
			if ef.get("gatilho", "") != "continua" or ef.get("acao", "") != "aura":
				continue
			if ef.get("excluir_proprio", false) and fonte_aura == inst:
				continue
			var filtro: Dictionary = ef.get("filtro", {})
			if filtro.has("subtipo") and str(inst.dados.get("subtipo", "")) != str(filtro["subtipo"]):
				continue
			total += int(ef.get(atributo, 0))
	return total

func vivo(inst: InstanciaCarta) -> bool:
	return inst in jogadores[inst.dono].campo

func _embaralhar(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var k := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[k]
		arr[k] = tmp


# ------------------------------------------------- serialização (partida em rede)

## Converte uma InstanciaCarta em referência estável [dono, índice no campo].
func ref_de(inst: InstanciaCarta) -> Array:
	return [inst.dono, jogadores[inst.dono].campo.find(inst)]

func inst_de(ref: Array) -> InstanciaCarta:
	var campo: Array = jogadores[int(ref[0])].campo
	var idx := int(ref[1])
	return campo[idx] if idx >= 0 and idx < campo.size() else null

func serializar_alvos(alvos: Dictionary) -> Dictionary:
	var d := {}
	for chave in alvos:
		d[chave] = ref_de(alvos[chave]) if alvos[chave] is InstanciaCarta else alvos[chave]
	return d

func desserializar_alvos(d: Dictionary) -> Dictionary:
	var alvos := {}
	for chave in d:
		alvos[chave] = inst_de(d[chave]) if d[chave] is Array else d[chave]
	return alvos

## Retorna o tipo de alvo que a carta/habilidade exige do jogador, ou "" se nenhum.
func requisito_alvo(dados: Dictionary) -> String:
	for ef in dados.get("efeitos", []):
		if str(ef.get("gatilho", "")) in ["imediato", "ao_entrar"]:
			var alvo := str(ef.get("alvo", ""))
			if alvo in ["convocado_inimigo", "convocado_aliado", "convocado_qualquer",
					"qualquer_inimigo", "cemiterio_convocado"]:
				return alvo
	return ""

## Erro legível se a carta da mão não pode ser jogada agora; "" se pode.
func pode_jogar(idx: int) -> String:
	if not em_fase_principal():
		return "Só é possível jogar cartas nas Fases Principais."
	var j := jogador_ativo()
	if idx < 0 or idx >= j.mao.size():
		return "Carta inválida."
	var dados: Dictionary = j.mao[idx]
	if dados.get("tipo", "") == "Fonte":
		return "Você já jogou uma Fonte neste turno." if j.fonte_jogada else ""
	if not pode_pagar(custo_ajustado(dados, j), j):
		return "Essência insuficiente."
	if str(dados.get("custo_adicional", "")) == "sacrificar_convocado" and j.convocados().is_empty():
		return "Você precisa de um Convocado aliado para sacrificar."
	if not _existe_alvo(requisito_alvo(dados), j):
		return "Nenhum alvo válido."
	return ""

func _existe_alvo(req: String, j: Jogador) -> bool:
	match req:
		"":
			return true
		"convocado_inimigo":
			return not jogadores[1 - j.indice].convocados().is_empty()
		"convocado_aliado":
			return not j.convocados().is_empty()
		"convocado_qualquer":
			return not (j.convocados().is_empty() and jogadores[1 - j.indice].convocados().is_empty())
		"qualquer_inimigo":
			return true  # o Comandante inimigo é sempre alvo válido
		"cemiterio_convocado":
			for dados in j.cemiterio:
				if dados.get("tipo", "") == "Convocado":
					return true
			return false
	return false


# ---------------------------------------------------------------- jogar cartas

## alvos: {"convocado": InstanciaCarta, "comandante": bool, "cemiterio_idx": int,
##         "sacrificio": InstanciaCarta} — só as chaves que a carta exigir.
func jogar_carta(idx: int, alvos: Dictionary = {}) -> String:
	var erro := pode_jogar(idx)
	if erro != "":
		return erro
	var j := jogador_ativo()
	var dados: Dictionary = j.mao[idx]

	if dados.get("tipo", "") == "Fonte":
		j.mao.remove_at(idx)
		j.fonte_jogada = true
		j.campo.append(InstanciaCarta.new(dados, ativo))
		evento_visual.emit("jogada", {"dados": dados, "jogador": ativo})
		_emitir("%s joga a Fonte %s." % [j.nome(), dados["nome"]])
		estado_mudou.emit()
		return ""

	erro = _validar_alvos(dados, alvos)
	if erro != "":
		return erro
	if str(dados.get("custo_adicional", "")) == "sacrificar_convocado":
		var sac: Variant = alvos.get("sacrificio")
		if sac == null or not (sac is InstanciaCarta) or sac.dono != ativo \
				or not sac.eh_convocado() or not vivo(sac):
			return "Escolha um Convocado aliado para sacrificar."

	_pagar(custo_ajustado(dados, j), j)
	j.mao.remove_at(idx)
	evento_visual.emit("jogada", {"dados": dados, "jogador": ativo})
	if alvos.has("sacrificio"):
		_emitir("%s sacrifica %s." % [j.nome(), alvos["sacrificio"].nome()])
		_destruir(alvos["sacrificio"])

	match str(dados.get("tipo", "")):
		"Convocado":
			var inst := InstanciaCarta.new(dados, ativo)
			j.campo.append(inst)
			_emitir("%s convoca %s." % [j.nome(), dados["nome"]])
			_passiva_ao_entrar(j)
			_executar_efeitos(dados, "ao_entrar", j, alvos)
		"Feitiço":
			_emitir("%s conjura %s." % [j.nome(), dados["nome"]])
			_executar_efeitos(dados, "imediato", j, alvos)
			j.cemiterio.append(dados)
		"Relíquia":
			j.campo.append(InstanciaCarta.new(dados, ativo))
			_emitir("%s coloca a Relíquia %s no Campo." % [j.nome(), dados["nome"]])
	estado_mudou.emit()
	return ""

func _validar_alvos(dados: Dictionary, alvos: Dictionary) -> String:
	var req := requisito_alvo(dados)
	if req == "":
		return ""
	var inst: Variant = alvos.get("convocado")
	match req:
		"convocado_inimigo":
			if inst == null or inst.dono == ativo or not inst.eh_convocado() or not vivo(inst):
				return "Escolha um Convocado inimigo como alvo."
		"convocado_aliado":
			if inst == null or inst.dono != ativo or not inst.eh_convocado() or not vivo(inst):
				return "Escolha um Convocado aliado como alvo."
		"convocado_qualquer":
			if inst == null or not inst.eh_convocado() or not vivo(inst):
				return "Escolha um Convocado como alvo."
		"qualquer_inimigo":
			if not bool(alvos.get("comandante", false)):
				if inst == null or inst.dono == ativo or not inst.eh_convocado() or not vivo(inst):
					return "Escolha um Convocado inimigo ou o Comandante inimigo."
		"cemiterio_convocado":
			var idx := int(alvos.get("cemiterio_idx", -1))
			var cem: Array = jogador_ativo().cemiterio
			if idx < 0 or idx >= cem.size() or cem[idx].get("tipo", "") != "Convocado":
				return "Escolha um Convocado no seu Cemitério."
	return ""

func _pagar(custo: Dictionary, j: Jogador) -> void:
	var fac := BancoDados.custo_faccao(custo)
	var inc := int(custo.get("incolor", 0))
	var usa := mini(j.bonus_faccao, fac)
	j.bonus_faccao -= usa
	fac -= usa
	usa = mini(j.bonus_neutra, inc)
	j.bonus_neutra -= usa
	inc -= usa
	usa = mini(j.bonus_faccao, inc)
	j.bonus_faccao -= usa
	inc -= usa
	var restante := fac + inc
	for inst in j.campo:
		if restante == 0:
			break
		if inst.tipo() == "Fonte" and not inst.usada:
			inst.usada = true
			restante -= 1
	assert(restante == 0, "Pagamento de Essência inconsistente.")

func _passiva_ao_entrar(j: Jogador) -> void:
	# Passiva de Ordwyn: +1 de Vida quando um Convocado aliado entra em jogo.
	if j.comandante["id"] == "ordwyn":
		j.vida += 1
		_emitir("Passiva de Ordwyn: %s ganha 1 de Vida (%d)." % [j.nome(), j.vida])


# ---------------------------------------------------------------- efeitos

func _executar_efeitos(dados: Dictionary, gatilho: String, j: Jogador, alvos: Dictionary) -> void:
	for ef in dados.get("efeitos", []):
		if fase == Fase.FIM:
			return
		if str(ef.get("gatilho", "")) == gatilho:
			_executar_efeito(ef, j, alvos)

func _executar_efeito(ef: Dictionary, j: Jogador, alvos: Dictionary) -> void:
	var inimigo: Jogador = jogadores[1 - j.indice]
	var valor := int(ef.get("valor", 0))
	match str(ef.get("acao", "")):
		"dano":
			match str(ef.get("alvo", "")):
				"comandante_inimigo":
					evento_visual.emit("projetil", {"origem_jogador": j.indice, "alvo_jogador": inimigo.indice})
					_dano_comandante(inimigo, valor)
				"comandante_aliado":
					_dano_comandante(j, valor)
				"qualquer_inimigo":
					if bool(alvos.get("comandante", false)):
						evento_visual.emit("projetil", {"origem_jogador": j.indice, "alvo_jogador": inimigo.indice})
						_dano_comandante(inimigo, valor)
					else:
						evento_visual.emit("projetil", {"origem_jogador": j.indice, "alvo_inst": alvos["convocado"]})
						_dano_convocado(alvos["convocado"], valor)
				_:
					evento_visual.emit("projetil", {"origem_jogador": j.indice, "alvo_inst": alvos["convocado"]})
					_dano_convocado(alvos["convocado"], valor)
		"dano_todos":
			for inst in inimigo.convocados():
				if fase == Fase.FIM:
					return
				evento_visual.emit("projetil", {"origem_jogador": j.indice, "alvo_inst": inst})
				_dano_convocado(inst, valor)
		"curar":
			var alvo_cura := inimigo if str(ef.get("alvo", "")) == "comandante_inimigo" else j
			alvo_cura.vida += valor
			evento_visual.emit("cura", {"jogador": alvo_cura.indice, "valor": valor})
			_emitir("%s ganha %d de Vida (%d)." % [alvo_cura.nome(), valor, alvo_cura.vida])
		"comprar":
			for _i in valor:
				if fase == Fase.FIM:
					return
				_comprar(j)
		"buff":
			var alvos_buff: Array = []
			match str(ef.get("alvo", "")):
				"todos_aliados":
					alvos_buff = j.convocados()
				"proprio":
					pass  # não usado no set atual
				_:
					if alvos.get("convocado") != null:
						alvos_buff = [alvos["convocado"]]
			var permanente := str(ef.get("duracao", "turno")) == "permanente"
			for inst in alvos_buff:
				if permanente:
					inst.buff_poder_perm += int(ef.get("poder", 0))
					inst.buff_res_perm += int(ef.get("resiliencia", 0))
				else:
					inst.buff_poder_turno += int(ef.get("poder", 0))
					inst.buff_res_turno += int(ef.get("resiliencia", 0))
				for kw in ef.get("palavras_chave", []):
					if not kw in inst.kw_temporarias:
						inst.kw_temporarias.append(kw)
		"destruir":
			_emitir("%s é destruído pelo efeito." % alvos["convocado"].nome())
			_destruir(alvos["convocado"])
		"token":
			var t: Dictionary = ef.get("token", {})
			var dados_token := {
				"id": "token_" + str(t.get("nome", "?")).to_lower().replace(" ", "_"),
				"nome": t.get("nome", "Token"), "tipo": "Convocado",
				"subtipo": t.get("subtipo", ""), "faccao": [],
				"custo": {"incolor": 0}, "poder": int(t.get("poder", 1)),
				"resiliencia": int(t.get("resiliencia", 1)),
				"palavras_chave": t.get("palavras_chave", []),
			}
			for _i in int(ef.get("quantidade", 1)):
				j.campo.append(InstanciaCarta.new(dados_token, j.indice, true))
				_passiva_ao_entrar(j)
			_emitir("%s cria %d token(s) %s." % [j.nome(), int(ef.get("quantidade", 1)), dados_token["nome"]])
		"reviver":
			var idx := int(alvos.get("cemiterio_idx", -1))
			var dados_c: Dictionary = j.cemiterio[idx]
			j.cemiterio.remove_at(idx)
			j.mao.append(dados_c)
			_emitir("%s retorna do Cemitério para a mão de %s." % [dados_c["nome"], j.nome()])
		"drenar":
			evento_visual.emit("projetil", {"origem_jogador": j.indice, "alvo_jogador": inimigo.indice})
			_dano_comandante(inimigo, valor)
			if fase != Fase.FIM:
				j.vida += valor
				evento_visual.emit("cura", {"jogador": j.indice, "valor": valor})
				_emitir("%s drena %d de Vida (%d)." % [j.nome(), valor, j.vida])
		"essencia":
			if bool(ef.get("faccao", false)):
				j.bonus_faccao += valor
			else:
				j.bonus_neutra += valor
			_emitir("%s ganha %d de Essência extra neste turno." % [j.nome(), valor])
		"buscar_fonte":
			for i in j.baralho.size():
				if j.baralho[i].get("tipo", "") == "Fonte":
					var dados_f: Dictionary = j.baralho[i]
					j.baralho.remove_at(i)
					var inst_f := InstanciaCarta.new(dados_f, j.indice)
					inst_f.usada = true
					j.campo.append(inst_f)
					_embaralhar(j.baralho)
					_emitir("%s busca %s do baralho (entra usada)." % [j.nome(), dados_f["nome"]])
					break

func _dano_convocado(inst: InstanciaCarta, valor: int) -> void:
	if not vivo(inst):
		return
	inst.dano_marcado += valor
	evento_visual.emit("dano_convocado", {"inst": inst, "valor": valor})
	_emitir("%s sofre %d de dano." % [inst.nome(), valor])
	if inst.dano_marcado >= res_de(inst):
		_destruir(inst)

func _dano_comandante(j: Jogador, valor: int) -> void:
	j.vida -= valor
	evento_visual.emit("dano_comandante", {"jogador": j.indice, "valor": valor})
	_emitir("%s sofre %d de dano (Vida: %d)." % [j.nome(), valor, j.vida])
	if j.vida <= 0:
		_terminar(1 - j.indice)

func _destruir(inst: InstanciaCarta) -> void:
	var j: Jogador = jogadores[inst.dono]
	if not inst in j.campo:
		return
	j.campo.erase(inst)
	if not inst.eh_token:
		j.cemiterio.append(inst.dados)
	_emitir("%s vai para o Cemitério." % inst.nome())
	if inst.eh_convocado():
		_executar_efeitos(inst.dados, "ao_morrer", j, {})
		# Passiva de Nyx: +1 de Vida quando um Convocado aliado morre.
		if fase != Fase.FIM and j.comandante["id"] == "nyx":
			j.vida += 1
			_emitir("Passiva de Nyx: %s ganha 1 de Vida (%d)." % [j.nome(), j.vida])


# ---------------------------------------------------------------- comandante e relíquias

func pode_comando(j: Jogador) -> String:
	if not em_fase_principal() or j != jogador_ativo():
		return "A Habilidade de Comando só pode ser usada nas suas Fases Principais."
	if j.comando_usado:
		return "Habilidade de Comando já usada neste turno."
	var hc: Dictionary = j.comandante["habilidade_comando"]
	if not pode_pagar(hc.get("custo", {}), j):
		return "Essência insuficiente."
	if str(hc.get("custo_adicional", "")) == "sacrificar_convocado" and j.convocados().is_empty():
		return "Você precisa de um Convocado aliado para sacrificar."
	return ""

func ativar_comando(alvos: Dictionary = {}) -> String:
	var j := jogador_ativo()
	var erro := pode_comando(j)
	if erro != "":
		return erro
	var hc: Dictionary = j.comandante["habilidade_comando"]
	if str(hc.get("custo_adicional", "")) == "sacrificar_convocado":
		var sac: Variant = alvos.get("sacrificio")
		if sac == null or not (sac is InstanciaCarta) or sac.dono != ativo \
				or not sac.eh_convocado() or not vivo(sac):
			return "Escolha um Convocado aliado para sacrificar."
	_pagar(hc.get("custo", {}), j)
	j.comando_usado = true
	_emitir("%s usa a Habilidade de Comando: %s" % [j.nome(), hc["texto"]])
	if alvos.has("sacrificio"):
		_emitir("%s sacrifica %s." % [j.nome(), alvos["sacrificio"].nome()])
		_destruir(alvos["sacrificio"])
	if fase != Fase.FIM:
		for ef in hc.get("efeitos", []):
			_executar_efeito(ef, j, alvos)
	estado_mudou.emit()
	return ""

func efeito_ativado_de(inst: InstanciaCarta) -> Dictionary:
	for ef in inst.dados.get("efeitos", []):
		if str(ef.get("gatilho", "")) == "ativada":
			return ef
	return {}

func ativar_reliquia(inst: InstanciaCarta) -> String:
	if not em_fase_principal():
		return "Habilidades só podem ser ativadas nas Fases Principais."
	if inst.dono != ativo:
		return "Esta Relíquia não é sua."
	var ef := efeito_ativado_de(inst)
	if ef.is_empty():
		return "Esta carta não tem habilidade ativada."
	if inst.usada:
		return "%s já foi usada neste turno." % inst.nome()
	var j := jogador_ativo()
	if not pode_pagar(ef.get("custo", {}), j):
		return "Essência insuficiente."
	_pagar(ef.get("custo", {}), j)
	inst.usada = true
	_emitir("%s ativa %s." % [j.nome(), inst.nome()])
	_executar_efeito(ef, j, {})
	estado_mudou.emit()
	return ""


# ---------------------------------------------------------------- combate

func atacantes_elegiveis() -> Array:
	var lista: Array = []
	for inst in jogador_ativo().convocados():
		if not inst.usada and (not inst.entrou_neste_turno or tem_kw(inst, "Investida")):
			lista.append(inst)
	return lista

func pode_bloquear(bloqueador: InstanciaCarta, atacante: InstanciaCarta) -> bool:
	if not bloqueador.eh_convocado() or bloqueador.usada:
		return false
	if tem_kw(atacante, "Voo") and not tem_kw(bloqueador, "Voo"):
		return false
	return true

func declarar_atacantes(lista: Array) -> String:
	if fase != Fase.PRINCIPAL_1:
		return "O Combate acontece entre as Fases Principais 1 e 2."
	if combate_feito:
		return "Só há um Combate por turno."
	var elegiveis := atacantes_elegiveis()
	for a in lista:
		if not a in elegiveis:
			return "%s não pode atacar neste turno." % a.nome()
	combate_feito = true
	if lista.is_empty():
		fase = Fase.PRINCIPAL_2
		_emitir("%s não ataca. Fase Principal 2." % jogador_ativo().nome())
		estado_mudou.emit()
		return ""
	atacantes = lista.duplicate()
	for a in atacantes:
		a.usada = true  # Vigilância fica para o pós-MVP
	_emitir("%s ataca com %d Convocado(s)." % [jogador_ativo().nome(), atacantes.size()])
	# Se o defensor não tem nenhum bloqueador possível, resolve direto.
	var tem_bloqueio := false
	for b in defensor().convocados():
		for a in atacantes:
			if pode_bloquear(b, a):
				tem_bloqueio = true
				break
		if tem_bloqueio:
			break
	if tem_bloqueio:
		fase = Fase.BLOQUEIO
		estado_mudou.emit()
	else:
		_resolver_combate({})
	return ""

func validar_bloqueios(bloqueios: Dictionary) -> String:
	# bloqueios: InstanciaCarta atacante -> InstanciaCarta bloqueador (0 ou 1 por atacante)
	var def := defensor()
	var usados: Array = []
	for a in bloqueios:
		var b: InstanciaCarta = bloqueios[a]
		if not a in atacantes:
			return "Bloqueio atribuído a um não-atacante."
		if b.dono != def.indice or not vivo(b):
			return "Bloqueador inválido."
		if b in usados:
			return "%s não pode bloquear dois atacantes." % b.nome()
		if not pode_bloquear(b, a):
			return "%s não pode bloquear %s." % [b.nome(), a.nome()]
		usados.append(b)
	# Guarda: se um Convocado pronto com Guarda pode bloquear alguém, ele deve bloquear.
	for inst in def.convocados():
		if inst.usada or not tem_kw(inst, "Guarda") or inst in usados:
			continue
		for a in atacantes:
			if not bloqueios.has(a) and pode_bloquear(inst, a):
				return "%s tem Guarda e deve bloquear se puder." % inst.nome()
	return ""

func declarar_bloqueios(bloqueios: Dictionary) -> String:
	if fase != Fase.BLOQUEIO:
		return "Não é o momento de declarar bloqueadores."
	var erro := validar_bloqueios(bloqueios)
	if erro != "":
		return erro
	_resolver_combate(bloqueios)
	return ""

func _resolver_combate(bloqueios: Dictionary) -> void:
	var def := defensor()
	for a in bloqueios:
		_emitir("%s bloqueia %s." % [bloqueios[a].nome(), a.nome()])

	# Passo 1: dano de Primeiro Golpe (simultâneo entre quem tem a palavra-chave).
	var golpes: Array = []  # [origem, alvo]
	for a in atacantes:
		if not bloqueios.has(a):
			continue
		var b: InstanciaCarta = bloqueios[a]
		if tem_kw(a, "Primeiro Golpe"):
			golpes.append([a, b])
		if tem_kw(b, "Primeiro Golpe"):
			golpes.append([b, a])
	_aplicar_golpes(golpes)
	if fase == Fase.FIM:
		return

	# Passo 2: dano normal (quem tem Primeiro Golpe já bateu; mortos não batem).
	golpes = []
	for a in atacantes:
		if not bloqueios.has(a):
			if vivo(a):
				evento_visual.emit("ataque", {"origem": a, "alvo_jogador": def.indice})
				_dano_comandante(def, poder_de(a))
				if fase == Fase.FIM:
					return
			continue
		var b: InstanciaCarta = bloqueios[a]
		if vivo(a) and vivo(b) and not tem_kw(a, "Primeiro Golpe"):
			golpes.append([a, b])
		if vivo(b) and vivo(a) and not tem_kw(b, "Primeiro Golpe"):
			golpes.append([b, a])
	_aplicar_golpes(golpes)
	if fase == Fase.FIM:
		return

	atacantes = []
	fase = Fase.PRINCIPAL_2
	_emitir("Combate encerrado. Fase Principal 2 de %s." % jogador_ativo().nome())
	estado_mudou.emit()

func _aplicar_golpes(golpes: Array) -> void:
	# Calcula todo o dano antes de aplicar (simultâneo), depois destrói os mortos.
	var pendentes: Array = []  # [alvo, dano, toque_mortal]
	for g in golpes:
		var origem: InstanciaCarta = g[0]
		var alvo: InstanciaCarta = g[1]
		var dano := poder_de(origem)
		evento_visual.emit("ataque", {"origem": origem, "alvo_inst": alvo})
		pendentes.append([alvo, dano, dano > 0 and tem_kw(origem, "Toque Mortal")])
	var mortos: Array = []
	for p in pendentes:
		var alvo: InstanciaCarta = p[0]
		alvo.dano_marcado += int(p[1])
		if int(p[1]) > 0:
			_emitir("%s sofre %d de dano de combate." % [alvo.nome(), int(p[1])])
		if (alvo.dano_marcado >= res_de(alvo) or bool(p[2])) and not alvo in mortos:
			mortos.append(alvo)
	for m in mortos:
		_destruir(m)
		if fase == Fase.FIM:
			return


# ---------------------------------------------------------------- fluxo de turno

func encerrar_turno() -> String:
	if not em_fase_principal():
		return "Não é possível encerrar o turno agora."
	var j := jogador_ativo()
	if j.mao.size() > LIMITE_MAO:
		fase = Fase.DESCARTE
		_emitir("%s precisa descartar %d carta(s)." % [j.nome(), j.mao.size() - LIMITE_MAO])
		estado_mudou.emit()
		return ""
	_finalizar_turno()
	return ""

func descartar(idx: int) -> String:
	if fase != Fase.DESCARTE:
		return "Não é o momento de descartar."
	var j := jogador_ativo()
	if idx < 0 or idx >= j.mao.size():
		return "Carta inválida."
	var dados: Dictionary = j.mao[idx]
	j.mao.remove_at(idx)
	j.cemiterio.append(dados)
	_emitir("%s descarta %s." % [j.nome(), dados["nome"]])
	if j.mao.size() <= LIMITE_MAO:
		_finalizar_turno()
	else:
		estado_mudou.emit()
	return ""

func _finalizar_turno() -> void:
	# Efeitos "até o final do turno" expiram; Essência não gasta se perde.
	for jog in jogadores:
		for inst in jog.campo:
			inst.limpar_buffs_de_turno()
	jogador_ativo().bonus_neutra = 0
	jogador_ativo().bonus_faccao = 0
	ativo = 1 - ativo
	_comecar_turno()

func _comecar_turno() -> void:
	turno += 1
	var j := jogador_ativo()
	combate_feito = false
	atacantes = []
	j.fonte_jogada = false
	j.comando_usado = false
	# Despertar: tudo do jogador da vez fica pronto; mal de invocação passa;
	# dano marcado em Convocados é removido (de todos — dano não persiste entre turnos).
	for inst in j.campo:
		inst.usada = false
		inst.entrou_neste_turno = false
	for jog in jogadores:
		for inst in jog.campo:
			inst.dano_marcado = 0
	_emitir("")
	_emitir("— Turno %d: %s —" % [turno, j.nome()])
	# Colheita: compra 1 (exceto o jogador inicial no primeiro turno).
	if turno > 1:
		_comprar(j)
		if fase == Fase.FIM:
			return
	fase = Fase.PRINCIPAL_1
	estado_mudou.emit()

func _comprar(j: Jogador) -> void:
	if j.baralho.is_empty():
		_emitir("%s tenta comprar com o baralho vazio!" % j.nome())
		_terminar(1 - j.indice)
		return
	j.mao.append(j.baralho.pop_back())
	_emitir("%s compra uma carta (%d no baralho)." % [j.nome(), j.baralho.size()])

func _terminar(vencedor: int) -> void:
	if fase == Fase.FIM:
		return
	fase = Fase.FIM
	_emitir("=== VITÓRIA de %s! ===" % jogadores[vencedor].nome())
	partida_terminou.emit(vencedor)
	estado_mudou.emit()

func _emitir(texto: String) -> void:
	registro.emit(texto)
