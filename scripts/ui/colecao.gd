extends Control
## Coleção & Loja: coleção do jogador, abertura de boosters, crafting e compra
## de cristais. Tudo vem do servidor via Api — o cliente só exibe o que recebeu
## (nenhum saldo, sorteio ou preço é calculado localmente).

const TAM_CARTA := Vector2(112, 152)
const ORDEM_RARIDADE := {"comum": 0, "incomum": 1, "rara": 2, "mítica": 3}
const COR_RARIDADE := {
	"comum": Color(0.75, 0.75, 0.75), "incomum": Color(0.45, 0.75, 0.45),
	"rara": Color(0.40, 0.60, 0.95), "mítica": Color(0.95, 0.55, 0.20),
}

var possuidas := {}          # carta_id -> quantidade (do servidor)
var lbl_status: Label
var lbl_saldos: Label
var grade: GridContainer
var painel_carta: VBoxContainer  # painel lateral da carta selecionada
var botoes_topo: Array = []
var carta_sel := ""

func _ready() -> void:
	_montar_ui()
	_conectar()

func _conectar() -> void:
	lbl_status.text = "Conectando ao servidor..."
	_habilitar(false)
	var erro: String = await Api.garantir_sessao()
	if not is_instance_valid(lbl_status):
		return  # a tela foi fechada durante o await
	if erro != "":
		lbl_status.text = erro + "  (o jogo local segue funcionando sem servidor)"
		return
	_habilitar(true)
	await _recarregar()

func _habilitar(sim: bool) -> void:
	for b in botoes_topo:
		b.disabled = not sim

## Recarrega perfil + coleção do servidor e reconstrói a tela.
func _recarregar() -> void:
	var p: Dictionary = await Api.perfil()
	var c: Dictionary = await Api.colecao()
	if not is_instance_valid(lbl_status):
		return  # a tela foi fechada durante o await
	if not p.ok or not c.ok:
		lbl_status.text = str(p.dados.get("erro", c.dados.get("erro", "Falha ao carregar.")))
		return
	possuidas.clear()
	for linha in c.dados.get("cartas", []):
		possuidas[str(linha["carta_id"])] = int(linha["quantidade"])
	var boosters := 0
	for b in p.dados.get("boosters", []):
		boosters += int(b["quantidade"])
	var pity: int = int(p.dados.get("pity", {}).get("sem_mitica", 0))
	lbl_saldos.text = "💎 %d Cristais    ✨ %d Pó de Essência    📦 %d Boosters" % [
		int(Api.jogador.get("cristais", 0)), int(Api.jogador.get("po_essencia", 0)), boosters]
	lbl_status.text = "Conectado como %s.  Boosters sem Mítica: %d/%d (garantia no %dº)." % [
		str(Api.jogador.get("nickname", "?")), pity,
		_eco_pity(), _eco_pity()]
	_montar_grade()
	_mostrar_carta(carta_sel)

func _eco_pity() -> int:
	return int(Api.economia.get("booster", {}).get("pity_mitica", 10))

# ---------------------------------------------------------------- UI

func _montar_ui() -> void:
	_montar_fundo()
	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margem.add_theme_constant_override("margin_" + lado, 16)
	add_child(margem)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margem.add_child(v)

	# Cabeçalho: título + saldos + ações.
	var topo := HBoxContainer.new()
	topo.add_theme_constant_override("separation", 10)
	v.add_child(topo)
	var titulo := Label.new()
	titulo.text = "COLEÇÃO & LOJA"
	titulo.add_theme_font_size_override("font_size", 26)
	titulo.add_theme_color_override("font_color", Color(0.88, 0.78, 0.45))
	topo.add_child(titulo)
	lbl_saldos = Label.new()
	lbl_saldos.add_theme_font_size_override("font_size", 15)
	lbl_saldos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_saldos.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	topo.add_child(lbl_saldos)
	botoes_topo.append(_botao(topo, "📦 Comprar booster", _comprar_booster))
	botoes_topo.append(_botao(topo, "✨ Abrir booster", _abrir_booster))
	botoes_topo.append(_botao(topo, "💎 Comprar cristais", _abrir_loja_cristais))
	var btn_voltar := _botao(topo, "← Voltar", func() -> void:
		get_tree().change_scene_to_file("res://scenes/menu_principal.tscn"))

	lbl_status = Label.new()
	lbl_status.add_theme_font_size_override("font_size", 12)
	lbl_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(lbl_status)

	# Corpo: grade de cartas + painel lateral de crafting.
	var corpo := HBoxContainer.new()
	corpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	corpo.add_theme_constant_override("separation", 12)
	v.add_child(corpo)
	var rolagem := ScrollContainer.new()
	rolagem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolagem.size_flags_vertical = Control.SIZE_EXPAND_FILL
	corpo.add_child(rolagem)
	grade = GridContainer.new()
	grade.columns = 10
	grade.add_theme_constant_override("h_separation", 10)
	grade.add_theme_constant_override("v_separation", 10)
	rolagem.add_child(grade)

	painel_carta = VBoxContainer.new()
	painel_carta.custom_minimum_size = Vector2(280, 0)
	painel_carta.add_theme_constant_override("separation", 8)
	corpo.add_child(painel_carta)
	_mostrar_carta("")

	# `btn_voltar` nunca é desabilitado: sem servidor ainda dá para sair da tela.
	btn_voltar.disabled = false

