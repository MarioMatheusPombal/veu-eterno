class_name Jogador
extends RefCounted
## Estado de um Duelista: Comandante no Trono, zonas e recursos do turno.

var indice := 0
var eh_ia := false
var comandante: Dictionary = {}
var vida := 20
var baralho: Array = []    # dados de carta (topo = último elemento)
var mao: Array = []        # dados de carta
var campo: Array = []      # InstanciaCarta (Fontes, Convocados e Relíquias)
var cemiterio: Array = []  # dados de carta
var vazio: Array = []      # zona de exílio (reservada; nenhum efeito do set usa ainda)

# Estado do turno
var fonte_jogada := false
var comando_usado := false
var bonus_neutra := 0      # Essência incolor temporária (efeitos); não acumula
var bonus_faccao := 0      # Essência de facção temporária (efeitos); não acumula

func nome() -> String:
	return str(comandante.get("nome", "Duelista %d" % (indice + 1)))

func faccao() -> String:
	var f: Array = comandante.get("faccao", [])
	return str(f[0]) if not f.is_empty() else ""

func convocados() -> Array:
	return campo.filter(func(inst: InstanciaCarta) -> bool: return inst.eh_convocado())
