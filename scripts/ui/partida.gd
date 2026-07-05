extends Control
## Cena de partida: UI construída em código a partir do estado do Motor.
## Suporta hotseat, IA e partida em rede (os dois lados rodam o mesmo Motor
## deterministicamente e trocam apenas as ações via Rede).
## Animações: eventos visuais do Motor entram numa fila e são tocados antes
## de a UI ser reconstruída com o novo estado.

const TAM_MAO := Vector2(112, 152)
const TAM_CAMPO := Vector2(104, 142)
const COR_ALVO := Color(0.30, 0.90, 0.40)
const COR_ELEGIVEL := Color(0.95, 0.85, 0.30)
const COR_SELECAO := Color(0.95, 0.45, 0.20)
const COR_ATACANTE := Color(0.90, 0.25, 0.25)
const COR_BLOQUEIO := Color(0.35, 0.70, 0.95)

enum Modo {NORMAL, ALVO, SACRIFICIO, ATACANTES}

var motor: Motor
var modo: int = Modo.NORMAL
var origem := ""      # "mao" | "comando"
var carta_idx := -1
var alvos := {}
var requisito := ""
var atacantes_sel: Array = []
var bloqueios := {}   # atacante -> bloqueador
var bloqueador_sel: InstanciaCarta = null
var ia_ocupada := false

var fila_anim: Array = []
var animando := false
var _origem_jogada := Vector2.ZERO   # posição real da carta clicada na mão
var _tem_origem_jogada := false
var camada_anim: Control
var camada_linhas: Control  # linhas de bloqueio desenhadas por cima do tabuleiro
var detalhe: DetalheCarta   # visualização ampliada (botão direito)
var _ultimo_turno := -1

var lbl_fase: Label
var lbl_instrucao: Label
var log_rt: RichTextLabel
var mao_box: HBoxContainer
var linhas := {}       # "fontes_cima" etc -> HBoxContainer
var slots_cmd := {}    # "cima"/"baixo" -> Container
var lbl_info := {}     # "cima"/"baixo" -> Label
var visuais := {}      # InstanciaCarta -> CartaVisual
var paineis_cmd := {}  # índice do jogador -> ComandanteVisual
var botoes := {}
var popup_cem: PopupPanel
var popup_vbox: VBoxContainer

func _ready() -> void:
	_montar_ui()
	motor = Motor.new()
	motor.registro.connect(_log)
	motor.estado_mudou.connect(_ao_estado_mudou)
	motor.partida_terminou.connect(_fim_de_jogo)
	motor.evento_visual.connect(_evento_visual)
	if Rede.ativo:
		Rede.acao_recebida.connect(_ao_acao_remota)
		Rede.desconectado.connect(_ao_desconectar)
	var cfg: Dictionary = BancoDados.config_partida
	if cfg.is_empty():  # execução direta da cena (F6) no editor
		cfg = {"jogadores": [
			{"comandante": "ordwyn", "eh_ia": false},
			{"comandante": "korrath", "eh_ia": true}]}
	motor.iniciar(cfg["jogadores"], int(cfg.get("seed", 0)))
	_atualizar()
	_falas_de_entrada()

func _falas_de_entrada() -> void:
	var c0: String = motor.jogadores[0].comandante["id"]
	var c1: String = motor.jogadores[1].comandante["id"]
	# Fala específica contra o oponente tem prioridade; senão a fala de entrada.
	Som.falar(c0, ["vs_" + c1, "entrada"], true)
	get_tree().create_timer(2.4).timeout.connect(
			func() -> void: Som.falar(c1, ["vs_" + c0, "entrada"], true))


# ---------------------------------------------------------------- construção da UI

func _montar_ui() -> void:
	_montar_fundo("res://assets/ui/fundo_mesa", 0.35)

	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margem.add_theme_constant_override("margin_" + lado, 8)
	add_child(margem)

	var raiz := HBoxContainer.new()
	raiz.add_theme_constant_override("separation", 8)
	margem.add_child(raiz)

	var esquerda := VBoxContainer.new()
	esquerda.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	esquerda.add_theme_constant_override("separation", 4)
	raiz.add_child(esquerda)

	esquerda.add_child(_montar_lado("cima"))
	esquerda.add_child(_montar_centro())
	esquerda.add_child(_montar_lado("baixo"))

	var rolagem := ScrollContainer.new()
	rolagem.custom_minimum_size = Vector2(0, TAM_MAO.y + 12)
	rolagem.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	rolagem.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	esquerda.add_child(rolagem)
	mao_box = HBoxContainer.new()
	mao_box.add_theme_constant_override("separation", 6)
	mao_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mao_box.alignment = BoxContainer.ALIGNMENT_CENTER
	rolagem.add_child(mao_box)

	var direita := VBoxContainer.new()
	direita.custom_minimum_size = Vector2(270, 0)
	raiz.add_child(direita)
	var titulo_log := Label.new()
	titulo_log.text = "Registro da Partida"
	titulo_log.add_theme_font_size_override("font_size", 12)
	direita.add_child(titulo_log)
	log_rt = RichTextLabel.new()
	log_rt.scroll_following = true
	log_rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_rt.add_theme_font_size_override("normal_font_size", 11)
	direita.add_child(log_rt)

	popup_cem = PopupPanel.new()
	popup_vbox = VBoxContainer.new()
	popup_cem.add_child(popup_vbox)
	add_child(popup_cem)

	# Linhas de bloqueio (desenhadas via sinal draw).
	camada_linhas = Control.new()
	camada_linhas.set_anchors_preset(Control.PRESET_FULL_RECT)
	camada_linhas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada_linhas.draw.connect(_desenhar_linhas)
	add_child(camada_linhas)

	# Camada de animações por cima de tudo (fantasmas de carta, projéteis, números).
	camada_anim = Control.new()
	camada_anim.set_anchors_preset(Control.PRESET_FULL_RECT)
	camada_anim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(camada_anim)

	# Visualização ampliada (botão direito) — fica por cima de tudo.
	detalhe = DetalheCarta.new()
	add_child(detalhe)

