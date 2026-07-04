class_name CartaVisual
extends Control
## Widget de carta com TAMANHO FIXO (o conteúdo é recortado, nunca estica a carta).
## Renderiza dados do banco (mão) ou uma InstanciaCarta (Campo).
## Carrega a arte de dados["arte"] se o PNG existir; senão usa placeholder da facção.
## Acabamentos: dados["acabamento"] == "foil" | "holo" aplicam shader por cima.
## Clique esquerdo → `clicada`; clique direito → `detalhes` (visualização ampliada).

signal clicada(visual: CartaVisual)
signal detalhes(visual: CartaVisual)

const CORES_FACCAO := {
	"Coroa Radiante": Color(0.85, 0.72, 0.35),
	"Vínculo Selvagem": Color(0.30, 0.58, 0.32),
	"Véu das Sombras": Color(0.52, 0.34, 0.66),
	"Corrente do Caos": Color(0.80, 0.33, 0.22),
}
const COR_INCOLOR := Color(0.55, 0.55, 0.58)
const TAM_BASE := 112.0  # largura de referência para a escala das fontes

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
	size = tamanho
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = descricao()
	_construir(tamanho)

func _construir(tam: Vector2) -> void:
	var e := tam.x / TAM_BASE  # escala tipográfica

	var painel := Panel.new()
	painel.set_anchors_preset(Control.PRESET_FULL_RECT)
	painel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_estilo = StyleBoxFlat.new()
	_estilo.bg_color = Color(0.13, 0.13, 0.17)
	_estilo.border_color = cor_de_faccao(dados.get("faccao", []))
	_estilo.set_border_width_all(maxi(int(2 * e), 2))
	_estilo.set_corner_radius_all(int(6 * e))
	painel.add_theme_stylebox_override("panel", _estilo)
	add_child(painel)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6 * e
	v.offset_right = -6 * e
	v.offset_top = 5 * e
	v.offset_bottom = -5 * e
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", int(2 * e))
	add_child(v)

	var topo := HBoxContainer.new()
	topo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(topo)
	var nome := _label(str(dados.get("nome", "?")), int(10 * e))
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nome.clip_text = true
	topo.add_child(nome)
	if dados.has("custo"):
		topo.add_child(_label(_texto_custo(), int(10 * e)))

	var arte := _no_de_arte()
	arte.custom_minimum_size = Vector2(0, tam.y * 0.34)
	v.add_child(arte)

	v.add_child(_label(_linha_de_tipo(), int(8 * e)))

	var texto := _texto_de_regras()
	if texto != "":
		var lbl := _label(texto, int(8 * e))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		lbl.clip_contents = true
		v.add_child(lbl)
	else:
		var vazio := Control.new()
		vazio.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vazio.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(vazio)

	if dados.get("tipo", "") == "Convocado":
		var stats := _label(_texto_stats(), int(11 * e))
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.add_child(stats)

	_aplicar_acabamento(e)

	if instancia != null and instancia.usada:
		modulate = Color(0.55, 0.55, 0.55)
	elif instancia != null and instancia.eh_convocado() and instancia.entrou_neste_turno \
			and motor != null and not motor.tem_kw(instancia, "Investida"):
		modulate = Color(0.75, 0.75, 0.85)  # mal de invocação

func _aplicar_acabamento(e: float) -> void:
	var acabamento := str(dados.get("acabamento", ""))
	if acabamento != "foil" and acabamento != "holo":
		return
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/%s.gdshader" % acabamento)
	overlay.material = mat
	add_child(overlay)
	# Etiqueta discreta do acabamento no rodapé esquerdo.
	var etiqueta := _label("✦ FOIL" if acabamento == "foil" else "★ HOLO", int(7 * e))
	etiqueta.add_theme_color_override("font_color", Color(0.9, 0.85, 1.0, 0.8))
	etiqueta.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	etiqueta.position = Vector2(6 * e, size.y - 14 * e)
	add_child(etiqueta)

func _no_de_arte() -> Control:
	var caminho := str(dados.get("arte", ""))
	if caminho != "" and ResourceLoader.exists(caminho, "Texture2D"):
		var tex := TextureRect.new()
		tex.texture = load(caminho)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.clip_contents = true
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

func descricao() -> String:
	var linhas: Array = [str(dados.get("nome", "?")), _linha_de_tipo()]
	if dados.has("custo"):
		linhas.append("Custo: " + _texto_custo())
	if dados.get("tipo", "") == "Convocado":
		linhas.append("Poder/Resiliência: " + _texto_stats())
	var regras := _texto_de_regras()
	if regras != "":
		linhas.append(regras)
	if str(dados.get("texto_flavor", "")) != "":
		linhas.append("« %s »" % dados["texto_flavor"])
	if str(dados.get("acabamento", "")) != "":
		linhas.append("Acabamento: " + str(dados["acabamento"]).to_upper())
	return "\n".join(linhas)

func destacar(cor: Color) -> void:
	_estilo.border_color = cor
	_estilo.set_border_width_all(4)

func definir_selo(texto: String) -> void:
	if _selo == null:
		_selo = _label("", 12)
		_selo.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		add_child(_selo)
		_selo.position = Vector2(size.x / 2.0 - 12, 2)
	_selo.text = texto

func _label(texto: String, tamanho_fonte: int) -> Label:
	var lbl := Label.new()
	lbl.text = texto
	lbl.add_theme_font_size_override("font_size", tamanho_fonte)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

func _gui_input(evento: InputEvent) -> void:
	if evento is InputEventMouseButton and evento.pressed:
		if evento.button_index == MOUSE_BUTTON_LEFT:
			clicada.emit(self)
		elif evento.button_index == MOUSE_BUTTON_RIGHT:
			detalhes.emit(self)
