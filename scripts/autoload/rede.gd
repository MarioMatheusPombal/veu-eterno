extends Node
## Autoload: partida por IP com ENet (funciona em LAN e VPNs como Radmin/Hamachi).
## O host é sempre o Jogador 1 (lugar 0). Os dois lados rodam o mesmo Motor de forma
## determinística (mesma semente de embaralhamento) e trocam apenas as ações.

signal status_mudou(texto: String)
signal lobby_mudou
signal acao_recebida(pacote: Dictionary)
signal desconectado

const PORTA_PADRAO := 7777

var ativo := false        # true durante uma partida em rede
var conectado := false    # true quando os dois lados estão ligados
var meu_lugar := -1       # 0 = host, 1 = cliente
var comandantes := ["", ""]
var _sinais_ligados := false

func hospedar(porta: int) -> String:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(porta, 1) != OK:
		return "Não foi possível abrir a porta %d (já em uso?)." % porta
	multiplayer.multiplayer_peer = peer
	meu_lugar = 0
	_ligar_sinais()
	status_mudou.emit("Sala criada na porta %d. Aguardando oponente...\nPasse ao amigo o seu IP (da LAN ou do Radmin VPN)." % porta)
	return ""

func conectar(ip: String, porta: int) -> String:
	if ip.strip_edges() == "":
		return "Informe o IP do host."
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip.strip_edges(), porta) != OK:
		return "Endereço inválido."
	multiplayer.multiplayer_peer = peer
	meu_lugar = 1
	_ligar_sinais()
	status_mudou.emit("Conectando a %s:%d..." % [ip, porta])
	return ""

func _ligar_sinais() -> void:
	if _sinais_ligados:
		return
	_sinais_ligados = true
	multiplayer.peer_connected.connect(_ao_peer_conectado)
	multiplayer.peer_disconnected.connect(_ao_peer_desconectado)
	multiplayer.connected_to_server.connect(_ao_conectar_no_servidor)
	multiplayer.connection_failed.connect(_ao_falhar)

func _ao_peer_conectado(_id: int) -> void:
	conectado = true
	status_mudou.emit("Oponente conectado! Escolham os Comandantes.")
	# Reenvia a escolha local caso já tenha sido feita antes da conexão.
	if comandantes[meu_lugar] != "":
		_rpc_comandante.rpc(meu_lugar, comandantes[meu_lugar])
	lobby_mudou.emit()

func _ao_conectar_no_servidor() -> void:
	conectado = true
	status_mudou.emit("Conectado! Escolham os Comandantes.")
	lobby_mudou.emit()

func _ao_falhar() -> void:
	status_mudou.emit("Falha ao conectar. Verifique o IP/porta (e o firewall do host).")
	encerrar()

func _ao_peer_desconectado(_id: int) -> void:
	var estava_em_partida := ativo
	encerrar()
	if estava_em_partida:
		desconectado.emit()
	else:
		status_mudou.emit("O oponente desconectou.")
		lobby_mudou.emit()

func escolher_comandante(id_cmd: String) -> void:
	comandantes[meu_lugar] = id_cmd
	if conectado:
		_rpc_comandante.rpc(meu_lugar, id_cmd)
	lobby_mudou.emit()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_comandante(lugar: int, id_cmd: String) -> void:
	comandantes[lugar] = id_cmd
	lobby_mudou.emit()

func pronto_para_iniciar() -> bool:
	return conectado and comandantes[0] != "" and comandantes[1] != ""

func iniciar_partida() -> void:
	if meu_lugar != 0 or not pronto_para_iniciar():
		return
	var cfg := {
		"jogadores": [
			{"comandante": comandantes[0], "eh_ia": false},
			{"comandante": comandantes[1], "eh_ia": false},
		],
		"seed": randi(),
	}
	_rpc_iniciar.rpc(cfg)
	_comecar(cfg)

@rpc("authority", "call_remote", "reliable")
func _rpc_iniciar(cfg: Dictionary) -> void:
	_comecar(cfg)

func _comecar(cfg: Dictionary) -> void:
	ativo = true
	BancoDados.config_partida = cfg
	get_tree().change_scene_to_file("res://scenes/partida.tscn")

func enviar_acao(pacote: Dictionary) -> void:
	if ativo and conectado:
		_rpc_acao.rpc(pacote)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_acao(pacote: Dictionary) -> void:
	acao_recebida.emit(pacote)

func encerrar() -> void:
	ativo = false
	conectado = false
	meu_lugar = -1
	comandantes = ["", ""]
	multiplayer.multiplayer_peer = null
