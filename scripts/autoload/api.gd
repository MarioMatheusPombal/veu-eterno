extends Node
## Autoload: toda a comunicação com o backend (meta-jogo) passa por aqui.
## O jogo local (IA/hotseat) funciona 100% offline — só Coleção, Loja e Ranking
## exigem servidor. A resposta do servidor é sempre a fonte da verdade
## (o cliente nunca calcula saldo, sorteio ou rating localmente).

signal sessao_mudou

const TIMEOUT_S := 8.0

var jwt := ""        # token de sessão, só em memória (nunca salvar em disco)
var jogador := {}    # perfil público retornado pelo servidor
var economia := {}   # preços e taxas de drop (GET /config/economia)

func logado() -> bool:
	return jwt != ""

func id_conta() -> String:
	return str(jogador.get("id", ""))

## Requisição genérica. Retorna {ok, codigo, dados}; em falha de rede, ok=false
## com uma mensagem legível em dados.erro.
func requisitar(metodo: int, rota: String, corpo: Dictionary = {}) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_S
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if jwt != "":
		headers.append("Authorization: Bearer " + jwt)
	var corpo_txt := "" if corpo.is_empty() and metodo == HTTPClient.METHOD_GET \
			else JSON.stringify(corpo)
	var erro := http.request(Opcoes.servidor_url + rota, headers, metodo, corpo_txt)
	if erro != OK:
		http.queue_free()
		return {"ok": false, "codigo": 0, "dados": {"erro": "Endereço do servidor inválido."}}
	var resposta: Array = await http.request_completed
	http.queue_free()
	var resultado: int = resposta[0]
	var codigo: int = resposta[1]
	if resultado != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "codigo": 0,
				"dados": {"erro": "Sem conexão com o servidor. Verifique a URL nas Opções."}}
	var dados: Variant = JSON.parse_string(resposta[3].get_string_from_utf8())
	if codigo == 401:
		jwt = ""  # sessão expirou; a próxima tela refaz o login
		sessao_mudou.emit()
	return {"ok": codigo >= 200 and codigo < 300, "codigo": codigo,
			"dados": dados if dados is Dictionary else {}}

## Login. Hoje usa a rota de desenvolvimento (/auth/dev, sem Steam); quando o jogo
## for exportado com GodotSteam, este é o único lugar a trocar pelo ticket Steam
## (POST /auth/steam) — o resto do jogo não muda.
func entrar() -> Dictionary:
	var r := await requisitar(HTTPClient.METHOD_POST, "/auth/dev",
			{"nome": Opcoes.nome_jogador})
	if r.ok:
		jwt = str(r.dados["token"])
		jogador = r.dados["jogador"]
		sessao_mudou.emit()
	return r

## Garante sessão ativa (e economia carregada). Retorna "" ou uma mensagem de erro.
func garantir_sessao() -> String:
	if not logado():
		var r := await entrar()
		if not r.ok:
			return str(r.dados.get("erro", "Não foi possível entrar no servidor."))
	if economia.is_empty():
		var e := await requisitar(HTTPClient.METHOD_GET, "/config/economia")
		if e.ok:
			economia = e.dados["economia"]
	return ""

func sair() -> void:
	jwt = ""
	jogador = {}
	sessao_mudou.emit()

# -------------------------------------------------------------- endpoints

func perfil() -> Dictionary:
	var r := await requisitar(HTTPClient.METHOD_GET, "/perfil")
	if r.ok:
		jogador = r.dados["jogador"]
		sessao_mudou.emit()
	return r

func colecao() -> Dictionary:
	return await requisitar(HTTPClient.METHOD_GET, "/colecao")

func comprar_booster(quantidade: int) -> Dictionary:
	return await requisitar(HTTPClient.METHOD_POST, "/boosters/comprar",
			{"quantidade": quantidade})

func abrir_booster() -> Dictionary:
	return await requisitar(HTTPClient.METHOD_POST, "/boosters/abrir", {})

func reciclar(carta_id: String, quantidade: int) -> Dictionary:
	return await requisitar(HTTPClient.METHOD_POST, "/crafting/reciclar",
			{"carta_id": carta_id, "quantidade": quantidade})

func criar(carta_id: String) -> Dictionary:
	return await requisitar(HTTPClient.METHOD_POST, "/crafting/criar",
			{"carta_id": carta_id, "quantidade": 1})

func pacotes_cristais() -> Dictionary:
	return await requisitar(HTTPClient.METHOD_GET, "/loja/pacotes")

func comprar_pacote(id_pacote: String) -> Dictionary:
	return await requisitar(HTTPClient.METHOD_POST, "/loja/comprar", {"pacote": id_pacote})

func rankings() -> Dictionary:
	return await requisitar(HTTPClient.METHOD_GET, "/rankings")

func reportar_resultado(modo: String, semente: int, meu_lugar: int, vencedor: int,
		oponente_id: String) -> Dictionary:
	return await requisitar(HTTPClient.METHOD_POST, "/partidas/resultado", {
		"oponente_id": oponente_id, "modo": modo, "seed": semente,
		"meu_lugar": meu_lugar, "vencedor": vencedor,
	})
