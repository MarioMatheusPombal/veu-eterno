extends Node
## Teste de fumaça headless: simula partidas IA vs IA direto no Motor (sem UI).
## Rodar com:
##   godot --headless res://scenes/teste_simulacao.tscn
## Falhas de regra aparecem como erro/push_error; ao final imprime o placar.

const MAX_PASSOS := 4000
const ARQUIVO_RESULTADO := "res://resultado_simulacao.txt"

var relatorio: Array = []

func _ready() -> void:
	var ids: Array = ["ordwyn", "sylvaine", "nyx", "korrath"]
	var total := 0
	var falhas := 0
	for a in ids:
		for b in ids:
			for _rep in 2:
				total += 1
				if not _simular(a, b):
					falhas += 1
	_reportar("Simulações: %d | Falhas: %d" % [total, falhas])
	var arq := FileAccess.open(ARQUIVO_RESULTADO, FileAccess.WRITE)
	if arq != null:
		arq.store_string("\n".join(relatorio))
	get_tree().quit(1 if falhas > 0 else 0)

func _reportar(texto: String) -> void:
	print(texto)
	relatorio.append(texto)

func _simular(cmd_a: String, cmd_b: String) -> bool:
	var motor := Motor.new()
	motor.iniciar([{"comandante": cmd_a, "eh_ia": true}, {"comandante": cmd_b, "eh_ia": true}])
	var passos := 0
	while motor.fase != Motor.Fase.FIM and passos < MAX_PASSOS:
		passos += 1
		if motor.em_fase_principal():
			var acao := IA.proxima_acao(motor)
			match str(acao["tipo"]):
				"carta":
					var erro: String = motor.jogar_carta(acao["idx"], acao["alvos"])
					if erro != "":
						_reportar("ERRO: " + "jogar_carta falhou (%s vs %s): %s" % [cmd_a, cmd_b, erro])
						return false
				"comando":
					var erro: String = motor.ativar_comando(acao["alvos"])
					if erro != "":
						_reportar("ERRO: " + "comando falhou: " + erro)
						return false
				"reliquia":
					var erro: String = motor.ativar_reliquia(acao["inst"])
					if erro != "":
						_reportar("ERRO: " + "reliquia falhou: " + erro)
						return false
				"passar":
					if motor.fase == Motor.Fase.PRINCIPAL_1 and not motor.combate_feito:
						var erro: String = motor.declarar_atacantes(IA.escolher_atacantes(motor))
						if erro != "":
							_reportar("ERRO: " + "atacantes falhou: " + erro)
							return false
					else:
						motor.encerrar_turno()
		elif motor.fase == Motor.Fase.BLOQUEIO:
			var erro: String = motor.declarar_bloqueios(IA.escolher_bloqueios(motor))
			if erro != "":
				_reportar("ERRO: " + "bloqueios falhou (%s vs %s): %s" % [cmd_a, cmd_b, erro])
				return false
		elif motor.fase == Motor.Fase.DESCARTE:
			motor.descartar(IA.escolher_descarte(motor))
	if motor.fase != Motor.Fase.FIM:
		_reportar("ERRO: " + "Partida %s vs %s não terminou em %d passos." % [cmd_a, cmd_b, MAX_PASSOS])
		return false
	_reportar("  %s vs %s -> venceu %s (turno %d)" % [
		cmd_a, cmd_b, motor.jogadores[0].nome() if motor.jogadores[0].vida > 0
		else motor.jogadores[1].nome(), motor.turno])
	return true
