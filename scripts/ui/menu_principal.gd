extends Control
## Menu principal com telas: Principal, Jogar Local, Jogar por IP e Opções.

const ORDEM := ["ordwyn", "sylvaine", "nyx", "korrath"]

var telas := {}
# Tela local
var sel := [-1, -1]
var opcao_modo: OptionButton
var btn_iniciar_local: Button
var grupos: Array = [[], []]
# Tela IP
var campo_ip: LineEdit
var campo_porta: LineEdit
var lbl_status: Label
var lbl_escolhas: Label
var grupo_rede: Array = []
var btn_iniciar_rede: Button

func _ready() -> void:
	if Rede.ativo or Rede.conectado:
		Rede.encerrar()
	_montar_fundo("res://assets/arte/ui/fundo_menu", 0.45)
	telas["principal"] = _tela_principal()
	telas["local"] = _tela_local()
	telas["ip"] = _tela_ip()
	telas["opcoes"] = _tela_opcoes()
	for nome in telas:
		add_child(telas[nome])
	Rede.status_mudou.connect(func(t: String) -> void: lbl_status.text = t)
	Rede.lobby_mudou.connect(_atualizar_lobby)
	_mostrar("principal")

func _mostrar(nome: String) -> void:
	for t in telas:
		telas[t].visible = t == nome

## Usa a arte de fundo se existir (aceita .png/.jpg/.jpeg/.webp); senão, cor sólida.
## Um véu escuro por cima garante a legibilidade do texto em qualquer arte.
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

func _centro_com_vbox() -> Array:
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	centro.add_child(v)
	return [centro, v]

func _titulo(v: VBoxContainer) -> void:
	var titulo := Label.new()
	titulo.text = "VÉU ETERNO"
	titulo.add_theme_font_size_override("font_size", 44)
	titulo.add_theme_color_override("font_color", Color(0.88, 0.78, 0.45))
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(titulo)

func _botao(v: VBoxContainer, texto: String, acao: Callable, altura := 40) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = Vector2(320, altura)
	b.pressed.connect(acao)
	v.add_child(b)
	return b

func _rotulo(v: VBoxContainer, texto: String, tamanho := 13) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tamanho)
	v.add_child(l)
	return l


# ---------------------------------------------------------------- telas

func _tela_principal() -> Control:
	var par := _centro_com_vbox()
	var v: VBoxContainer = par[1]
	_titulo(v)
	var sub := _rotulo(v, "Dois Duelistas. Dois Comandantes. Um só sai do Véu.", 12)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_botao(v, "⚔  Jogar (neste PC)", func() -> void: _mostrar("local"))
	_botao(v, "🌐  Jogar por IP", func() -> void: _mostrar("ip"))
	_botao(v, "⚙  Opções", func() -> void: _mostrar("opcoes"))
	_botao(v, "Sair", func() -> void: get_tree().quit())
	return par[0]

func _tela_local() -> Control:
	var par := _centro_com_vbox()
	var v: VBoxContainer = par[1]
	_titulo(v)
	opcao_modo = OptionButton.new()
	opcao_modo.add_item("1 Jogador — contra a IA")
	opcao_modo.add_item("2 Jogadores — no mesmo PC")
	v.add_child(opcao_modo)
	for p in 2:
		_rotulo(v, "Comandante do Jogador 1" if p == 0 else "Comandante do Jogador 2 / IA")
		var linha := HBoxContainer.new()
		linha.add_theme_constant_override("separation", 8)
		v.add_child(linha)
		for i in ORDEM.size():
			var btn := _botao_comandante(ORDEM[i])
			btn.pressed.connect(_selecionar_local.bind(p, i))
			linha.add_child(btn)
			grupos[p].append(btn)
	btn_iniciar_local = _botao(v, "⚔  Iniciar Duelo", _iniciar_local, 44)
	btn_iniciar_local.disabled = true
	_botao(v, "← Voltar", (func() -> void: _mostrar("principal")), 32)
	return par[0]

