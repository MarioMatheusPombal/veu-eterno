class_name DetalheCarta
extends Control
## Visualização ampliada (botão direito): a carta/comandante é renderizada num
## SubViewport e exibida com shader de tilt 3D que acompanha o mouse.
## Fecha com qualquer clique ou Esc.

const TAM := Vector2i(370, 505)

var _viewport: SubViewport
var _tex: TextureRect
var _mat: ShaderMaterial
var _btn_fechar: Button

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

	_tex = TextureRect.new()
	_tex.texture = _viewport.get_texture()
	_tex.custom_minimum_size = Vector2(TAM)
	_tex.size = Vector2(TAM)
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/tilt_3d.gdshader")
	_tex.material = _mat
	add_child(_tex)

	var dica := Label.new()
	dica.text = "clique em qualquer lugar, Esc ou ✕ para fechar · mova o mouse para girar"
	dica.add_theme_font_size_override("font_size", 12)
	dica.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 0.8))
	dica.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dica.position = Vector2(-210, -34)
	dica.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dica)

	var btn_fechar := Button.new()
	btn_fechar.text = "✕"
	btn_fechar.add_theme_font_size_override("font_size", 20)
	btn_fechar.custom_minimum_size = Vector2(44, 44)
	btn_fechar.pressed.connect(fechar)
	add_child(btn_fechar)
	_btn_fechar = btn_fechar

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
	visible = true
	_centralizar()

func fechar() -> void:
	visible = false
	_limpar_viewport()

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

# Fechamento tratado em _input (roda ANTES da etapa de GUI): nenhum outro controle
# consegue "engolir" o clique. O clique que ABRE o detalhe não fecha, porque o _input
# dele roda enquanto o painel ainda está invisível.
func _input(evento: InputEvent) -> void:
	if not visible:
		return
	var clique: bool = evento is InputEventMouseButton and evento.pressed
	if clique or evento.is_action_pressed("ui_cancel"):
		fechar()
		get_viewport().set_input_as_handled()
