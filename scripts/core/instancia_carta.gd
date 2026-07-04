class_name InstanciaCarta
extends RefCounted
## Uma carta em jogo no Campo: estado de runtime por cima dos dados imutáveis do banco.

var dados: Dictionary
var dono: int                    # índice do jogador (0 ou 1)
var usada := false               # "tapped"
var entrou_neste_turno := true   # mal de invocação (Convocados sem Investida)
var dano_marcado := 0
var buff_poder_turno := 0
var buff_res_turno := 0
var buff_poder_perm := 0
var buff_res_perm := 0
var kw_temporarias: Array = []   # palavras-chave até o fim do turno
var eh_token := false

func _init(p_dados: Dictionary, p_dono: int, p_token := false) -> void:
	dados = p_dados
	dono = p_dono
	eh_token = p_token

func tipo() -> String:
	return str(dados.get("tipo", ""))

func eh_convocado() -> bool:
	return tipo() == "Convocado"

func nome() -> String:
	return str(dados.get("nome", "?"))

func limpar_buffs_de_turno() -> void:
	buff_poder_turno = 0
	buff_res_turno = 0
	kw_temporarias.clear()
