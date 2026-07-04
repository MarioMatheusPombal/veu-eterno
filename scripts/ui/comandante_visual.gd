class_name ComandanteVisual
extends PanelContainer
## Painel do Trono: Comandante com Vida, Passiva e botão da Habilidade de Comando.

signal clicado(visual: ComandanteVisual)
signal comando_pressionado

var comandante: Dictionary = {}
var indice_jogador := 0
var _estilo: StyleBoxFlat

func configurar(p_comandante: Dictionary, vida: int, p_indice: int,
		mostrar_botao: bool, botao_habilitado: bool) -> void:
	comandante = p_comandante
	indice_jogador = p_indice
	custom_minimum_size = Vector2(190, 150)
	_estilo = StyleBoxFlat.new()
	_estilo.bg_color = Color(0.10, 0.10, 0.14)
	_estilo.border_color = CartaVisual.cor_de_faccao(comandante.get("faccao", []))
	_estilo.set_border_width_all(3)
	_estilo.set_corner_radius_all(8)
	_estilo.content_margin_left = 8
	_estilo.content_margin_right = 8
	_estilo.content_margin_top = 6
	_estilo.content_margin_bottom = 6
	add_theme_stylebox_override("panel", _estilo)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var hc: Dictionary = comandante.get("habilidade_comando", {})
	tooltip_text = "%s\n%s\nPassiva: %s\nComando — %s: %s" % [
		comandante.get("nome", "?"),
		", ".join(comandante.get("faccao", [])),
		comandante.get("habilidade_passiva", ""),
		_texto_custo(hc.get("custo", {}), str(hc.get("custo_adicional", ""))),
		hc.get("texto", ""),
	]

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	add_child(v)

	var nome := Label.new()
	nome.text = str(comandante.get("nome", "?"))
	nome.add_theme_font_size_override("font_size", 11)
	nome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nome)

	var lbl_vida := Label.new()
	lbl_vida.text = "❤ %d" % vida
	lbl_vida.add_theme_font_size_override("font_size", 22)
	lbl_vida.add_theme_color_override("font_color",
			Color(0.9, 0.35, 0.35) if vida <= 5 else Color(0.9, 0.85, 0.8))
	lbl_vida.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(lbl_vida)

	var passiva := Label.new()
	passiva.text = str(comandante.get("habilidade_passiva", ""))
	passiva.add_theme_font_size_override("font_size", 8)
	passiva.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	passiva.size_flags_vertical = Control.SIZE_EXPAND_FILL
	passiva.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(passiva)

	if mostrar_botao:
		var btn := Button.new()
		btn.text = "Comando (%s)" % _texto_custo(hc.get("custo", {}), str(hc.get("custo_adicional", "")))
		btn.add_theme_font_size_override("font_size", 10)
		btn.disabled = not botao_habilitado
		btn.tooltip_text = str(hc.get("texto", ""))
		btn.pressed.connect(func() -> void: comando_pressionado.emit())
		v.add_child(btn)

func _texto_custo(custo: Dictionary, adicional: String) -> String:
	var texto := str(int(custo.get("incolor", 0)))
	if adicional == "sacrificar_convocado":
		texto += " + sacrifício"
	return texto

func destacar(cor: Color) -> void:
	_estilo.border_color = cor
	_estilo.set_border_width_all(4)

func _gui_input(evento: InputEvent) -> void:
	if evento is InputEventMouseButton and evento.pressed \
			and evento.button_index == MOUSE_BUTTON_LEFT:
		clicado.emit(self)
