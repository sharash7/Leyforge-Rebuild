class_name LfeNetworkSession
extends Node

signal state_changed(state: String, reason: String)
signal peer_admitted(peer_id: int, player_id: String)
signal peer_left(peer_id: int, player_id: String)
signal peer_rejected(peer_id: int, reason: String)
signal packet_received(peer_id: int, bytes: PackedByteArray)
signal shutdown_complete

const MAX_PLAYERS: int = 8
const AUTH_SECONDS: float = 3.0
const CONNECT_SECONDS: float = 6.0
const TRANSITIONS: Dictionary = {
	"OFFLINE":["STARTING_HOST","CONNECTING","DISCONNECTED"],
	"STARTING_HOST":["HOSTING","CONNECTION_FAILED","DISCONNECTED"],
	"HOSTING":["CLOSING","DISCONNECTED"],
	"CLOSING":["HOSTING","DISCONNECTED"],
	"CONNECTING":["AUTHENTICATING","CONNECTION_FAILED","DISCONNECTED"],
	"AUTHENTICATING":["CONNECTED","REJECTED","CONNECTION_FAILED","DISCONNECTED"],
	"CONNECTED":["ENDING","DISCONNECTED"],
	"ENDING":["DISCONNECTED"],
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
var _authenticating_callback: Callable
var _admit: Callable
var _can_admit: Callable
var _pending: Dictionary = {}
var _rejections: Dictionary = {}
var _deadline: int = 0
var _polling: bool = false
var _close_requested: bool = false
var generation: int = 0
var expected_world_id: String = ""
var last_host_traffic: int = 0
var lifecycle_metrics: Dictionary = {"sent_bytes":0,"received_bytes":0,"sent_packets":0,"received_packets":0}
var _attempt_started: int = 0
var _heartbeat_at: int = 0
var _closing_deadline: int = 0
var _closing_acks: Dictionary = {}
var _leave_requests: Array[int] = []
const LIVENESS_MSEC: int = 5000
const CLOSING_ACK_MSEC: int = 350

func transition(next: String, reason: String = "ok") -> bool:
	if next not in TRANSITIONS.get(state, []) or reason not in LfeCompatibilityManifest.REASONS: return false
	state = next
	reason_code = reason
	print("LFE_SESSION mode=%s state=%s reason=%s peer=%d" % [mode,state,reason,local_peer_id])
	state_changed.emit(state,reason)
	return true

func _setup() -> void:
	generation += 1
	var owned_generation: int = generation
	_api = SceneMultiplayer.new()
	# Raw application packets still require a valid custom API root.
	_api.root_path = get_path()
	_api.allow_object_decoding = false
	_api.server_relay = false
	_api.auth_timeout = AUTH_SECONDS
	_api.auth_callback = func(id: int, bytes: PackedByteArray):
		if owned_generation == generation: _auth(id,bytes)
	_authenticating_callback = func(id: int):
		if owned_generation == generation: _authenticating(id)
	_api.peer_authenticating.connect(_authenticating_callback)
	_api.peer_authentication_failed.connect(func(id: int):
		if owned_generation == generation: _auth_failed(id))
	_api.peer_connected.connect(func(id: int):
		if owned_generation == generation: _connected_peer(id))
	_api.peer_disconnected.connect(func(id: int):
		if owned_generation == generation: _left_peer(id))
	_api.connection_failed.connect(func():
		if owned_generation == generation: _connection_failed())
	_api.server_disconnected.connect(func():
		if owned_generation == generation: _server_disconnected())
	_api.peer_packet.connect(func(id: int, bytes: PackedByteArray):
		if owned_generation == generation: _receive_packet(id,bytes))
	_transport = ENetMultiplayerPeer.new()

func start_host(port: int, local: Dictionary, hosted: Dictionary, admission: Callable, admission_check: Callable = Callable()) -> bool:
	if port < 1 or port > 65535 or not admission.is_valid() or LfeCompatibilityManifest.validate_hello(local,local,hosted) != "ok": return false
	if state not in ["OFFLINE","DISCONNECTED"] or generation >= 2147483645: return false
	mode = "HOST"
	if not transition("STARTING_HOST"): return false
	_setup()
	_hello = local.duplicate(true)
	world_manifest = hosted.duplicate(true)
	_admit = admission
	_can_admit = admission_check
	# Seven admitted remotes + one bounded pre-admission slot, allowing a useful
	# server_full response at capacity rather than an opaque socket timeout.
	if _transport.create_server(port, MAX_PLAYERS, 12) != OK:
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
	if state not in ["OFFLINE","DISCONNECTED"] or generation >= 2147483645: return false
	mode = "JOIN"
	_attempt_started = Time.get_ticks_msec()
	if not transition("CONNECTING"): return false
	_setup()
	_hello = local.duplicate(true)
	if _transport.create_client(address, port, 12) != OK:
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
	for id: int in _leave_requests: _api.disconnect_peer(id)
	_leave_requests.clear()
	for id: int in _rejections.keys():
		if now >= _rejections[id]:
			_api.disconnect_peer(id)
			_rejections.erase(id)
	if mode == "JOIN" and state in ["CONNECTING","AUTHENTICATING"] and now >= _deadline:
		transition("CONNECTION_FAILED","auth_timeout" if state == "AUTHENTICATING" else "connection_failed")
		_close_transport()
		return
	if mode == "HOST" and state == "HOSTING" and now >= _heartbeat_at:
		_heartbeat_at = now + 1000
		for id: int in peer_to_player:
			if id != local_peer_id: _send_control(id,{"kind":"session_heartbeat"})
	if mode == "JOIN" and state == "CONNECTED" and now-last_host_traffic >= LIVENESS_MSEC:
		end_session("server_timeout")
	if state == "CLOSING" and _closing_deadline > 0 and (now >= _closing_deadline or _closing_acks.is_empty()):
		disconnect_session()
		shutdown_complete.emit()
	elif state == "ENDING" and now >= _closing_deadline:
		disconnect_session()


func _authenticating(id: int) -> void:
	if mode == "JOIN":
		if id != 1 or not transition("AUTHENTICATING"): return
		_deadline = Time.get_ticks_msec() + int(AUTH_SECONDS * 1000)
		_api.send_auth(id, JSON.stringify(_hello).to_utf8_buffer())

func _auth(id: int, bytes: PackedByteArray) -> void:
	var value: Variant = LfeCompatibilityManifest.decode(bytes)
	if mode == "HOST":
		if _pending.has(id) or _rejections.has(id): return
		if state != "HOSTING": _reject(id,"server_closing"); return
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
			if not expected_world_id.is_empty() and value["world"]["world_id"] != expected_world_id:
				transition("REJECTED","world_mismatch")
				_close_transport()
				return
			world_manifest = value["world"].duplicate(true)
			_api.complete_auth(id)

func _reject(id: int, reason: String) -> void:
	print("LFE_SESSION rejected peer=%d reason=%s" % [id,reason])
	_api.send_auth(id,JSON.stringify({"reason":reason,"world":{}}).to_utf8_buffer())
	_rejections[id] = Time.get_ticks_msec() + 250
	peer_rejected.emit(id,reason)

func _connected_peer(id: int) -> void:
	if mode == "HOST":
		if state != "HOSTING": _leave_requests.append(id); return
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
		last_host_traffic = Time.get_ticks_msec()
		lifecycle_metrics["handshake_msec"] = last_host_traffic-_attempt_started
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
		_close_transport()

func _connection_failed() -> void:
	if state in ["CONNECTING","AUTHENTICATING"]:
		transition("CONNECTION_FAILED","connection_failed")
		_close_transport()

func _server_disconnected() -> void:
	if state in ["CONNECTED","AUTHENTICATING","CONNECTING"]: end_session("server_disconnected")

func disconnect_session() -> void:
	if state != "DISCONNECTED": transition("DISCONNECTED",reason_code)
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
	generation += 1
	_closing_deadline = 0
	_closing_acks.clear()
	_leave_requests.clear()
	_pending.clear()
	_rejections.clear()
	peer_to_player.clear()
	player_to_peer.clear()
	world_manifest.clear()

func _exit_tree() -> void:
	_close_transport()

# Generic authenticated application seam; transport objects stay in this class.
func send_packet(peer_id: int, bytes: PackedByteArray, transfer_mode: int, channel: int) -> Error:
	if _api == null or bytes.is_empty() or bytes.size() > 8192 or channel < 1 or channel > 11 or transfer_mode not in [MultiplayerPeer.TRANSFER_MODE_RELIABLE,MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED]: return ERR_INVALID_PARAMETER
	if mode == "HOST":
		if state != "HOSTING" or peer_id == local_peer_id or not peer_to_player.has(peer_id): return ERR_UNAUTHORIZED
	elif mode == "JOIN":
		if state != "CONNECTED" or peer_id != 1: return ERR_UNAUTHORIZED
	else: return ERR_UNAUTHORIZED
	return _api.send_bytes(bytes,peer_id,transfer_mode,channel)

func _receive_packet(peer_id: int, bytes: PackedByteArray) -> void:
	if bytes.is_empty() or bytes.size() > 8192: return
	var control: Dictionary = LfeSessionLifecycleProtocol.decode(bytes)
	if not control.is_empty():
		lifecycle_metrics["received_bytes"] += bytes.size()
		lifecycle_metrics["received_packets"] += 1
		_control(peer_id,control)
		return
	if mode == "HOST" and state == "HOSTING" and peer_id != local_peer_id and peer_to_player.has(peer_id):
		packet_received.emit(peer_id,bytes)
	elif mode == "JOIN" and state == "CONNECTED" and peer_id == 1:
		packet_received.emit(peer_id,bytes)

func disconnect_player(player_id: String) -> void:
	if mode == "HOST" and _api != null and player_to_peer.has(player_id):
		var peer: int = player_to_peer[player_id]
		if peer != local_peer_id: _api.disconnect_peer(peer)
func begin_host_closing() -> bool:
	return mode == "HOST" and transition("CLOSING","server_closing")

func cancel_host_closing() -> void:
	if state == "CLOSING" and _closing_deadline == 0: transition("HOSTING")

# The application calls this only after its authoritative save succeeded.
func finish_host_closing() -> void:
	if state != "CLOSING" or _closing_deadline != 0: return
	_closing_acks.clear()
	for id: int in peer_to_player:
		if id == local_peer_id: continue
		_closing_acks[id] = true
		_send_control(id,{"kind":"session_closing","reason":"host_shutdown"})
	_closing_deadline = Time.get_ticks_msec() + CLOSING_ACK_MSEC

func leave_session() -> void:
	if mode != "JOIN" or state != "CONNECTED": end_session("client_left"); return
	_send_control(1,{"kind":"client_leaving"})
	_closing_deadline = Time.get_ticks_msec() + 100
	transition("ENDING","client_left")

func end_session(reason: String) -> void:
	if state == "CONNECTED": transition("ENDING",reason)
	if state != "DISCONNECTED": transition("DISCONNECTED",reason)
	_close_transport()

func _send_control(peer: int, packet: Dictionary) -> void:
	var bytes: PackedByteArray = LfeSessionLifecycleProtocol.encode(packet)
	if _api != null and not bytes.is_empty():
		if _api.send_bytes(bytes,peer,MultiplayerPeer.TRANSFER_MODE_RELIABLE,LfeSessionLifecycleProtocol.CHANNEL) == OK:
			lifecycle_metrics["sent_bytes"] += bytes.size()
			lifecycle_metrics["sent_packets"] += 1

func _control(peer: int, packet: Dictionary) -> void:
	if mode == "HOST" and peer != local_peer_id and peer_to_player.has(peer):
		if packet["kind"] == "session_closing_ack" and state == "CLOSING": _closing_acks.erase(peer)
		elif packet["kind"] == "client_leaving":
			_left_peer(peer)
			_leave_requests.append(peer)
	elif mode == "JOIN" and peer == 1 and state == "CONNECTED":
		if packet["kind"] not in ["session_heartbeat","session_closing"]: return
		last_host_traffic = Time.get_ticks_msec()
		if packet["kind"] == "session_closing":
			transition("ENDING","host_shutdown")
			_send_control(1,{"kind":"session_closing_ack"})
			_closing_deadline = Time.get_ticks_msec() + 100

func note_host_traffic() -> void:
	if mode == "JOIN" and state == "CONNECTED": last_host_traffic = Time.get_ticks_msec()
