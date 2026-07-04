extends Node
## Autoload: carrega cartas, comandantes e baralhos de res://data/ na inicialização.

const ARQUIVOS_CARTAS := [
	"res://data/cartas/coroa_radiante.json",
	"res://data/cartas/vinculo_selvagem.json",
	"res://data/cartas/veu_das_sombras.json",
	"res://data/cartas/corrente_do_caos.json",
	"res://data/cartas/incolores.json",
]

var cartas: Dictionary = {}       # id -> dados da carta
var comandantes: Dictionary = {}  # id -> dados do comandante
var baralhos: Dictionary = {}     # id -> {nome, comandante, lista (ids expandidos)}
var config_partida: Dictionary = {}  # preenchido pelo menu antes de trocar de cena

func _ready() -> void:
	for caminho in ARQUIVOS_CARTAS:
		for carta in _ler_json(caminho):
			cartas[carta["id"]] = carta
	for cmd in _ler_json("res://data/comandantes.json"):
		comandantes[cmd["id"]] = cmd
	var dados: Dictionary = _ler_json("res://data/baralhos.json")
	for id_baralho in dados:
		var b: Dictionary = dados[id_baralho]
		var lista: Array = []
		for id_carta in b["cartas"]:
			assert(cartas.has(id_carta), "Carta desconhecida no baralho %s: %s" % [id_baralho, id_carta])
			for k in int(b["cartas"][id_carta]):
				# A primeira cópia de cartas listadas em "holo"/"foil" ganha o acabamento.
				var acabamento := "normal"
				if k == 0 and id_carta in b.get("holo", []):
					acabamento = "holo"
				elif k == 0 and id_carta in b.get("foil", []):
					acabamento = "foil"
				lista.append({"id": id_carta, "acabamento": acabamento})
		assert(lista.size() >= 40, "Baralho %s tem menos de 40 cartas." % id_baralho)
		baralhos[id_baralho] = {"nome": b["nome"], "comandante": b["comandante"], "lista": lista}

func _ler_json(caminho: String) -> Variant:
	var texto := FileAccess.get_file_as_string(caminho)
	var resultado: Variant = JSON.parse_string(texto)
	assert(resultado != null, "JSON inválido: " + caminho)
	return resultado

static func custo_total(custo: Dictionary) -> int:
	var total := 0
	for chave in custo:
		total += int(custo[chave])
	return total

static func custo_faccao(custo: Dictionary) -> int:
	var total := 0
	for chave in custo:
		if chave != "incolor":
			total += int(custo[chave])
	return total
