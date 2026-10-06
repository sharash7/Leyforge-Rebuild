class_name LfeNetworkSession
extends Node

signal state_changed(state: String, reason: String)
signal peer_admitted(peer_id: int, player_id: String)
signal peer_left(peer_id: int, player_id: String)
signal peer_rejected(peer_id: int, reason: String)
signal packet_received(peer_id: int, bytes: PackedByteArray)

const MAX_PLAYERS: int = 8
const AUTH_SECONDS: float = 3.0
const CONNECT_SECONDS: float = 6.0
const TRANSITIONS: Dictionary = {
	"OFFLINE":["STARTING_HOST","CONNECTING","DISCONNECTED"],
	"STARTING_HOST":["HOSTING","CONNECTION_FAILED","DISCONNECTED"],
	"HOSTING":["DISCONNECTED"],
	"CONNECTING":["AUTHENTICATING","CONNECTION_FAILED","DISCONNECTED"],
	"AUTHENTICATING":["CONNECTED","REJECTED","CONNECTION_FAILED","DISCONNECTED"],
	"CONNECTED":["DISCONNECTED"],
	"REJECTED":["DISCONNECTED"],
	"CONNECTION_FAILED":["DISCONNECTED"],
	"DISCONNECTED":["STARTING_HOST","CONNECTING"]
}
var mode: String = "OFFLINE"
var state: String = "OFFLINE"
var reason_code: String = "ok"
var peer_to_player: Dictionary = {}
var player_to_peer: Dictionary = {}
var world_manifest: Dictionary = {}
var local_peer_id: int = 0
var listen_port: int = 0
var _api: SceneMultiplayer
var _transport: ENetMultiplayerPeer
var _hello: Dictionary = {}
var _admit: Callable
var _can_admit: Callable
var _pending: Dictionary = {}
var _rejections: Dictionary = {}
var _deadline: int = 0
var _polling: bool = false
var _close_requested: bool = false

func transition(next: String, reason: String = "ok") -> bool:
	if next not in TRANSITIONS.get(state, []) or reason not in LfeCompatibilityManifest.REASONS: return false
	state = next
	reason_code = reason
	print("LFE_SESSION mode=%s state=%s reason=%s peer=%d" % [mode,state,reason,local_peer_id])
	state_changed.emit(state,reason)
	return true

func _setup() -> void:
	_api = SceneMultiplayer.new()
	# Raw application packets still require a valid custom API root.
	_api.root_path = get_path()
	_api.allow_object_decoding = false
	_api.server_relay = false
	_api.auth_timeout = AUTH_SECONDS
	_api.auth_callback = _auth
	_api.peer_authenticating.connect(_authenticating)
	_api.peer_authentication_failed.connect(_auth_failed)
	_api.peer_connected.connect(_connected_peer)
	_api.peer_disconnected.connect(_left_peer)
	_api.connection_failed.connect(_connection_failed)
	_api.server_disconnected.connect(_server_disconnected)
	_api.peer_packet.connect(_receive_packet)
	_transport = ENetMultiplayerPeer.new()

func start_host(port: int, local: Dictionary, hosted: Dictionary, admission: Callable, admission_check: Callable = Callable()) -> bool:
	if port < 1 or port > 65535 or not admission.is_valid() or LfeCompatibilityManifest.validate_hello(local,local,hosted) != "ok": return false
	if state not in ["OFFLINE","DISCONNECTED"]: return false
	mode = "HOST"
	if not transition("STARTING_HOST"): return false
	_setup()
	_hello = local.duplicate(true)
	world_manifest = hosted.duplicate(true)
	_admit = admission
	_can_admit = admission_check
	# Seven admitted remotes + one bounded pre-admission slot, allowing a useful
	# server_full response at capacity rather than an opaque socket timeout.
	if _transport.create_server(port, MAX_PLAYERS, 11) != OK:
		transition("CONNECTION_FAILED","connection_failed")
		_close_transport()
		return false
	_api.multiplayer_peer = _transport
	local_peer_id = _api.get_unique_id()
	listen_port = port
	peer_to_player[local_peer_id] = local["player_id"]
	player_to_peer[local["player_id"]] = local_peer_id
	print("LFE_SESSION listening port=%d host_player=%s" % [port,local["player_id"].left(8)])
	return transition("HOSTING")

