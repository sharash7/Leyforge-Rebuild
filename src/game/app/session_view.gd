class_name LeyforgeSessionView
extends CanvasLayer

var session: LfeNetworkSession
var game: LeyforgeWave1Playground
var local_player_id: String = ""
var _label: Label
var _ended: PanelContainer
var _ended_label: Label
var reconnect_button: Button
var _reason: String = ""
var _attempting: bool = false
var _invite_input: LineEdit
var _host_info: PanelContainer
var _host_label: Label

func build(network: LfeNetworkSession, player_id: String, _host: bool = false) -> void:
	session = network
	local_player_id = player_id
	layer = 2
	if _label != null: return
	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(16,180)
	add_child(panel)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size",16)
	panel.add_child(_label)
	if game != null and not _host: _build_ended()
	if game != null and _host: _build_host()
	_update()

func _build_host() -> void:
	_host_info = PanelContainer.new()
	_host_info.position = Vector2(16,260)
	_host_info.hide()
	add_child(_host_info)
	var body: VBoxContainer = VBoxContainer.new(); _host_info.add_child(body)
	_host_label = Label.new(); _host_label.add_theme_font_size_override("font_size",16); body.add_child(_host_label)
	var copy: Button = Button.new(); copy.text = "Copy Invite"; body.add_child(copy)
	copy.pressed.connect(func():
		var address: String = game.connectivity.external_address
		if address.is_empty(): address = game.connectivity.addresses[0] if not game.connectivity.addresses.is_empty() else "<HOST ADDRESS>"
		DisplayServer.clipboard_set("Leyforge private session\nAddress: %s\nPort: %d (UDP)\nInvite: %s" % [address,session.listen_port,session.private_auth.display_invite()]))
	var toggle: Button = Button.new(); toggle.text = "Session / Invite (F8)"; toggle.position = Vector2(16,220); add_child(toggle)
	toggle.pressed.connect(_toggle_host)

func _toggle_host() -> void:
	_host_info.visible = not _host_info.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _host_info.visible else Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if _host_info != null and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8: _toggle_host()

func _build_ended() -> void:
	var background: ColorRect = ColorRect.new()
	background.name = "SessionEndedBackground"
	background.color = Color(0.035,0.05,0.075,1)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_ended = PanelContainer.new()
	_ended.name = "SessionEnded"
	_ended.position = Vector2(310,200)
	_ended.custom_minimum_size = Vector2(660,300)
	add_child(_ended)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation",20)
	_ended.add_child(body)
	_ended_label = Label.new()
	_ended_label.add_theme_font_size_override("font_size",22)
	body.add_child(_ended_label)
	_invite_input = LineEdit.new()
	_invite_input.secret = true
	_invite_input.placeholder_text = "New invite after HOST restart (blank keeps current in-memory invite)"
	_invite_input.max_length = 39
	body.add_child(_invite_input)
	reconnect_button = Button.new()
	reconnect_button.name = "Reconnect"
	reconnect_button.text = "Reconnect"
	reconnect_button.pressed.connect(func():
		if not _invite_input.text.is_empty():
			game.session_options.invite_secret = LfePrivateSessionAuth.parse_invite(_invite_input.text)
			_invite_input.clear()
		game.reconnect_client())
	body.add_child(reconnect_button)
	var exit_button: Button = Button.new()
	exit_button.name = "Exit"
	exit_button.text = "Exit"
	exit_button.pressed.connect(func(): game.request_client_leave(true))
	body.add_child(exit_button)
	show_connecting()

func _process(_delta: float) -> void:
	if session != null: _update()

func _update() -> void:
	if session.mode == "HOST":
		_label.text = "Session: %s | Port: %d | Players: %d / 8" % [session.state.capitalize(),session.listen_port,session.peer_to_player.size()]
		if _host_label != null and session.private_auth != null:
			_host_label.text = "Listening locally: %s / UDP %d\nLAN candidates: %s\nWAN candidate: %s\n%s\n%s\nInvite: %s\nShare privately. HOST restart requires a new invite." % [session.bind_address,session.listen_port,", ".join(game.connectivity.addresses),game.connectivity.external_address if not game.connectivity.external_address.is_empty() else "unknown (router/ISP)",game.connectivity.status,game.connectivity.warning,session.private_auth.display_invite()]
	else:
		var world_id: String = session.world_manifest.get("world_id","—")
		_label.text = "Leyforge session\n%s%s\nWorld: %s\nPlayer: %s" % [session.state.capitalize(),(" — " + session.reason_code) if session.reason_code != "ok" else "",world_id,local_player_id.left(8)]
		if session.ping_msec >= 0: _label.text += "\nPing: %.0f ms" % session.ping_msec
		if _attempting and _ended_label != null:
			_ended_label.text = "%s\n%s:%d\nPlayer: %s" % ["Synchronizing world…" if session.state == "CONNECTED" else session.state.capitalize(),game.session_options.address,game.session_options.port,local_player_id.left(8)]
		if reconnect_button != null:
			reconnect_button.disabled = _attempting or game._teardown_pending or session.state == "ENDING"

func show_connecting() -> void:
	_attempting = true
	if _ended != null:
		_ended.show()
		get_node("SessionEndedBackground").show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func show_playing() -> void:
	_attempting = false
	_ended.hide()
	get_node("SessionEndedBackground").hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func show_ended(reason: String) -> void:
	_attempting = false
	_reason = reason
	_ended.show()
	get_node("SessionEndedBackground").show()
	var message: String = {"host_shutdown":"Host ended session", "server_disconnected":"Connection to host lost", "server_timeout":"Connection to host lost (timeout)", "connection_failed":"Could not connect to host", "auth_timeout":"Host authentication timed out", "client_left":"You left the session", "world_mismatch":"Host is running a different world", "protocol_mismatch":"Host and client use different network protocols", "build_mismatch":"Host and client use different builds", "private_session_denied":"Private session denied — enter the current invite"}.get(reason,"Session ended: " + reason)
	_ended_label.text = "%s\nWorld: %s\nHost: %s:%d\nPlayer: %s" % [message,game.previous_world_id if not game.previous_world_id.is_empty() else "—",game.session_options.address,game.session_options.port,local_player_id.left(8)]
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func teardown_complete() -> void:
	_update()
