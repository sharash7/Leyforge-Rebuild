extends SceneTree

var game: LeyforgeWave1Playground
var session: LfeNetworkSession
var directory: String
var label: String
var fault: String = ""
var hold: float = 0.5
var events: Array = []
var states: Array = []
var failures: Array = []
var baseline_shared: Dictionary = {}
var baseline_host: Dictionary = {}
var records: Dictionary = {}
var connected_at: int = 0
var started: int
var save_hash: String = ""
var report: Dictionary = {}

func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--proof-dir="): directory = arg.trim_prefix("--proof-dir=")
		if arg.begins_with("--proof-name="): label = arg.trim_prefix("--proof-name=")
		if arg.begins_with("--proof-fault="): fault = arg.trim_prefix("--proof-fault=")
		if arg.begins_with("--proof-hold="): hold = float(arg.trim_prefix("--proof-hold="))
	if not directory.is_absolute_path() or label.is_empty(): quit(1); return
	started = Time.get_ticks_msec()
	game = load("res://scenes/main/wave_1_playground.tscn").instantiate()
	root.add_child(game)
	if game.session_options.mode == "HOST":
		while game.network_session == null and Time.get_ticks_msec() - started < 20000:
			await process_frame
		session = game.network_session
		if session == null: quit(1); return
		game.set_physics_process(false)
		game.player.set_physics_process(false)
		game._sync_active_transform()
		game.set_process(false)
		baseline_shared = shared()
		baseline_host = game.active_character.snapshot()
		if FileAccess.file_exists(game.world_save.get_primary_path()): save_hash = FileAccess.get_sha256(game.world_save.get_primary_path())
		session.peer_admitted.connect(_admitted)
		session.peer_left.connect(_left)
		session.peer_rejected.connect(_rejected)
	else:
		for child: Node in game.get_children():
			if child is LeyforgeSessionView: session = child.session
		if session == null: quit(1); return
		# Test-only wire faults use the real session/auth transport, never a fake peer.
		match fault:
			"protocol_mismatch": session._hello["network_protocol_version"] = 2
			"build_mismatch": session._hello["build_version"] = "incompatible"
			"save_schema_mismatch": session._hello["save_version"] = 3
			"content_version_mismatch": session._hello["content_version"] = 2
			"content_hash_mismatch": session._hello["content_hash"] = "a".repeat(64)
			"worldgen_unsupported": session._hello["worldgen_versions"] = [99]
			"invalid_identity": session._hello["player_id"] = "bad"
			"malformed_handshake": session._hello["extra"] = true
			"oversized_handshake": session._hello["extra"] = "x".repeat(4096)
			"auth_timeout":
				session._api.peer_authenticating.disconnect(session._authenticating)
				session._api.peer_authenticating.connect(_silent_auth)
	states.append(session.state)
	session.state_changed.connect(func(state: String, reason: String): states.append(state); events.append({"kind":"state","state":state,"reason":reason}))
	while Time.get_ticks_msec() - started < 120000:
		await process_frame
		if session.mode == "HOST":
			# Avoid ticking gameplay while checking admission conservation.
			game.set_physics_process(false)
			game.player.set_physics_process(false)
			if FileAccess.file_exists(directory.path_join(label + ".save")):
				if not game.request_save(): failures.append("normal host save failed")
				DirAccess.remove_absolute(directory.path_join(label + ".save"))
				report["saved"] = true
			_write_report()
			if FileAccess.file_exists(directory.path_join(label + ".stop")): break
		else:
			if session.state == "CONNECTED":
				if connected_at == 0: connected_at = Time.get_ticks_msec()
				if hold >= 0 and Time.get_ticks_msec() - connected_at >= int(hold * 1000): break
			elif session.state in ["REJECTED","CONNECTION_FAILED","DISCONNECTED"]: break
			if FileAccess.file_exists(directory.path_join(label + ".stop")): break
			if Time.get_ticks_msec() - started > 12000 and connected_at == 0: failures.append("client state timeout"); break
			_write_report()
	_write_report()
	session.disconnect_session()
	await create_timer(0.2).timeout
	print("W5_2_PROCESS_END name=%s state=%s" % [label,report.get("state","")])
	quit(0 if failures.is_empty() else 1)

func _silent_auth(_id: int) -> void:
	session.transition("AUTHENTICATING")

func shared() -> Dictionary:
	return {"resources":game.world_resources.snapshot(),"creation":game.creation.snapshot(),"overrides":game.world_save.overrides.count(),"owner":game.authority.owner_player_id}

func _admitted(peer: int, player_id: String) -> void:
	var record: LfePlayerCharacter = game.authority.character(player_id)
	var existing: bool = records.has(player_id)
	if existing and records[player_id] != record: failures.append("reconnect changed record object")
	records[player_id] = record
	var expected: LfePlayerCharacter = LfePlayerCharacter.new(player_id,game.block_catalog)
	if not existing and (record.resources.snapshot() != expected.resources.snapshot() or record.survival.snapshot() != expected.survival.snapshot()): failures.append("new record defaults differ")
	if not game._position_is_safe(Vector3(record.transform["position"][0],record.transform["position"][1],record.transform["position"][2])): failures.append("unsafe admitted spawn")
	if shared() != baseline_shared: failures.append("admission changed shared world")
	if game.active_character.snapshot() != baseline_host: failures.append("admission changed host character")
	events.append({"kind":"admitted","peer":peer,"player_id":player_id,"existing":existing,"roster":game.authority.characters.size()})

func _left(peer: int, player_id: String) -> void:
	if game.authority.character(player_id) != records.get(player_id): failures.append("leave deleted durable record")
	events.append({"kind":"left","peer":peer,"player_id":player_id,"roster":game.authority.characters.size()})

func _rejected(peer: int, reason: String) -> void:
	if shared() != baseline_shared: failures.append("rejection changed shared world")
	if FileAccess.file_exists(game.world_save.get_primary_path()) and FileAccess.get_sha256(game.world_save.get_primary_path()) != save_hash: failures.append("rejection wrote save")
	events.append({"kind":"rejected","peer":peer,"reason":reason,"roster":game.authority.characters.size()})

func _write_report() -> void:
	report.merge({"pid":OS.get_process_id(),"name":label,"state":session.state,"reason":session.reason_code,"states":states,"peer_id":session.local_peer_id,"bindings":session.peer_to_player.duplicate(),"events":events,"world":session.world_manifest.duplicate(true),"failures":failures,"passed":failures.is_empty()},true)
	if session.mode == "HOST":
		report["owner"] = game.authority.owner_player_id
		report["roster"] = game.authority.players_snapshot()
	else:
		report["player_id"] = session._hello.get("player_id","")
		report["client_has_no_authority"] = game.authority == null and game.world_save == null and game.player == null
		report["client_world_save_absent"] = not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://worlds"))
	var target: String = directory.path_join(label + ".json")
	var file: FileAccess = FileAccess.open(target + ".pending",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.flush()
	file = null
	if DirAccess.rename_absolute(target + ".pending",target) != OK: failures.append("report atomic promotion failed")