func _tela_ip() -> Control:
	var par := _centro_com_vbox()
	var v: VBoxContainer = par[1]
	_titulo(v)
	_rotulo(v, "Partida por IP — funciona em LAN e VPNs como Radmin/Hamachi.", 11)
	var linha_ip := HBoxContainer.new()
	linha_ip.add_theme_constant_override("separation", 8)
	v.add_child(linha_ip)
	campo_ip = LineEdit.new()
	campo_ip.placeholder_text = "IP do host (ex.: 26.12.34.56)"
	campo_ip.custom_minimum_size = Vector2(280, 0)
	linha_ip.add_child(campo_ip)
	campo_porta = LineEdit.new()
	campo_porta.text = str(Rede.PORTA_PADRAO)
	campo_porta.custom_minimum_size = Vector2(80, 0)
	campo_porta.tooltip_text = "Porta (o host precisa liberá-la no firewall)"
	linha_ip.add_child(campo_porta)
	var linha_botoes := HBoxContainer.new()
	linha_botoes.add_theme_constant_override("separation", 8)
	v.add_child(linha_botoes)
	var btn_host := Button.new()
	btn_host.text = "Criar Sala (Host)"
	btn_host.custom_minimum_size = Vector2(180, 36)
	btn_host.pressed.connect(func() -> void:
		var erro := Rede.hospedar(int(campo_porta.text) if campo_porta.text.is_valid_int() else Rede.PORTA_PADRAO)
		if erro != "":
			lbl_status.text = erro)
	linha_botoes.add_child(btn_host)
	var btn_conectar := Button.new()
	btn_conectar.text = "Conectar"
	btn_conectar.custom_minimum_size = Vector2(180, 36)
	btn_conectar.pressed.connect(func() -> void:
		var erro := Rede.conectar(campo_ip.text, int(campo_porta.text) if campo_porta.text.is_valid_int() else Rede.PORTA_PADRAO)
		if erro != "":
			lbl_status.text = erro)
	linha_botoes.add_child(btn_conectar)
	lbl_status = _rotulo(v, "Crie uma sala ou conecte-se a uma.", 11)
	lbl_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_status.custom_minimum_size = Vector2(380, 0)
	_rotulo(v, "Seu Comandante:")
	var linha_cmd := HBoxContainer.new()
	linha_cmd.add_theme_constant_override("separation", 8)
	v.add_child(linha_cmd)
	for i in ORDEM.size():
		var btn := _botao_comandante(ORDEM[i])
		btn.pressed.connect(_selecionar_rede.bind(i))
		linha_cmd.add_child(btn)
		grupo_rede.append(btn)
	lbl_escolhas = _rotulo(v, "", 11)
	btn_iniciar_rede = _botao(v, "⚔  Iniciar Duelo (host)", (func() -> void: Rede.iniciar_partida()), 40)
	btn_iniciar_rede.disabled = true
	_botao(v, "← Voltar", _voltar_do_ip, 32)
	return par[0]

func _voltar_do_ip() -> void:
	Rede.encerrar()
	_mostrar("principal")

func _tela_opcoes() -> Control:
	var par := _centro_com_vbox()
	var v: VBoxContainer = par[1]
	_titulo(v)
	_rotulo(v, "Opções", 18)
	var chk_tela := CheckButton.new()
	chk_tela.text = "Tela cheia"
	chk_tela.button_pressed = Opcoes.tela_cheia
	chk_tela.toggled.connect(func(valor: bool) -> void: Opcoes.definir_tela_cheia(valor))
	v.add_child(chk_tela)
	var chk_anim := CheckButton.new()
	chk_anim.text = "Animações de combate"
	chk_anim.button_pressed = Opcoes.animacoes
	chk_anim.toggled.connect(func(valor: bool) -> void:
		Opcoes.animacoes = valor
		Opcoes.salvar())
	v.add_child(chk_anim)
	var chk_tremor := CheckButton.new()
	chk_tremor.text = "Tremor de tela ao sofrer dano"
	chk_tremor.button_pressed = Opcoes.tremor
	chk_tremor.toggled.connect(func(valor: bool) -> void:
		Opcoes.tremor = valor
		Opcoes.salvar())
	v.add_child(chk_tremor)
	_rotulo(v, "Velocidade da IA (segundos por ação):", 12)
	var slider := HSlider.new()
	slider.min_value = 0.2
	slider.max_value = 1.5
	slider.step = 0.1
	slider.value = Opcoes.velocidade_ia
	slider.custom_minimum_size = Vector2(320, 0)
	slider.value_changed.connect(func(valor: float) -> void:
		Opcoes.velocidade_ia = valor
		Opcoes.salvar())
	v.add_child(slider)
	_botao(v, "← Voltar", (func() -> void: _mostrar("principal")), 32)
	return par[0]


# ---------------------------------------------------------------- ações

func _botao_comandante(id_cmd: String) -> Button:
	var cmd: Dictionary = BancoDados.comandantes[id_cmd]
	var btn := Button.new()
	btn.toggle_mode = true
	btn.text = "%s\n(%s)" % [cmd["nome"], ", ".join(cmd["faccao"])]
	btn.add_theme_font_size_override("font_size", 10)
	btn.custom_minimum_size = Vector2(180, 52)
	btn.self_modulate = CartaVisual.cor_de_faccao(cmd["faccao"])
	btn.tooltip_text = "Passiva: %s\nComando: %s" % [
		cmd["habilidade_passiva"], cmd["habilidade_comando"]["texto"]]
	return btn

func _selecionar_local(p: int, i: int) -> void:
	sel[p] = i
	for k in grupos[p].size():
		grupos[p][k].button_pressed = k == i
	btn_iniciar_local.disabled = sel[0] < 0 or sel[1] < 0

func _iniciar_local() -> void:
	BancoDados.config_partida = {"jogadores": [
		{"comandante": ORDEM[sel[0]], "eh_ia": false},
		{"comandante": ORDEM[sel[1]], "eh_ia": opcao_modo.selected == 0},
	]}
	get_tree().change_scene_to_file("res://scenes/partida.tscn")

func _selecionar_rede(i: int) -> void:
	for k in grupo_rede.size():
		grupo_rede[k].button_pressed = k == i
	Rede.escolher_comandante(ORDEM[i])

func _atualizar_lobby() -> void:
	var nomes: Array = []
	for lugar in 2:
		var id_cmd: String = Rede.comandantes[lugar]
		var nome: String = BancoDados.comandantes[id_cmd]["nome"] if id_cmd != "" else "—"
		nomes.append("J%d: %s" % [lugar + 1, nome])
	lbl_escolhas.text = " | ".join(nomes)
	btn_iniciar_rede.disabled = not (Rede.meu_lugar == 0 and Rede.pronto_para_iniciar())
	btn_iniciar_rede.visible = Rede.meu_lugar != 1