func start_join(address: String, port: int, local: Dictionary) -> bool:
	if not LfeSessionOptions.valid_address(address) or port < 1 or port > 65535: return false
	if state not in ["OFFLINE","DISCONNECTED"]: return false
	mode = "JOIN"
	if not transition("CONNECTING"): return false
	_setup()
	_hello = local.duplicate(true)
	if _transport.create_client(address, port, 11) != OK:
		transition("CONNECTION_FAILED","connection_failed")
		_close_transport()
		return false
	_api.multiplayer_peer = _transport
	local_peer_id = _api.get_unique_id()
	_deadline = Time.get_ticks_msec() + int(CONNECT_SECONDS * 1000)
	print("LFE_SESSION joining address=%s port=%d player=%s" % [address,port,String(local.get("player_id","")).left(8)])
	return true

func _process(_delta: float) -> void:
	if _api == null: return
	_polling = true
	_api.poll()
	_polling = false
	if _close_requested:
		_close_transport()
		return
	var now: int = Time.get_ticks_msec()
	for id: int in _rejections.keys():
		if now >= _rejections[id]:
			_api.disconnect_peer(id)
			_rejections.erase(id)
	if mode == "JOIN" and state in ["CONNECTING","AUTHENTICATING"] and now >= _deadline:
		transition("CONNECTION_FAILED","auth_timeout" if state == "AUTHENTICATING" else "connection_failed")
		_close_transport()

func _authenticating(id: int) -> void:
	if mode == "JOIN":
		if id != 1 or not transition("AUTHENTICATING"): return
		_deadline = Time.get_ticks_msec() + int(AUTH_SECONDS * 1000)
		_api.send_auth(id, JSON.stringify(_hello).to_utf8_buffer())

func _auth(id: int, bytes: PackedByteArray) -> void:
	var value: Variant = LfeCompatibilityManifest.decode(bytes)
	if mode == "HOST":
		if _pending.has(id) or _rejections.has(id): return
		var reason: String = LfeCompatibilityManifest.validate_hello(value,_hello,world_manifest)
		if reason == "ok":
			var player_id: String = value["player_id"]
			if player_to_peer.has(player_id) or player_id in _pending.values(): reason = "duplicate_identity"
			elif peer_to_player.size() + _pending.size() >= MAX_PLAYERS: reason = "server_full"
			elif _can_admit.is_valid() and not _can_admit.call(player_id): reason = "server_full"
		if reason != "ok":
			_reject(id,reason)
			return
		_pending[id] = value["player_id"]
		_api.send_auth(id, JSON.stringify({"reason":"ok","world":world_manifest}).to_utf8_buffer())
		_api.complete_auth(id)
	else:
		if state != "AUTHENTICATING" or id != 1: return
		if not LfeCompatibilityManifest.exact_keys(value,["reason","world"]) or not value["reason"] is String or value["reason"] not in LfeCompatibilityManifest.REASONS:
			transition("REJECTED","malformed_handshake")
			_close_transport()
			return
		if value["reason"] != "ok":
			transition("REJECTED",value["reason"])
			_close_transport()
		elif not LfeCompatibilityManifest.valid_world(value["world"],_hello):
			transition("REJECTED","malformed_handshake")
			_close_transport()
		else:
			world_manifest = value["world"].duplicate(true)
			_api.complete_auth(id)

func _reject(id: int, reason: String) -> void:
	print("LFE_SESSION rejected peer=%d reason=%s" % [id,reason])
	_api.send_auth(id,JSON.stringify({"reason":reason,"world":{}}).to_utf8_buffer())
	_rejections[id] = Time.get_ticks_msec() + 250
	peer_rejected.emit(id,reason)