func _montar_lado(pos: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var slot := VBoxContainer.new()
	slot.custom_minimum_size = Vector2(196, 0)
	slot.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_cmd[pos] = slot
	h.add_child(slot)
	var centro := VBoxContainer.new()
	centro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centro.alignment = BoxContainer.ALIGNMENT_CENTER
	centro.add_theme_constant_override("separation", 2)
	var ordem := ["fontes_", "campo_"] if pos == "cima" else ["campo_", "fontes_"]
	for prefixo in ordem:
		var linha := HBoxContainer.new()
		linha.custom_minimum_size = Vector2(0, TAM_CAMPO.y * (0.62 if prefixo == "fontes_" else 1.0))
		linha.add_theme_constant_override("separation", 4)
		linha.alignment = BoxContainer.ALIGNMENT_CENTER
		linhas[prefixo + pos] = linha
		centro.add_child(linha)
	h.add_child(centro)
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 10)
	info.custom_minimum_size = Vector2(86, 0)
	lbl_info[pos] = info
	h.add_child(info)
	return h

func _montar_centro() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(0, 40)
	h.add_theme_constant_override("separation", 10)
	lbl_fase = Label.new()
	lbl_fase.add_theme_font_size_override("font_size", 13)
	lbl_fase.add_theme_color_override("font_color", Color(0.88, 0.78, 0.45))
	h.add_child(lbl_fase)
	lbl_instrucao = Label.new()
	lbl_instrucao.add_theme_font_size_override("font_size", 12)
	lbl_instrucao.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_instrucao.add_theme_color_override("font_color", Color(0.6, 0.85, 0.95))
	h.add_child(lbl_instrucao)
	for nome in ["atacar", "confirmar", "cancelar", "encerrar"]:
		var b := Button.new()
		b.visible = false
		botoes[nome] = b
		h.add_child(b)
	botoes["atacar"].text = "⚔ Atacar"
	botoes["atacar"].pressed.connect(_iniciar_ataque)
	botoes["confirmar"].pressed.connect(_confirmar)
	botoes["cancelar"].text = "Cancelar"
	botoes["cancelar"].pressed.connect(_cancelar)
	botoes["encerrar"].text = "Encerrar Turno"
	botoes["encerrar"].pressed.connect(_encerrar)
	return h


# ---------------------------------------------------------------- controle (local/IA/rede)

## Este cliente controla o jogador j?
func _controla(j: Jogador) -> bool:
	if Rede.ativo:
		return j.indice == Rede.meu_lugar
	return not j.eh_ia

func _posso_agir() -> bool:
	return _controla(motor.jogador_ativo())

func _jogador_baixo() -> int:
	if Rede.ativo:
		return Rede.meu_lugar
	if motor.jogadores[0].eh_ia:
		return 1
	if motor.jogadores[1].eh_ia:
		return 0
	if motor.fase == Motor.Fase.BLOQUEIO:
		return motor.defensor().indice
	return motor.ativo

## Dono da mão exibida embaixo.
func _dono_da_mao() -> Jogador:
	if Rede.ativo:
		return motor.jogadores[Rede.meu_lugar]
	return motor.jogador_ativo()


# ---------------------------------------------------------------- ações (local + rede)

func _acao_local(acao: Dictionary) -> String:
	var pacote := {}
	if Rede.ativo:
		pacote = _serializar_acao(acao)  # serializa ANTES de aplicar (índices ainda válidos)
	var erro := _aplicar_acao(acao)
	if erro == "" and Rede.ativo:
		Rede.enviar_acao(pacote)
	return erro

