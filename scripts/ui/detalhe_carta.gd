class_name DetalheCarta
extends Control
## Visualização ampliada (botão direito): a carta/comandante é renderizada num
## SubViewport e exibida com shader de tilt 3D que acompanha o mouse.
## Botão ESQUERDO: gira a carta para ver a capa (verso). BOTÃO DIREITO / Esc / ✕: fecha.
## A capa é res://assets/arte/ui/capa_carta.(png|jpg|webp) — trocar o arquivo troca o
## "shield" de todas as cartas; sem arquivo, usa um verso desenhado em código.

const TAM := Vector2i(370, 505)
const CAPA_BASE := "res://assets/arte/ui/capa_carta"

var _viewport: SubViewport        # frente (a carta em si)
var _viewport_verso: SubViewport  # verso (capa)
var _tex: TextureRect
var _mat: ShaderMaterial
var _btn_fechar: Button
var _mostrando_verso := false
var _virando := false

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var fundo := ColorRect.new()
	fundo.color = Color(0, 0, 0, 0.65)
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fundo)

	_viewport = SubViewport.new()
	_viewport.size = TAM
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS  # foil/holo animam
	add_child(_viewport)

	_viewport_verso = SubViewport.new()
	_viewport_verso.size = TAM
	_viewport_verso.transparent_bg = true
	_viewport_verso.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport_verso)
	_montar_verso()

	_tex = TextureRect.new()
	_tex.texture = _viewport.get_texture()
	_tex.custom_minimum_size = Vector2(TAM)
	_tex.size = Vector2(TAM)
	_tex.pivot_offset = Vector2(TAM) / 2.0  # o giro acontece em torno do centro
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/tilt_3d.gdshader")
	_tex.material = _mat
	add_child(_tex)

	var dica := Label.new()
	dica.text = "botão esquerdo: girar a carta · botão direito, Esc ou ✕: fechar"
	dica.add_theme_font_size_override("font_size", 12)
	dica.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 0.8))
	dica.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dica.position = Vector2(-200, -34)
	dica.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dica)

	_btn_fechar = Button.new()
	_btn_fechar.text = "✕"
	_btn_fechar.add_theme_font_size_override("font_size", 20)
	_btn_fechar.custom_minimum_size = Vector2(44, 44)
	_btn_fechar.pressed.connect(fechar)
	add_child(_btn_fechar)

## Verso: usa a arte da capa se existir; senão desenha um verso padrão em código.
func _montar_verso() -> void:
	var textura: Texture2D = null
	for ext in ["png", "jpg", "jpeg", "webp"]:
		if ResourceLoader.exists("%s.%s" % [CAPA_BASE, ext], "Texture2D"):
			textura = load("%s.%s" % [CAPA_BASE, ext])
			break
	if textura != null:
		var tex := TextureRect.new()
		tex.texture = textura
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.size = Vector2(TAM)
		_viewport_verso.add_child(tex)
		return
	# Verso padrão (placeholder): painel escuro com borda dourada e o símbolo do jogo.
	var painel := Panel.new()
	painel.size = Vector2(TAM)
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.09, 0.08, 0.13)
	estilo.border_color = Color(0.72, 0.60, 0.32)
	estilo.set_border_width_all(8)
	estilo.set_corner_radius_all(18)
	painel.add_theme_stylebox_override("panel", estilo)
	_viewport_verso.add_child(painel)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	painel.add_child(v)
	var simbolo := Label.new()
	simbolo.text = "❖"
	simbolo.add_theme_font_size_override("font_size", 110)
	simbolo.add_theme_color_override("font_color", Color(0.72, 0.60, 0.32))
	simbolo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(simbolo)
	var titulo := Label.new()
	titulo.text = "VÉU ETERNO"
	titulo.add_theme_font_size_override("font_size", 34)
	titulo.add_theme_color_override("font_color", Color(0.72, 0.60, 0.32))
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(titulo)

func abrir_carta(dados: Dictionary, motor: Motor = null, instancia: InstanciaCarta = null) -> void:
	_limpar_viewport()
	var carta := CartaVisual.new()
	_viewport.add_child(carta)
	carta.configurar(dados, motor, instancia, Vector2(TAM))
	carta.position = Vector2.ZERO
	_abrir()

func abrir_comandante(cmd: Dictionary, vida: int) -> void:
	_limpar_viewport()
	var painel := ComandanteVisual.new()
	_viewport.add_child(painel)
	painel.configurar(cmd, vida, 0, false, false, Vector2(TAM))
	painel.position = Vector2.ZERO
	_abrir()

func _abrir() -> void:
	_mostrando_verso = false
	_virando = false
	_tex.texture = _viewport.get_texture()
	_tex.scale = Vector2.ONE
	visible = true
	_centralizar()

func fechar() -> void:
	visible = false
	_limpar_viewport()

## Giro 3D: a carta "fecha" na horizontal, troca de lado e "abre" de novo.
func girar() -> void:
	if _virando:
		return
	_virando = true
	var tw := create_tween()
	tw.tween_property(_tex, "scale:x", 0.04, 0.14) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(_trocar_lado)
	tw.tween_property(_tex, "scale:x", 1.0, 0.14) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _virando = false)

func _trocar_lado() -> void:
	_mostrando_verso = not _mostrando_verso
	_tex.texture = _viewport_verso.get_texture() if _mostrando_verso else _viewport.get_texture()

func _limpar_viewport() -> void:
	for filho in _viewport.get_children():
		_viewport.remove_child(filho)
		filho.queue_free()

func _centralizar() -> void:
	_tex.position = (get_viewport_rect().size - Vector2(TAM)) / 2.0
	if _btn_fechar != null:
		_btn_fechar.position = _tex.position + Vector2(TAM.x + 12, -6)

func _process(_delta: float) -> void:
	if not visible:
		return
	_centralizar()
	var centro := _tex.position + Vector2(TAM) / 2.0
	var desvio := get_global_mouse_position() - centro
	var incl := Vector2(
		clampf(desvio.x / (float(TAM.x) * 1.2), -1.0, 1.0),
		clampf(desvio.y / (float(TAM.y) * 1.2), -1.0, 1.0))
	_mat.set_shader_parameter("inclinacao", incl)

# Input global (roda ANTES da etapa de GUI): esquerdo gira, direito/Esc fecha.
func _input(evento: InputEvent) -> void:
	if not visible:
		return
	if evento.is_action_pressed("ui_cancel"):
		fechar()
		get_viewport().set_input_as_handled()
		return
	if evento is InputEventMouseButton and evento.pressed:
		# Deixa o botão ✕ tratar o próprio clique.
		if _btn_fechar.get_global_rect().has_point(get_global_mouse_position()):
			return
		if evento.button_index == MOUSE_BUTTON_LEFT:
			girar()
		elif evento.button_index == MOUSE_BUTTON_RIGHT:
			fechar()
		get_viewport().set_input_as_handled()
