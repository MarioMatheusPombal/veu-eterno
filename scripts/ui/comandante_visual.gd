class_name ComandanteVisual
extends Control
## Painel do Trono: retrato do Comandante, Vida, Passiva e botão da Habilidade de Comando.
## Tamanho fixo (não estica). Clique esquerdo → `clicado`; direito → `detalhes`.

signal clicado(visual: ComandanteVisual)
signal detalhes(visual: ComandanteVisual)
signal comando_pressionado

const TAM_BASE := 196.0

var comandante: Dictionary = {}
var indice_jogador := 0
var _estilo: StyleBoxFlat

func configurar(p_comandante: Dictionary, vida: int, p_indice: int,
		mostrar_botao: bool, botao_habilitado: bool,
		tamanho := Vector2(196, 224)) -> void:
	comandante = p_comandante
	indice_jogador = p_indice
	custom_minimum_size = tamanho
	size = tamanho
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var e := tamanho.x / TAM_BASE

	var painel := Panel.new()
	painel.set_anchors_preset(Control.PRESET_FULL_RECT)
	painel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_estilo = StyleBoxFlat.new()
	_estilo.bg_color = Color(0.10, 0.10, 0.14)
	_estilo.border_color = CartaVisual.cor_de_faccao(comandante.get("faccao", []))
	_estilo.set_border_width_all(maxi(int(3 * e), 3))
	_estilo.set_corner_radius_all(int(8 * e))
	painel.add_theme_stylebox_override("panel", _estilo)
	add_child(painel)

	var hc: Dictionary = comandante.get("habilidade_comando", {})
	tooltip_text = "%s\n%s\nPassiva: %s\nComando — %s: %s\n(Botão direito para ampliar)" % [
		comandante.get("nome", "?"),
		", ".join(comandante.get("faccao", [])),
		comandante.get("habilidade_passiva", ""),
		_texto_custo(hc.get("custo", {}), str(hc.get("custo_adicional", ""))),
		hc.get("texto", ""),
	]

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8 * e
	v.offset_right = -8 * e
	v.offset_top = 6 * e
	v.offset_bottom = -6 * e
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", int(2 * e))
	add_child(v)

	var nome := _label(str(comandante.get("nome", "?")), int(11 * e))
	nome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nome)

	# Retrato: arte do comandante se existir, senão faixa da cor da facção.
	var retrato := _no_de_retrato()
	retrato.custom_minimum_size = Vector2(0, size.y * 0.34)
	v.add_child(retrato)

	var linha_vida := HBoxContainer.new()
	linha_vida.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(linha_vida)
	var lbl_vida := _label("❤ %d" % vida, int(20 * e))
	lbl_vida.add_theme_color_override("font_color",
			Color(0.9, 0.35, 0.35) if vida <= 5 else Color(0.9, 0.85, 0.8))
	linha_vida.add_child(lbl_vida)

	var passiva := _label(str(comandante.get("habilidade_passiva", "")), int(8 * e))
	passiva.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	passiva.size_flags_vertical = Control.SIZE_EXPAND_FILL
	passiva.clip_contents = true
	v.add_child(passiva)

	if mostrar_botao:
		var btn := Button.new()
		btn.text = "Comando (%s)" % _texto_custo(hc.get("custo", {}), str(hc.get("custo_adicional", "")))
		btn.add_theme_font_size_override("font_size", int(10 * e))
		btn.disabled = not botao_habilitado
		btn.tooltip_text = str(hc.get("texto", ""))
		btn.pressed.connect(func() -> void: comando_pressionado.emit())
		v.add_child(btn)

func _no_de_retrato() -> Control:
	var caminho := str(comandante.get("arte", ""))
	if caminho != "" and ResourceLoader.exists(caminho, "Texture2D"):
		var tex := TextureRect.new()
		tex.texture = load(caminho)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.clip_contents = true
		return tex
	var cor := ColorRect.new()
	cor.color = CartaVisual.cor_de_faccao(comandante.get("faccao", [])).darkened(0.45)
	cor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cor

func _texto_custo(custo: Dictionary, adicional: String) -> String:
	var texto := str(int(custo.get("incolor", 0)))
	if adicional == "sacrificar_convocado":
		texto += " + sacrifício"
	return texto

func destacar(cor: Color) -> void:
	_estilo.border_color = cor
	_estilo.set_border_width_all(4)

func _label(texto: String, tamanho_fonte: int) -> Label:
	var lbl := Label.new()
	lbl.text = texto
	lbl.add_theme_font_size_override("font_size", tamanho_fonte)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

func _gui_input(evento: InputEvent) -> void:
	if evento is InputEventMouseButton and evento.pressed:
		if evento.button_index == MOUSE_BUTTON_LEFT:
			clicado.emit(self)
		elif evento.button_index == MOUSE_BUTTON_RIGHT:
			detalhes.emit(self)
