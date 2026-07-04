class_name CartaVisual
extends PanelContainer
## Widget de carta: renderiza dados do banco (mão) ou uma InstanciaCarta (Campo).
## Carrega a arte de dados["arte"] se o PNG existir; senão usa placeholder da cor da facção.

signal clicada(visual: CartaVisual)

const CORES_FACCAO := {
	"Coroa Radiante": Color(0.85, 0.72, 0.35),
	"Vínculo Selvagem": Color(0.30, 0.58, 0.32),
	"Véu das Sombras": Color(0.52, 0.34, 0.66),
	"Corrente do Caos": Color(0.80, 0.33, 0.22),
}
const COR_INCOLOR := Color(0.55, 0.55, 0.58)

var dados: Dictionary = {}
var instancia: InstanciaCarta = null
var motor: Motor = null
var _estilo: StyleBoxFlat
var _selo: Label = null

static func cor_de_faccao(faccoes: Array) -> Color:
	if faccoes.is_empty():
		return COR_INCOLOR
	return CORES_FACCAO.get(str(faccoes[0]), COR_INCOLOR)

func configurar(p_dados: Dictionary, p_motor: Motor = null, p_instancia: InstanciaCarta = null,
		tamanho := Vector2(112, 152)) -> void:
	dados = p_dados
	motor = p_motor
	instancia = p_instancia
	custom_minimum_size = tamanho
	_construir()

func _construir() -> void:
	_estilo = StyleBoxFlat.new()
	_estilo.bg_color = Color(0.13, 0.13, 0.17)
	_estilo.border_color = cor_de_faccao(dados.get("faccao", []))
	_estilo.set_border_width_all(2)
	_estilo.set_corner_radius_all(6)
	_estilo.content_margin_left = 5
	_estilo.content_margin_right = 5
	_estilo.content_margin_top = 4
	_estilo.content_margin_bottom = 4
	add_theme_stylebox_override("panel", _estilo)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = _descricao()

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	add_child(v)

	var topo := HBoxContainer.new()
	topo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(topo)
	var nome := _label(str(dados.get("nome", "?")), 10)
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nome.clip_text = true
	topo.add_child(nome)
	if dados.has("custo"):
		topo.add_child(_label(_texto_custo(), 10))

	var arte := _no_de_arte()
	arte.custom_minimum_size = Vector2(0, custom_minimum_size.y * 0.34)
	v.add_child(arte)

	v.add_child(_label(_linha_de_tipo(), 8))

	var texto := _texto_de_regras()
	if texto != "":
		var lbl := _label(texto, 8)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(lbl)
	else:
		var vazio := Control.new()
		vazio.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vazio.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(vazio)

	if dados.get("tipo", "") == "Convocado":
		var stats := _label(_texto_stats(), 11)
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.add_child(stats)

	if instancia != null and instancia.usada:
		modulate = Color(0.55, 0.55, 0.55)
	elif instancia != null and instancia.eh_convocado() and instancia.entrou_neste_turno \
			and motor != null and not motor.tem_kw(instancia, "Investida"):
		modulate = Color(0.75, 0.75, 0.85)  # mal de invocação

func _no_de_arte() -> Control:
	var caminho := str(dados.get("arte", ""))
	if caminho != "" and ResourceLoader.exists(caminho, "Texture2D"):
		var tex := TextureRect.new()
		tex.texture = load(caminho)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tex
	var cor := ColorRect.new()
	cor.color = cor_de_faccao(dados.get("faccao", [])).darkened(0.45)
	cor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cor

func _texto_custo() -> String:
	var custo: Dictionary = dados.get("custo", {})
	var partes: Array = []
	var inc := int(custo.get("incolor", 0))
	if inc > 0 or BancoDados.custo_faccao(custo) == 0:
		partes.append(str(inc))
	for chave in custo:
		if chave != "incolor" and int(custo[chave]) > 0:
			partes.append("%d◆" % int(custo[chave]))
	return "".join(partes) if partes.size() <= 1 else "+".join(partes)

func _linha_de_tipo() -> String:
	var linha := str(dados.get("tipo", ""))
	if str(dados.get("subtipo", "")) != "":
		linha += " — " + str(dados.get("subtipo", ""))
	return linha

func _texto_de_regras() -> String:
	var partes: Array = []
	var kws: Array = dados.get("palavras_chave", [])
	if instancia != null:
		for kw in instancia.kw_temporarias:
			if not kw in kws:
				kws = kws + [kw]
	if not kws.is_empty():
		partes.append(", ".join(kws))
	var texto := str(dados.get("texto_efeito", ""))
	if texto != "":
		partes.append(texto.replace("[", "").replace("]", ""))
	return "\n".join(partes)

func _texto_stats() -> String:
	if instancia != null and motor != null:
		var p := motor.poder_de(instancia)
		var r := motor.res_de(instancia) - instancia.dano_marcado
		return "%d/%d" % [p, r]
	return "%d/%d" % [int(dados.get("poder", 0)), int(dados.get("resiliencia", 0))]

func _descricao() -> String:
	var linhas: Array = [str(dados.get("nome", "?")), _linha_de_tipo()]
	if dados.has("custo"):
		linhas.append("Custo: " + _texto_custo())
	var regras := _texto_de_regras()
	if regras != "":
		linhas.append(regras)
	if str(dados.get("texto_flavor", "")) != "":
		linhas.append("« %s »" % dados["texto_flavor"])
	return "\n".join(linhas)

func destacar(cor: Color) -> void:
	_estilo.border_color = cor
	_estilo.set_border_width_all(4)

func definir_selo(texto: String) -> void:
	if _selo == null:
		_selo = _label("", 12)
		_selo.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_selo.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		add_child(_selo)
	_selo.text = texto

func _label(texto: String, tamanho_fonte: int) -> Label:
	var lbl := Label.new()
	lbl.text = texto
	lbl.add_theme_font_size_override("font_size", tamanho_fonte)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

func _gui_input(evento: InputEvent) -> void:
	if evento is InputEventMouseButton and evento.pressed \
			and evento.button_index == MOUSE_BUTTON_LEFT:
		clicada.emit(self)