func _aplicar_acao(acao: Dictionary) -> String:
	match str(acao["t"]):
		"carta":
			return motor.jogar_carta(int(acao["idx"]), acao.get("alvos", {}))
		"comando":
			return motor.ativar_comando(acao.get("alvos", {}))
		"reliquia":
			return motor.ativar_reliquia(acao["inst"])
		"atacar":
			return motor.declarar_atacantes(acao["lista"])
		"bloqueios":
			return motor.declarar_bloqueios(acao["pares"])
		"encerrar":
			return motor.encerrar_turno()
		"descartar":
			return motor.descartar(int(acao["idx"]))
	return "Ação desconhecida."

func _serializar_acao(a: Dictionary) -> Dictionary:
	var d := {"t": a["t"]}
	match str(a["t"]):
		"carta":
			d["idx"] = a["idx"]
			d["alvos"] = motor.serializar_alvos(a.get("alvos", {}))
		"comando":
			d["alvos"] = motor.serializar_alvos(a.get("alvos", {}))
		"reliquia":
			d["ref"] = motor.ref_de(a["inst"])
		"atacar":
			var lista: Array = []
			for inst in a["lista"]:
				lista.append(motor.ref_de(inst))
			d["lista"] = lista
		"bloqueios":
			var pares: Array = []
			for atk in a["pares"]:
				pares.append([motor.ref_de(atk), motor.ref_de(a["pares"][atk])])
			d["pares"] = pares
		"descartar":
			d["idx"] = a["idx"]
	return d

func _ao_acao_remota(pacote: Dictionary) -> void:
	var a := {"t": pacote["t"]}
	match str(pacote["t"]):
		"carta":
			a["idx"] = pacote["idx"]
			a["alvos"] = motor.desserializar_alvos(pacote.get("alvos", {}))
		"comando":
			a["alvos"] = motor.desserializar_alvos(pacote.get("alvos", {}))
		"reliquia":
			a["inst"] = motor.inst_de(pacote["ref"])
		"atacar":
			var lista: Array = []
			for ref in pacote["lista"]:
				lista.append(motor.inst_de(ref))
			a["lista"] = lista
		"bloqueios":
			var pares := {}
			for par in pacote["pares"]:
				pares[motor.inst_de(par[0])] = motor.inst_de(par[1])
			a["pares"] = pares
		"descartar":
			a["idx"] = pacote["idx"]
	var erro := _aplicar_acao(a)
	if erro != "":
		_log("[Rede] Ação do oponente rejeitada: " + erro)


# ---------------------------------------------------------------- animações

func _evento_visual(tipo: String, info: Dictionary) -> void:
	# Falas dos comandantes tocam mesmo com as animações desligadas.
	match tipo:
		"jogada":
			Som.falar(motor.jogadores[int(info["jogador"])].comandante["id"], "jogar_carta")
		"dano_comandante":
			Som.falar(motor.jogadores[int(info["jogador"])].comandante["id"], "dano")
	if not Opcoes.animacoes:
		return
	match tipo:
		"jogada":
			var dono := int(info["jogador"])
			var pos := "baixo" if dono == _jogador_baixo() else "cima"
			var de: Vector2
			if _tem_origem_jogada and dono == motor.ativo:
				de = _origem_jogada  # posição exata da carta clicada na mão
				_tem_origem_jogada = false
			elif pos == "baixo":
				de = mao_box.get_global_rect().get_center()
			else:
				de = _pos_cmd(dono) + Vector2(0, -40)
			fila_anim.append({"tipo": "voo_carta", "dados": info["dados"],
					"de": de, "para": linhas["campo_" + pos].get_global_rect().get_center()})
		"ataque":
			fila_anim.append({"tipo": "voo_carta", "dados": info["origem"].dados,
					"de": _pos_inst(info["origem"]), "para": _pos_alvo(info)})
		"projetil":
			var cor := CartaVisual.cor_de_faccao(
					motor.jogadores[int(info["origem_jogador"])].comandante.get("faccao", []))
			fila_anim.append({"tipo": "projetil", "cor": cor,
					"de": _pos_cmd(int(info["origem_jogador"])), "para": _pos_alvo(info)})
		"dano_comandante":
			fila_anim.append({"tipo": "dano", "pos": _pos_cmd(int(info["jogador"])),
					"valor": int(info["valor"]), "tremor": true})
		"dano_convocado":
			fila_anim.append({"tipo": "dano", "pos": _pos_inst(info["inst"]),
					"valor": int(info["valor"]), "tremor": false})
		"cura":
			fila_anim.append({"tipo": "cura", "pos": _pos_cmd(int(info["jogador"])),
					"valor": int(info["valor"])})

func _pos_alvo(info: Dictionary) -> Vector2:
	if info.has("alvo_inst"):
		return _pos_inst(info["alvo_inst"])
	return _pos_cmd(int(info["alvo_jogador"]))