func _connected_peer(id: int) -> void:
	if mode == "HOST":
		if not _pending.has(id): _api.disconnect_peer(id); return
		var player_id: String = _pending[id]
		_pending.erase(id)
		if not _admit.call(player_id):
			_api.disconnect_peer(id)
			peer_rejected.emit(id,"server_full")
			return
		peer_to_player[id] = player_id
		player_to_peer[player_id] = id
		print("LFE_SESSION admitted peer=%d player=%s" % [id,player_id.left(8)])
		peer_admitted.emit(id,player_id)
	elif id == 1 and state == "AUTHENTICATING":
		peer_to_player[local_peer_id] = _hello["player_id"]
		player_to_peer[_hello["player_id"]] = local_peer_id
		transition("CONNECTED")

func _left_peer(id: int) -> void:
	_pending.erase(id)
	_rejections.erase(id)
	if peer_to_player.has(id):
		var player_id: String = peer_to_player[id]
		peer_to_player.erase(id)
		player_to_peer.erase(player_id)
		print("LFE_SESSION left peer=%d player=%s" % [id,player_id.left(8)])
		peer_left.emit(id,player_id)

func _auth_failed(id: int) -> void:
	var rejected: bool = _rejections.has(id)
	_pending.erase(id)
	_rejections.erase(id)
	if mode == "HOST":
		if not rejected: peer_rejected.emit(id,"auth_timeout")
	elif state == "AUTHENTICATING":
		transition("CONNECTION_FAILED","auth_timeout")

func _connection_failed() -> void:
	if state in ["CONNECTING","AUTHENTICATING"]:
		transition("CONNECTION_FAILED","connection_failed")
		_close_transport()

func _server_disconnected() -> void:
	if state in ["CONNECTED","AUTHENTICATING","CONNECTING"]: transition("DISCONNECTED","server_disconnected")
	peer_to_player.clear()
	player_to_peer.clear()

func disconnect_session() -> void:
	if state != "DISCONNECTED": transition("DISCONNECTED")
	_close_transport()

func _close_transport() -> void:
	# Never destroy or mutate a transport from inside its own poll callback.
	if _polling:
		_close_requested = true
		return
	_close_requested = false
	if _transport != null: _transport.close()
	if _api != null: _api.multiplayer_peer = null
	_api = null
	_transport = null
	_pending.clear()
	_rejections.clear()
	peer_to_player.clear()
	player_to_peer.clear()
	world_manifest.clear()

func _exit_tree() -> void:
	_close_transport()

# Generic authenticated application seam; transport objects stay in this class.
func send_packet(peer_id: int, bytes: PackedByteArray, transfer_mode: int, channel: int) -> Error:
	if _api == null or bytes.is_empty() or bytes.size() > 8192 or channel < 1 or channel > 10 or transfer_mode not in [MultiplayerPeer.TRANSFER_MODE_RELIABLE,MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED]: return ERR_INVALID_PARAMETER
	if mode == "HOST":
		if state != "HOSTING" or peer_id == local_peer_id or not peer_to_player.has(peer_id): return ERR_UNAUTHORIZED
	elif mode == "JOIN":
		if state != "CONNECTED" or peer_id != 1: return ERR_UNAUTHORIZED
	else: return ERR_UNAUTHORIZED
	return _api.send_bytes(bytes,peer_id,transfer_mode,channel)

func _receive_packet(peer_id: int, bytes: PackedByteArray) -> void:
	if bytes.is_empty() or bytes.size() > 8192: return
	if mode == "HOST" and state == "HOSTING" and peer_id != local_peer_id and peer_to_player.has(peer_id):
		packet_received.emit(peer_id,bytes)
	elif mode == "JOIN" and state == "CONNECTED" and peer_id == 1:
		packet_received.emit(peer_id,bytes)

func disconnect_player(player_id: String) -> void:
	if mode == "HOST" and _api != null and player_to_peer.has(player_id):
		var peer: int = player_to_peer[player_id]
		if peer != local_peer_id: _api.disconnect_peer(peer)