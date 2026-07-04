extends Node
## Teste de fumaça da UI: instancia o menu e a partida (vs IA) na árvore por alguns
## segundos. Erros de script aparecem no log (user://logs/godot.log).

func _ready() -> void:
	_rodar()

func _rodar() -> void:
	print("[validacao] instanciando menu...")
	var menu: Node = load("res://scenes/menu_principal.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(0.5).timeout
	menu.queue_free()
	await get_tree().process_frame

	print("[validacao] instanciando partida (Ordwyn vs IA Korrath)...")
	BancoDados.config_partida = {"jogadores": [
		{"comandante": "ordwyn", "eh_ia": false},
		{"comandante": "korrath", "eh_ia": true}]}
	var partida: Node = load("res://scenes/partida.tscn").instantiate()
	add_child(partida)
	await get_tree().create_timer(1.0).timeout
	# Simula o humano encerrando alguns turnos para a IA jogar de verdade.
	for _i in 6:
		var motor: Motor = partida.motor
		if motor.fase == Motor.Fase.FIM:
			break
		if motor.em_fase_principal() and not motor.jogador_ativo().eh_ia:
			motor.encerrar_turno()
		elif motor.fase == Motor.Fase.BLOQUEIO and not motor.defensor().eh_ia:
			motor.declarar_bloqueios({})
		elif motor.fase == Motor.Fase.DESCARTE and not motor.jogador_ativo().eh_ia:
			motor.descartar(0)
		await get_tree().create_timer(2.0).timeout
	print("[validacao] concluído sem travar.")
	get_tree().quit(0)