func _pos_inst(inst: InstanciaCarta) -> Vector2:
	if visuais.has(inst) and is_instance_valid(visuais[inst]):
		return visuais[inst].get_global_rect().get_center()
	return _pos_cmd(inst.dono)

func _pos_cmd(idx: int) -> Vector2:
	if paineis_cmd.has(idx) and is_instance_valid(paineis_cmd[idx]):
		return paineis_cmd[idx].get_global_rect().get_center()
	return get_viewport_rect().size / 2.0

func _ao_estado_mudou() -> void:
	if animando:
		return  # a fila será drenada e a UI atualizada ao final da reprodução
	if fila_anim.is_empty():
		_atualizar()
	else:
		_tocar_e_atualizar()

func _tocar_e_atualizar() -> void:
	animando = true
	while not fila_anim.is_empty():
		await _tocar(fila_anim.pop_front())
	animando = false
	_atualizar()

func _tocar(ev: Dictionary) -> void:
	match str(ev["tipo"]):
		"voo_carta":
			var ghost := CartaVisual.new()
			camada_anim.add_child(ghost)
			ghost.configurar(ev["dados"], null, null, TAM_CAMPO * 0.85)
			ghost.size = TAM_CAMPO * 0.85
			ghost.position = ev["de"] - ghost.size / 2.0
			var tw := create_tween()
			tw.tween_property(ghost, "position", ev["para"] - ghost.size / 2.0, 0.22) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			await tw.finished
			ghost.queue_free()
		"projetil":
			var p := ColorRect.new()
			p.color = ev["cor"]
			p.size = Vector2(16, 16)
			camada_anim.add_child(p)
			p.position = ev["de"] - Vector2(8, 8)
			var tw := create_tween()
			tw.tween_property(p, "position", ev["para"] - Vector2(8, 8), 0.26)
			await tw.finished
			p.queue_free()
		"dano":
			_numero_flutuante(ev["pos"], "-%d" % int(ev["valor"]), Color(1.0, 0.35, 0.3))
			if bool(ev["tremor"]):
				await _tremer()
			else:
				await get_tree().create_timer(0.12).timeout
		"cura":
			_numero_flutuante(ev["pos"], "+%d" % int(ev["valor"]), Color(0.4, 0.95, 0.45))
			await get_tree().create_timer(0.08).timeout

func _numero_flutuante(pos: Vector2, texto: String, cor: Color) -> void:
	var lbl := Label.new()
	lbl.text = texto
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", cor)
	camada_anim.add_child(lbl)
	lbl.position = pos - Vector2(12, 14)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 38, 0.7)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(lbl.queue_free)

func _tremer() -> void:
	if not Opcoes.tremor:
		await get_tree().create_timer(0.15).timeout
		return
	var orig := position
	var tw := create_tween()
	for i in 6:
		tw.tween_property(self, "position",
				orig + Vector2(randf_range(-9, 9), randf_range(-9, 9)), 0.04)
	tw.tween_property(self, "position", orig, 0.04)
	await tw.finished

func _banner(texto: String) -> void:
	if not Opcoes.animacoes:
		return
	var lbl := Label.new()
	lbl.text = texto
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", Color(0.88, 0.78, 0.45))
	camada_anim.add_child(lbl)
	await get_tree().process_frame
	lbl.position = Vector2(get_viewport_rect().size.x / 2.0 - lbl.size.x / 2.0,
			get_viewport_rect().size.y * 0.42)
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tw.tween_callback(lbl.queue_free)


# ---------------------------------------------------------------- atualização

func _atualizar() -> void:
	if motor == null:
		return
	visuais.clear()
	paineis_cmd.clear()
	if motor.fase != Motor.Fase.BLOQUEIO:
		bloqueios = {}
		bloqueador_sel = null
	var jb := _jogador_baixo()
	_preencher_lado("baixo", jb)
	_preencher_lado("cima", 1 - jb)
	_preencher_mao()
	_atualizar_rotulos()
	_atualizar_botoes()
	_aplicar_destaques()
	camada_linhas.queue_redraw()
	if motor.turno != _ultimo_turno and motor.fase != Motor.Fase.FIM:
		_ultimo_turno = motor.turno
		_banner("Seu turno!" if _posso_agir()
				else "Turno de %s" % motor.jogador_ativo().nome().split(",")[0])
	call_deferred("_verificar_ia")

func _process(_delta: float) -> void:
	# A linha bloqueador→mouse acompanha o cursor durante a escolha.
	if motor != null and motor.fase == Motor.Fase.BLOQUEIO and bloqueador_sel != null:
		camada_linhas.queue_redraw()

