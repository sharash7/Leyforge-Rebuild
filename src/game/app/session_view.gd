class_name LeyforgeSessionView
extends CanvasLayer

var session: LfeNetworkSession
var local_player_id: String = ""
var _label: Label

func build(network: LfeNetworkSession, player_id: String, host: bool = false) -> void:
	session = network
	local_player_id = player_id
	layer = 2
	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(16,180)
	add_child(panel)
	_label = Label.new()
	_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size",16)
	panel.add_child(_label)
	_update()

func _process(_delta: float) -> void:
	if session != null: _update()

func _update() -> void:
	if session.mode == "HOST":
		_label.text = "Session: %s | Port: %d | Players: %d / 8" % [session.state.capitalize(),session.listen_port,session.peer_to_player.size()]
	else:
		var world_id: String = session.world_manifest.get("world_id","—")
		_label.text = "Leyforge session\n%s%s\nWorld: %s\nPlayer: %s\n" % [session.state.capitalize(),(" — " + session.reason_code) if session.reason_code != "ok" else "",world_id,local_player_id.left(8)]
		if session.state == "CONNECTED":
			_label.text += "Seed: %d | Worldgen: %d | Save: %d\nProtocol: %d | Movement: predicted / server authoritative\nVoxels: HOST authoritative" % [session.world_manifest["seed"],session.world_manifest["worldgen_version"],session.world_manifest["save_version"],session.world_manifest["network_protocol_version"]]

func start_join(options: LfeSessionOptions) -> bool:
	var profile: LfeLocalProfile = LfeLocalProfile.new()
	if profile.open_profile(options.profile_path) != OK:
		push_error(profile.error)
		return false
	var fingerprint: String = LfeCompatibilityManifest.fingerprint()
	if fingerprint.is_empty():
		push_error("Canonical content fingerprint failed")
		return false
	var network: LfeNetworkSession = LfeNetworkSession.new()
	add_child(network)
	build(network,profile.player_id)
	return network.start_join(options.address,options.port,LfeCompatibilityManifest.hello(profile.player_id,fingerprint))
