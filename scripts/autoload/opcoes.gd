extends Node
## Autoload: opções do jogador, persistidas em user://opcoes.cfg.

const CAMINHO := "user://opcoes.cfg"

var tela_cheia := false
var animacoes := true
var tremor := true
var velocidade_ia := 0.6  # segundos entre ações da IA

func _ready() -> void:
	carregar()
	_aplicar_janela()

func carregar() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CAMINHO) != OK:
		return
	tela_cheia = bool(cfg.get_value("video", "tela_cheia", tela_cheia))
	animacoes = bool(cfg.get_value("jogo", "animacoes", animacoes))
	tremor = bool(cfg.get_value("jogo", "tremor", tremor))
	velocidade_ia = float(cfg.get_value("jogo", "velocidade_ia", velocidade_ia))

func salvar() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "tela_cheia", tela_cheia)
	cfg.set_value("jogo", "animacoes", animacoes)
	cfg.set_value("jogo", "tremor", tremor)
	cfg.set_value("jogo", "velocidade_ia", velocidade_ia)
	cfg.save(CAMINHO)

func definir_tela_cheia(valor: bool) -> void:
	tela_cheia = valor
	_aplicar_janela()
	salvar()

func _aplicar_janela() -> void:
	DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if tela_cheia
			else DisplayServer.WINDOW_MODE_WINDOWED)