## Desenha as linhas de bloqueio (bloqueador → atacante) e a linha em andamento até o mouse.
func _desenhar_linhas() -> void:
	if motor == null or motor.fase != Motor.Fase.BLOQUEIO:
		return
	var inv := camada_linhas.get_global_transform().affine_inverse()
	for a in bloqueios:
		if not visuais.has(a) or not visuais.has(bloqueios[a]):
			continue
		var de: Vector2 = inv * visuais[bloqueios[a]].get_global_rect().get_center()
		var para: Vector2 = inv * visuais[a].get_global_rect().get_center()
		camada_linhas.draw_line(de, para, COR_BLOQUEIO, 3.0, true)
		camada_linhas.draw_circle(de, 6.0, COR_BLOQUEIO)
		camada_linhas.draw_circle(para, 6.0, COR_ATACANTE)
	if bloqueador_sel != null and visuais.has(bloqueador_sel):
		var de: Vector2 = inv * visuais[bloqueador_sel].get_global_rect().get_center()
		var para: Vector2 = inv * camada_linhas.get_global_mouse_position()
		camada_linhas.draw_line(de, para, COR_SELECAO, 2.0, true)

func _abrir_detalhe_carta(cv: CartaVisual) -> void:
	detalhe.abrir_carta(cv.dados, motor, cv.instancia)

func _abrir_detalhe_comandante(cv: ComandanteVisual) -> void:
	detalhe.abrir_comandante(cv.comandante, motor.jogadores[cv.indice_jogador].vida)

func _preencher_lado(pos: String, idx: int) -> void:
	_limpar(slots_cmd[pos])
	_limpar(linhas["fontes_" + pos])
	_limpar(linhas["campo_" + pos])
	var j: Jogador = motor.jogadores[idx]
	var cv := ComandanteVisual.new()
	var mostrar_botao: bool = idx == motor.ativo and _controla(j) \
			and motor.em_fase_principal() and modo == Modo.NORMAL
	cv.configurar(j.comandante, j.vida, idx, mostrar_botao, motor.pode_comando(j) == "")
	cv.clicado.connect(_clicou_comandante)
	cv.detalhes.connect(_abrir_detalhe_comandante)
	cv.comando_pressionado.connect(_pressionou_comando)
	slots_cmd[pos].add_child(cv)
	paineis_cmd[idx] = cv
	for inst in j.campo:
		var linha: HBoxContainer = linhas[("fontes_" if inst.tipo() == "Fonte" else "campo_") + pos]
		var c := CartaVisual.new()
		var tam := TAM_CAMPO * (0.62 if inst.tipo() == "Fonte" else 1.0)
		c.configurar(inst.dados, motor, inst, tam)
		c.clicada.connect(_clicou_campo)
		c.detalhes.connect(_abrir_detalhe_carta)
		linha.add_child(c)
		visuais[inst] = c
	var disp: Dictionary = motor.essencia_disponivel(j)
	lbl_info[pos].text = "Mão: %d\nBaralho: %d\nCemitério: %d\nEssência: %d" % [
		j.mao.size(), j.baralho.size(), j.cemiterio.size(), int(disp["total"])]

func _preencher_mao() -> void:
	_limpar(mao_box)
	var dono := _dono_da_mao()
	if not _controla(dono) or motor.fase == Motor.Fase.FIM:
		return
	if not Rede.ativo and motor.fase == Motor.Fase.BLOQUEIO:
		return
	var minha_vez: bool = dono == motor.jogador_ativo() and motor.fase != Motor.Fase.BLOQUEIO
	for i in dono.mao.size():
		var c := CartaVisual.new()
		c.configurar(dono.mao[i], motor, null, TAM_MAO)
		c.set_meta("idx", i)
		c.clicada.connect(_clicou_mao)
		c.detalhes.connect(_abrir_detalhe_carta)
		if not minha_vez or (motor.em_fase_principal() and motor.pode_jogar(i) != ""):
			c.modulate = Color(0.55, 0.55, 0.55)
		mao_box.add_child(c)

func _atualizar_rotulos() -> void:
	var nomes_fase := {
		Motor.Fase.PRINCIPAL_1: "Fase Principal 1",
		Motor.Fase.BLOQUEIO: "Combate — Bloqueios",
		Motor.Fase.PRINCIPAL_2: "Fase Principal 2",
		Motor.Fase.DESCARTE: "Final — Descarte",
		Motor.Fase.FIM: "Fim da Partida",
	}
	lbl_fase.text = "Turno %d · %s · %s" % [
		motor.turno, motor.jogador_ativo().nome().split(",")[0], nomes_fase.get(motor.fase, "")]
	if motor.fase == Motor.Fase.BLOQUEIO and _controla(motor.defensor()):
		_instr("Defesa: clique num bloqueador seu e depois no atacante; confirme ao terminar.")
	elif motor.fase == Motor.Fase.DESCARTE and _posso_agir():
		_instr("Limite de mão (7): clique nas cartas que quer descartar.")
	elif Rede.ativo and motor.fase != Motor.Fase.FIM and not _posso_agir() \
			and not (motor.fase == Motor.Fase.BLOQUEIO and _controla(motor.defensor())):
		_instr("Aguardando o oponente...")

