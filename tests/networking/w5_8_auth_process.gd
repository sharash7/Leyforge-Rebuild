extends SceneTree
var session: LfeNetworkSession
var directory: String
var label: String
var mode: String
var fault: String = ""
var secret: PackedByteArray
var captured: Dictionary = {}
var events: Array = []
var admitted: Array = []
var world_seen: bool = false
var world_before_proof: bool = false
var challenged: bool = false
var first: bool = true
var seen_nonce: String = ""
var challenged_session: String = ""
var started: int
var hold: float = 0.5
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var port: int = 25659; var address: String = "127.0.0.1"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--proof-dir="): directory = arg.trim_prefix("--proof-dir=")
		if arg.begins_with("--proof-name="): label = arg.trim_prefix("--proof-name=")
		if arg.begins_with("--fault="): fault = arg.trim_prefix("--fault=")
		if arg.begins_with("--session="): mode = arg.trim_prefix("--session=")
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		if arg.begins_with("--address="): address = arg.trim_prefix("--address=")
		if arg.begins_with("--hold="): hold = float(arg.trim_prefix("--hold="))
	secret = LfePrivateSessionAuth.parse_invite(OS.get_environment("LEYFORGE_INVITE")); OS.unset_environment("LEYFORGE_INVITE")
	started = Time.get_ticks_msec()
	session = LfeNetworkSession.new(); root.add_child(session)
	session.state_changed.connect(func(state: String, reason: String): events.append({"state":state,"reason":reason}))
	var manifest: Dictionary = LfeCompatibilityManifest.hello(("a" if mode == "HOST" else "b").repeat(32),LfeCompatibilityManifest.fingerprint())
	if mode == "HOST":
		var world: Dictionary = {"world_id":"private-fixture","seed":184552221,"worldgen_version":2,"save_version":4,"content_version":1,"content_hash":manifest["content_hash"],"network_protocol_version":7}
		if not session.start_host(port,manifest,world,func(id: String): admitted.append(id); return true): quit(1); return
		# Fixture-only injected key; production HOST always securely generates its own.
		session.private_auth._secret = secret.duplicate()
		session.peer_rejected.connect(func(_id: int, reason: String): events.append({"rejected":reason}))
	else:
		if fault == "wrong": secret[0] ^= 1
		if fault in ["missing","malformed_invite"]: secret.clear()
		if not session.start_join(address,port,manifest,secret): quit(1); return
		if fault == "nonce": session._client_nonce = "bad"
		if fault == "auth_type":
			session._api.peer_authenticating.disconnect(session._authenticating_callback)
			session._api.peer_authenticating.connect(func(id: int):
				session.transition("AUTHENTICATING")
				var hello: Dictionary = LfePrivateSessionAuth.hello(manifest,session._client_nonce)
				hello["auth_version"] = true
				session._api.send_auth(id,JSON.stringify(hello).to_utf8_buffer()))
		if fault == "timeout":
			session._api.peer_authenticating.disconnect(session._authenticating_callback)
			session._api.peer_authenticating.connect(func(_id: int): session.transition("AUTHENTICATING"))
		session._api.auth_callback = _auth_probe
	var connected_at: int = 0
	while Time.get_ticks_msec()-started < 90000:
		await process_frame
		_write()
		if mode == "HOST":
			if FileAccess.file_exists(directory.path_join(label+".stop")): break
		else:
			if session.state == "CONNECTED":
				if connected_at == 0: connected_at = Time.get_ticks_msec()
				if fault == "replay" and first and Time.get_ticks_msec()-connected_at >= 250:
					first = false; session.disconnect_session(); await create_timer(0.3).timeout
					world_seen = false; challenged = false; connected_at = 0
					session.start_join(address,port,manifest,secret); session._api.auth_callback = _auth_probe
				elif Time.get_ticks_msec()-connected_at >= int(hold*1000): break
			elif session.state in ["REJECTED","CONNECTION_FAILED","DISCONNECTED"]: break
	_write(); session.disconnect_session(); await create_timer(0.1).timeout; quit(0)
func _auth_probe(id: int, bytes: PackedByteArray) -> void:
	var value: Variant = LfeCompatibilityManifest.decode(bytes)
	if value is Dictionary and value.has("world") and not value["world"].is_empty():
		world_seen = true
		if not session._proof_sent: world_before_proof = true
	if LfePrivateSessionAuth.valid_challenge(value):
		challenged = true
		if not seen_nonce.is_empty() and seen_nonce == value["server_nonce"]: quit(1); return
		seen_nonce = value["server_nonce"]; challenged_session = value["session_instance"]
		if fault in ["byte","session","shape","proof_type","replay","stale"]:
			session._proof_sent = true
			var packet: Dictionary = LfePrivateSessionAuth.proof(secret,session._hello,session._client_nonce,value)
			if fault == "replay" and not first: packet = captured
			else: captured = packet.duplicate(true)
			if fault == "byte": packet["proof"] = ("0" if packet["proof"][0] != "0" else "1")+packet["proof"].substr(1)
			if fault == "session": packet["session_instance"] = "0".repeat(32)
			if fault == "shape": packet["proof"] = "malformed"
			if fault == "proof_type": packet["session_instance"] = true
			if fault == "stale": await create_timer(6.2).timeout
			if session._api != null: session._api.send_auth(id,JSON.stringify(packet).to_utf8_buffer())
			return
	session._auth(id,bytes)
func _write() -> void:
	var report: Dictionary = {"state":session.state,"reason":session.reason_code,"world_seen":world_seen,"world_before_proof":world_before_proof,"challenged":challenged,"admitted":admitted,"pending":session.private_auth.pending.size() if session.private_auth != null else 0,"bindings":session.peer_to_player.size(),"events":events,"metrics":session.lifecycle_metrics,"first":first,"session_instance":challenged_session,"passed":true}
	var file: FileAccess = FileAccess.open(directory.path_join(label+".json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report)); file=null
