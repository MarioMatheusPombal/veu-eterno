extends Node
## Autoload: falas dos Comandantes e efeitos sonoros.
## Os arquivos são opcionais (placeholders): se não existirem, nada toca.
## Estrutura esperada (ver SONS.md na raiz do repositório):
##   res://assets/sons/comandantes/<id>/<evento>.ogg  (ou .wav/.mp3)
##   Variantes: <evento>_1.ogg, <evento>_2.ogg, <evento>_3.ogg (escolhidas ao acaso).

const COOLDOWN_FALA := 6.0  # segundos entre falas do mesmo comandante
const EXTENSOES := ["ogg", "wav", "mp3"]

var _players: Array = []
var _proximo_player := 0
var _cooldowns := {}  # id do comandante -> instante em que pode falar de novo

func _ready() -> void:
	for _i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

## Toca a primeira fala existente da lista de eventos (permite fallback,
## ex.: ["vs_korrath", "entrada"]). Respeita o cooldown por comandante.
func falar(id_cmd: String, eventos: Variant, ignorar_cooldown := false) -> void:
	var lista: Array = eventos if eventos is Array else [eventos]
	var agora := Time.get_ticks_msec() / 1000.0
	if not ignorar_cooldown and agora < float(_cooldowns.get(id_cmd, 0.0)):
		return
	for evento in lista:
		var stream := _achar_fala(id_cmd, str(evento))
		if stream != null:
			_tocar_stream(stream)
			_cooldowns[id_cmd] = agora + COOLDOWN_FALA
			return

## Efeito sonoro genérico (res://assets/sons/sfx/<nome>.<ext>).
func sfx(nome: String) -> void:
	for ext in EXTENSOES:
		var caminho := "res://assets/sons/sfx/%s.%s" % [nome, ext]
		if ResourceLoader.exists(caminho, "AudioStream"):
			_tocar_stream(load(caminho))
			return

func _achar_fala(id_cmd: String, evento: String) -> AudioStream:
	var base := "res://assets/sons/comandantes/%s/%s" % [id_cmd, evento]
	var candidatos: Array = []
	for ext in EXTENSOES:
		if ResourceLoader.exists("%s.%s" % [base, ext], "AudioStream"):
			candidatos.append("%s.%s" % [base, ext])
		for n in range(1, 4):
			if ResourceLoader.exists("%s_%d.%s" % [base, n, ext], "AudioStream"):
				candidatos.append("%s_%d.%s" % [base, n, ext])
	if candidatos.is_empty():
		return null
	return load(candidatos.pick_random())

func _tocar_stream(stream: AudioStream) -> void:
	var p: AudioStreamPlayer = _players[_proximo_player]
	_proximo_player = (_proximo_player + 1) % _players.size()
	p.stream = stream
	p.play()