func _atualizar_botoes() -> void:
	for nome in botoes:
		botoes[nome].visible = false
	if motor.fase == Motor.Fase.FIM:
		return
	match modo:
		Modo.NORMAL:
			if _posso_agir() and motor.em_fase_principal():
				botoes["encerrar"].visible = true
				if motor.fase == Motor.Fase.PRINCIPAL_1 and not motor.combate_feito \
						and not motor.atacantes_elegiveis().is_empty():
					botoes["atacar"].visible = true
			if motor.fase == Motor.Fase.BLOQUEIO and _controla(motor.defensor()):
				botoes["confirmar"].text = "Confirmar Bloqueios"
				botoes["confirmar"].visible = true
		Modo.ATACANTES:
			botoes["confirmar"].text = "Confirmar Ataque (%d)" % atacantes_sel.size()
			botoes["confirmar"].visible = true
			botoes["cancelar"].visible = true
		Modo.ALVO, Modo.SACRIFICIO:
			botoes["cancelar"].visible = true

func _aplicar_destaques() -> void:
	match modo:
		Modo.ALVO:
			for inst in _alvos_validos():
				if visuais.has(inst):
					visuais[inst].destacar(COR_ALVO)
			if requisito == "qualquer_inimigo" and paineis_cmd.has(1 - motor.ativo):
				paineis_cmd[1 - motor.ativo].destacar(COR_ALVO)
		Modo.SACRIFICIO:
			for inst in motor.jogador_ativo().convocados():
				if visuais.has(inst):
					visuais[inst].destacar(COR_ALVO)
		Modo.ATACANTES:
			for inst in motor.atacantes_elegiveis():
				if visuais.has(inst):
					visuais[inst].destacar(COR_SELECAO if inst in atacantes_sel else COR_ELEGIVEL)
	if motor.fase == Motor.Fase.BLOQUEIO:
		for i in motor.atacantes.size():
			var a: InstanciaCarta = motor.atacantes[i]
			if visuais.has(a):
				visuais[a].destacar(COR_ATACANTE)
				visuais[a].definir_selo("⚔%d" % (i + 1))
		for a in bloqueios:
			var num := motor.atacantes.find(a) + 1
			if visuais.has(bloqueios[a]):
				visuais[bloqueios[a]].destacar(COR_BLOQUEIO)
				visuais[bloqueios[a]].definir_selo("🛡%d" % num)
		if bloqueador_sel != null and visuais.has(bloqueador_sel):
			visuais[bloqueador_sel].destacar(COR_SELECAO)

func _alvos_validos() -> Array:
	match requisito:
		"convocado_inimigo", "qualquer_inimigo":
			return motor.oponente().convocados()
		"convocado_aliado":
			return motor.jogador_ativo().convocados()
		"convocado_qualquer":
			return motor.jogador_ativo().convocados() + motor.oponente().convocados()
	return []


# ---------------------------------------------------------------- interação

func _clicou_mao(cv: CartaVisual) -> void:
	if motor.fase == Motor.Fase.FIM or not _posso_agir():
		return
	var idx: int = cv.get_meta("idx")
	if motor.fase == Motor.Fase.DESCARTE:
		_acao_local({"t": "descartar", "idx": idx})
		return
	if modo != Modo.NORMAL or not motor.em_fase_principal():
		return
	var erro := motor.pode_jogar(idx)
	if erro != "":
		_instr(erro)
		return
	_origem_jogada = cv.get_global_rect().get_center()
	_tem_origem_jogada = true
	origem = "mao"
	carta_idx = idx
	alvos = {}
	_avancar_pendente(_dados_pendentes())

func _dados_pendentes() -> Dictionary:
	if origem == "comando":
		return motor.jogador_ativo().comandante["habilidade_comando"]
	return motor.jogador_ativo().mao[carta_idx]

func _avancar_pendente(dados: Dictionary) -> void:
	if str(dados.get("custo_adicional", "")) == "sacrificar_convocado" \
			and not alvos.has("sacrificio"):
		modo = Modo.SACRIFICIO
		_instr("Escolha um Convocado aliado para sacrificar.")
		_atualizar()
		return
	var req := motor.requisito_alvo(dados)
	if req != "" and not _alvo_definido(req):
		if req == "cemiterio_convocado":
			_abrir_cemiterio()
			return
		modo = Modo.ALVO
		requisito = req
		_instr("Escolha um alvo destacado." + (" (O Comandante inimigo também é alvo válido.)"
				if req == "qualquer_inimigo" else ""))
		_atualizar()
		return
	_executar_pendente()

func _alvo_definido(req: String) -> bool:
	match req:
		"qualquer_inimigo":
			return alvos.has("convocado") or bool(alvos.get("comandante", false))
		"cemiterio_convocado":
			return alvos.has("cemiterio_idx")
	return alvos.has("convocado")