func _botao(pai: Container, texto: String, acao: Callable) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = Vector2(0, 36)
	b.pressed.connect(acao)
	pai.add_child(b)
	return b

func _montar_fundo() -> void:
	var fundo := ColorRect.new()
	fundo.color = Color(0.07, 0.08, 0.10)
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fundo)

## Grade com TODAS as cartas do catálogo; não possuídas ficam escurecidas.
func _montar_grade() -> void:
	for filho in grade.get_children():
		filho.queue_free()
	var ids: Array = BancoDados.cartas.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ca: Dictionary = BancoDados.cartas[a]
		var cb: Dictionary = BancoDados.cartas[b]
		var fa := _primeira_faccao(ca)
		var fb := _primeira_faccao(cb)
		if fa != fb:
			return fa < fb
		var ra: int = ORDEM_RARIDADE.get(str(ca.get("raridade", "comum")), 0)
		var rb: int = ORDEM_RARIDADE.get(str(cb.get("raridade", "comum")), 0)
		if ra != rb:
			return ra < rb
		return str(ca.get("nome", "")) < str(cb.get("nome", "")))
	for id in ids:
		grade.add_child(_celula(id))

## Primeira facção da carta ("" para incolores, que têm faccao = []).
static func _primeira_faccao(dados: Dictionary) -> String:
	var faccoes: Array = dados.get("faccao", [])
	return str(faccoes[0]) if not faccoes.is_empty() else ""

func _celula(id: String) -> Control:
	var dados: Dictionary = BancoDados.cartas[id]
	var caixa := VBoxContainer.new()
	caixa.add_theme_constant_override("separation", 2)
	var visual := CartaVisual.new()
	visual.configurar(dados, null, null, TAM_CARTA)
	visual.clicada.connect(func(_v: CartaVisual) -> void: _mostrar_carta(id))
	visual.detalhes.connect(func(_v: CartaVisual) -> void: _mostrar_carta(id))
	var eh_fonte_basica: bool = dados.get("tipo", "") == "Fonte" and dados.get("basica", false)
	var qtd: int = int(possuidas.get(id, 0))
	if not eh_fonte_basica and qtd == 0:
		visual.modulate = Color(0.35, 0.35, 0.4)
	caixa.add_child(visual)
	var lbl := Label.new()
	lbl.text = "∞" if eh_fonte_basica else "×%d" % qtd
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color",
			COR_RARIDADE.get(str(dados.get("raridade", "comum")), Color.WHITE))
	caixa.add_child(lbl)
	return caixa

## Painel lateral: detalhes + crafting da carta selecionada.
func _mostrar_carta(id: String) -> void:
	carta_sel = id
	for filho in painel_carta.get_children():
		filho.queue_free()
	var titulo := Label.new()
	titulo.add_theme_font_size_override("font_size", 16)
	painel_carta.add_child(titulo)
	if id == "" or not BancoDados.cartas.has(id):
		titulo.text = "Clique numa carta\npara criar ou reciclar."
		return
	var dados: Dictionary = BancoDados.cartas[id]
	var raridade := str(dados.get("raridade", "comum"))
	titulo.text = str(dados.get("nome", "?"))
	titulo.add_theme_color_override("font_color", COR_RARIDADE.get(raridade, Color.WHITE))
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 12)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var qtd: int = int(possuidas.get(id, 0))
	info.text = "Raridade: %s\nCópias: %d" % [raridade.capitalize(), qtd]
	painel_carta.add_child(info)
	if dados.get("tipo", "") == "Fonte" and dados.get("basica", false):
		info.text += "\nFontes básicas são infinitas — fora do crafting."
		return
	var crafting: Dictionary = Api.economia.get("crafting", {})
	var custo_criar: int = int(crafting.get("criar", {}).get(raridade, 0))
	var ganho_reciclar: int = int(crafting.get("reciclar", {}).get(raridade, 0))
	var btn_criar := _botao(painel_carta, "Criar  (−%d ✨)" % custo_criar, func() -> void:
		_executar(Api.criar.bind(id)))
	btn_criar.disabled = custo_criar <= 0
	var btn_reciclar := _botao(painel_carta, "Reciclar 1  (+%d ✨)" % ganho_reciclar,
			func() -> void: _executar(Api.reciclar.bind(id, 1)))
	btn_reciclar.disabled = qtd <= 0