func _executar_pendente() -> void:
	var erro := ""
	if origem == "comando":
		erro = _acao_local({"t": "comando", "alvos": alvos})
	else:
		erro = _acao_local({"t": "carta", "idx": carta_idx, "alvos": alvos})
	_instr(erro)
	_resetar_modo()

func _resetar_modo() -> void:
	modo = Modo.NORMAL
	origem = ""
	carta_idx = -1
	alvos = {}
	requisito = ""
	atacantes_sel = []
	_tem_origem_jogada = false
	if not animando:
		_atualizar()

func _clicou_campo(cv: CartaVisual) -> void:
	var inst := cv.instancia
	if inst == null or motor.fase == Motor.Fase.FIM:
		return
	if motor.fase == Motor.Fase.BLOQUEIO:
		_clique_bloqueio(inst)
		return
	if not _posso_agir():
		return
	match modo:
		Modo.ALVO:
			if inst in _alvos_validos():
				alvos["convocado"] = inst
				_avancar_pendente(_dados_pendentes())
		Modo.SACRIFICIO:
			if inst.dono == motor.ativo and inst.eh_convocado():
				alvos["sacrificio"] = inst
				_avancar_pendente(_dados_pendentes())
		Modo.ATACANTES:
			if inst in motor.atacantes_elegiveis():
				if inst in atacantes_sel:
					atacantes_sel.erase(inst)
				else:
					atacantes_sel.append(inst)
				_atualizar()
		Modo.NORMAL:
			if inst.dono == motor.ativo and inst.tipo() == "Relíquia":
				_instr(_acao_local({"t": "reliquia", "inst": inst}))

func _clique_bloqueio(inst: InstanciaCarta) -> void:
	var def := motor.defensor()
	if not _controla(def):
		return
	if inst.dono == def.indice:
		if not inst.eh_convocado() or inst.usada:
			return
		for a in bloqueios.keys():
			if bloqueios[a] == inst:  # já bloqueia: clique remove a atribuição
				bloqueios.erase(a)
				bloqueador_sel = null
				_atualizar()
				return
		bloqueador_sel = inst
		_instr("Agora clique no atacante que %s vai bloquear." % inst.nome())
		_atualizar()
	elif inst in motor.atacantes and bloqueador_sel != null:
		if motor.pode_bloquear(bloqueador_sel, inst):
			bloqueios[inst] = bloqueador_sel
			bloqueador_sel = null
			_instr("")
			_atualizar()
		else:
			_instr("%s não pode bloquear %s." % [bloqueador_sel.nome(), inst.nome()])

func _clicou_comandante(cv: ComandanteVisual) -> void:
	if modo == Modo.ALVO and requisito == "qualquer_inimigo" \
			and cv.indice_jogador != motor.ativo and _posso_agir():
		alvos["comandante"] = true
		_avancar_pendente(_dados_pendentes())

func _pressionou_comando() -> void:
	if not _posso_agir() or not motor.em_fase_principal() or modo != Modo.NORMAL:
		return
	var erro := motor.pode_comando(motor.jogador_ativo())
	if erro != "":
		_instr(erro)
		return
	origem = "comando"
	carta_idx = -1
	alvos = {}
	_avancar_pendente(_dados_pendentes())

func _abrir_cemiterio() -> void:
	_limpar(popup_vbox)
	var titulo := Label.new()
	titulo.text = "Escolha um Convocado do Cemitério:"
	popup_vbox.add_child(titulo)
	var j := motor.jogador_ativo()
	for i in j.cemiterio.size():
		if j.cemiterio[i].get("tipo", "") != "Convocado":
			continue
		var b := Button.new()
		b.text = "%s (%d/%d)" % [j.cemiterio[i]["nome"],
				int(j.cemiterio[i].get("poder", 0)), int(j.cemiterio[i].get("resiliencia", 0))]
		b.pressed.connect(_escolheu_cemiterio.bind(i))
		popup_vbox.add_child(b)
	var cancelar := Button.new()
	cancelar.text = "Cancelar"
	cancelar.pressed.connect(func() -> void:
		popup_cem.hide()
		_resetar_modo())
	popup_vbox.add_child(cancelar)
	popup_cem.popup_centered()

func _escolheu_cemiterio(idx: int) -> void:
	alvos["cemiterio_idx"] = idx
	popup_cem.hide()
	_avancar_pendente(_dados_pendentes())


# ---------------------------------------------------------------- botões

func _iniciar_ataque() -> void:
	modo = Modo.ATACANTES
	atacantes_sel = []
	_instr("Clique nos Convocados que vão atacar (destacados) e confirme.")
	_atualizar()

func _confirmar() -> void:
	if modo == Modo.ATACANTES:
		var lista := atacantes_sel.duplicate()
		modo = Modo.NORMAL
		atacantes_sel = []
		var erro := _acao_local({"t": "atacar", "lista": lista})
		_instr(erro)
		if erro != "" and not animando:
			_atualizar()
	elif motor.fase == Motor.Fase.BLOQUEIO:
		_instr(_acao_local({"t": "bloqueios", "pares": bloqueios}))

func _cancelar() -> void:
	_instr("")
	_resetar_modo()

func _encerrar() -> void:
	if modo != Modo.NORMAL:
		return
	_instr(_acao_local({"t": "encerrar"}))


# ---------------------------------------------------------------- IA

func _verificar_ia() -> void:
	if Rede.ativo or ia_ocupada or motor.fase == Motor.Fase.FIM:
		return
	if motor.em_fase_principal() and motor.jogador_ativo().eh_ia:
		_rodar_ia()
	elif motor.fase == Motor.Fase.BLOQUEIO and motor.defensor().eh_ia:
		_bloquear_ia()
	elif motor.fase == Motor.Fase.DESCARTE and motor.jogador_ativo().eh_ia:
		while motor.fase == Motor.Fase.DESCARTE and motor.jogador_ativo().eh_ia:
			motor.descartar(IA.escolher_descarte(motor))

func _rodar_ia() -> void:
	ia_ocupada = true
	while motor.fase != Motor.Fase.FIM and motor.em_fase_principal() \
			and motor.jogador_ativo().eh_ia:
		await get_tree().create_timer(Opcoes.velocidade_ia).timeout
		while animando:
			await get_tree().process_frame
		if motor.fase == Motor.Fase.FIM or not motor.em_fase_principal() \
				or not motor.jogador_ativo().eh_ia:
			break
		var acao := IA.proxima_acao(motor)
		match str(acao["tipo"]):
			"carta":
				motor.jogar_carta(acao["idx"], acao["alvos"])
			"comando":
				motor.ativar_comando(acao["alvos"])
			"reliquia":
				motor.ativar_reliquia(acao["inst"])
			"passar":
				if motor.fase == Motor.Fase.PRINCIPAL_1 and not motor.combate_feito:
					motor.declarar_atacantes(IA.escolher_atacantes(motor))
					if motor.fase == Motor.Fase.BLOQUEIO:
						break  # humano defende
				else:
					motor.encerrar_turno()
					break
	ia_ocupada = false
	call_deferred("_verificar_ia")

func _bloquear_ia() -> void:
	ia_ocupada = true
	await get_tree().create_timer(maxf(Opcoes.velocidade_ia, 0.5)).timeout
	if motor.fase == Motor.Fase.BLOQUEIO:
		motor.declarar_bloqueios(IA.escolher_bloqueios(motor))
	ia_ocupada = false
	call_deferred("_verificar_ia")


# ---------------------------------------------------------------- utilidades

func _fim_de_jogo(vencedor: int) -> void:
	Som.falar(motor.jogadores[vencedor].comandante["id"], "vitoria", true)
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		Som.falar(motor.jogadores[1 - vencedor].comandante["id"], "derrota", true))
	var dlg := AcceptDialog.new()
	dlg.title = "Fim da Partida"
	dlg.dialog_text = "🏆 %s vence o duelo!" % motor.jogadores[vencedor].nome()
	dlg.confirmed.connect(_voltar_ao_menu)
	add_child(dlg)
	dlg.popup_centered()

func _ao_desconectar() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Conexão perdida"
	dlg.dialog_text = "O oponente desconectou da partida."
	dlg.confirmed.connect(_voltar_ao_menu)
	add_child(dlg)
	dlg.popup_centered()

func _voltar_ao_menu() -> void:
	if Rede.ativo:
		Rede.encerrar()
	get_tree().change_scene_to_file("res://scenes/menu_principal.tscn")

## Usa a arte da mesa se existir (aceita .png/.jpg/.jpeg/.webp); senão, cor sólida.
## Um véu escuro por cima mantém as cartas legíveis sobre qualquer arte.
func _montar_fundo(base: String, escurecer: float) -> void:
	var textura: Texture2D = null
	for ext in ["png", "jpg", "jpeg", "webp"]:
		if ResourceLoader.exists("%s.%s" % [base, ext], "Texture2D"):
			textura = load("%s.%s" % [base, ext])
			break
	if textura != null:
		var tex := TextureRect.new()
		tex.texture = textura
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tex)
		var veu := ColorRect.new()
		veu.color = Color(0.02, 0.02, 0.04, escurecer)
		veu.set_anchors_preset(Control.PRESET_FULL_RECT)
		veu.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(veu)
	else:
		var fundo := ColorRect.new()
		fundo.color = Color(0.07, 0.08, 0.10)
		fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
		fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fundo)

func _log(texto: String) -> void:
	if log_rt != null:
		log_rt.append_text(texto + "\n")

func _instr(texto: String) -> void:
	lbl_instrucao.text = texto

func _limpar(no: Node) -> void:
	for filho in no.get_children():
		no.remove_child(filho)
		filho.queue_free()