# ---------------------------------------------------------------- ações

## Executa uma chamada da Api (Callable, ex.: Api.criar.bind(id)) e recarrega a
## tela; erros aparecem no status.
func _executar(chamada: Callable) -> void:
	var r: Dictionary = await chamada.call()
	if not is_instance_valid(lbl_status):
		return
	if not r.ok:
		lbl_status.text = "⚠ " + str(r.dados.get("erro", "Falha na operação."))
		return
	await _recarregar()

func _comprar_booster() -> void:
	var preco: int = int(Api.economia.get("booster", {}).get("preco_cristais", 100))
	lbl_status.text = "Comprando booster (%d 💎)..." % preco
	_executar(Api.comprar_booster.bind(1))

func _abrir_booster() -> void:
	lbl_status.text = "Abrindo booster..."
	var r: Dictionary = await Api.abrir_booster()
	if not is_instance_valid(lbl_status):
		return
	if not r.ok:
		lbl_status.text = "⚠ " + str(r.dados.get("erro", "Falha ao abrir."))
		return
	_popup_booster(r.dados.get("cartas", []))
	await _recarregar()

## Revela as 5 cartas sorteadas pelo servidor.
func _popup_booster(ids: Array) -> void:
	var popup := PopupPanel.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	popup.add_child(v)
	var titulo := Label.new()
	titulo.text = "✨ Booster aberto!"
	titulo.add_theme_font_size_override("font_size", 20)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(titulo)
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 12)
	v.add_child(linha)
	for id in ids:
		if not BancoDados.cartas.has(str(id)):
			continue
		var caixa := VBoxContainer.new()
		var visual := CartaVisual.new()
		visual.configurar(BancoDados.cartas[str(id)], null, null, Vector2(140, 190))
		caixa.add_child(visual)
		var lbl := Label.new()
		var raridade := str(BancoDados.cartas[str(id)].get("raridade", "comum"))
		lbl.text = raridade.capitalize()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", COR_RARIDADE.get(raridade, Color.WHITE))
		caixa.add_child(lbl)
		linha.add_child(caixa)
	var btn := Button.new()
	btn.text = "Continuar"
	btn.pressed.connect(func() -> void: popup.hide())
	v.add_child(btn)
	add_child(popup)
	popup.popup_centered()

## Loja de cristais: pacotes vêm do servidor; taxas de drop exibidas junto
## (exigência da Steam para microtransações aleatórias).
func _abrir_loja_cristais() -> void:
	var r: Dictionary = await Api.pacotes_cristais()
	if not is_instance_valid(lbl_status):
		return
	if not r.ok:
		lbl_status.text = "⚠ " + str(r.dados.get("erro", "Loja indisponível."))
		return
	var popup := PopupPanel.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	popup.add_child(v)
	var titulo := Label.new()
	titulo.text = "💎 Cristais de Essência"
	titulo.add_theme_font_size_override("font_size", 18)
	v.add_child(titulo)
	if bool(r.dados.get("simulada", false)):
		var aviso := Label.new()
		aviso.text = "(Loja de desenvolvimento: crédito imediato, sem cobrança.)"
		aviso.add_theme_font_size_override("font_size", 11)
		v.add_child(aviso)
	for pacote in r.dados.get("pacotes", []):
		var id_pacote := str(pacote["id"])
		var btn := Button.new()
		btn.text = "%s — %d 💎 — R$ %.2f" % [str(pacote["nome"]),
				int(pacote["cristais"]), int(pacote["brl_centavos"]) / 100.0]
		btn.custom_minimum_size = Vector2(360, 36)
		btn.pressed.connect(func() -> void:
			popup.hide()
			lbl_status.text = "Processando compra..."
			_executar(Api.comprar_pacote.bind(id_pacote)))
		v.add_child(btn)
	var drop := Label.new()
	drop.text = _texto_taxas_de_drop()
	drop.add_theme_font_size_override("font_size", 11)
	drop.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drop.custom_minimum_size = Vector2(380, 0)
	v.add_child(drop)
	var fechar := Button.new()
	fechar.text = "Fechar"
	fechar.pressed.connect(func() -> void: popup.hide())
	v.add_child(fechar)
	add_child(popup)
	popup.popup_centered()

func _texto_taxas_de_drop() -> String:
	var booster: Dictionary = Api.economia.get("booster", {})
	var pct: Dictionary = booster.get("slot_final_pct", {})
	var partes: Array = []
	for raridade in pct:
		partes.append("%s %d%%" % [str(raridade).capitalize(), int(pct[raridade])])
	return ("Cada booster (%d 💎) traz 5 cartas: 3 Comuns, 1 Incomum e 1 carta final — %s.\n" +
			"Garantia: 1 Mítica a cada %d boosters (pity).") % [
			int(booster.get("preco_cristais", 100)), " / ".join(partes),
			int(booster.get("pity_mitica", 10))]
