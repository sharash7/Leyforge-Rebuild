extends SceneTree
## Separate rendered process. Commands inject normal Godot pointer/keyboard events.
var app: Control
var proof: String
var processed: int = 0
var pointer: Vector2 = Vector2.ZERO
var captured: Array = []
var busy: bool = true

func _initialize() -> void:
	proof = OS.get_cmdline_user_args()[0]
	call_deferred("start")

func start() -> void:
	app = load("res://tools/forge/forge.tscn").instantiate(); root.add_child(app)
	await process_frame
	await process_frame
	await process_frame
	write_report()
	busy = false

func _process(_delta: float) -> bool:
	if app == null: return false
	if FileAccess.file_exists(proof + ".stop"): app._close(); return false
	if not busy and FileAccess.file_exists(proof + ".command.json"):
		busy = true
		var claimed: String = proof + ".processing.json"
		if DirAccess.rename_absolute(proof + ".command.json", claimed) != OK: busy = false; return false
		var payload: String = FileAccess.get_file_as_string(claimed)
		var read_error: Error = FileAccess.get_open_error()
		var parser: JSON = JSON.new()
		var parsed: Error = parser.parse(payload)
		if parsed == OK and parser.data is Dictionary:
			DirAccess.remove_absolute(claimed)
			call_deferred("execute", parser.data)
		else:
			DirAccess.rename_absolute(claimed, proof + ".failed-command.json")
			push_error("Malformed Forge test command: read_error=%d bytes=%d parse_error=%d line=%d detail=%s payload=%s" % [read_error, payload.to_utf8_buffer().size(), parsed, parser.get_error_line(), parser.get_error_message(), payload])
			quit(2)
	return false

func mouse(position: Vector2, button: int, pressed: bool, shift: bool = false) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new(); event.position = position; event.global_position = position; event.button_index = button; event.pressed = pressed; event.shift_pressed = shift
	Input.parse_input_event(event)

func click(position: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	mouse(position, button, true); mouse(position, button, false)

func execute(command: Dictionary) -> void:
	match command.op:
		"click": click(Vector2(command.x, command.y), int(command.get("button", 1)))
		"key":
			var event: InputEventKey = InputEventKey.new(); event.keycode = int(command.code); event.ctrl_pressed = command.get("ctrl", false); event.pressed = true; Input.parse_input_event(event); event = event.duplicate(); event.pressed = false; Input.parse_input_event(event)
		"text":
			for character: String in str(command.text):
				var event: InputEventKey = InputEventKey.new(); event.unicode = character.unicode_at(0); event.pressed = true; Input.parse_input_event(event)
		"drag":
			var start_position: Vector2 = Vector2(command.x, command.y)
			mouse(start_position, int(command.get("button", 1)), true, command.get("shift", false))
			for n: int in range(1, 11):
				var event: InputEventMouseMotion = InputEventMouseMotion.new(); event.position = start_position + Vector2(command.dx, command.dy) * n / 10.0; event.relative = Vector2(command.dx, command.dy) / 10.0; event.shift_pressed = command.get("shift", false); event.button_mask = MOUSE_BUTTON_MASK_LEFT; Input.parse_input_event(event)
			mouse(start_position + Vector2(command.dx, command.dy), int(command.get("button", 1)), false)
		"resize": root.size = Vector2i(command.width, command.height)
		"capture":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(command.path)
			captured.append(command.path)
	await process_frame
	await process_frame
	processed += 1
	write_report()
	busy = false

func walk(node: Node, widgets: Array) -> void:
	if node is Control and node.is_visible_in_tree() and node.get_window().visible and (node is Button or node is LineEdit or node is ItemList or node is TabBar or node is SubViewportContainer):
		var rect: Rect2 = node.get_global_rect()
		if node.get_window() != root: rect.position += Vector2(node.get_window().position)
		widgets.append({"role": "search" if node == app.presentation.search else "", "class": node.get_class(), "text": node.text if node is Button or node is LineEdit else node.name, "path": str(node.get_path()), "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "focus": node.has_focus()})
	for child: Node in node.get_children(true): walk(child, widgets)

func write_report() -> void:
	var widgets: Array = []; walk(app, widgets)
	var tabs: Array = []
	var bar: TabBar = app.pages.get_tab_bar()
	for index: int in bar.tab_count:
		var tab: Rect2 = bar.get_tab_rect(index)
		tab.position += bar.global_position
		tabs.append([tab.position.x, tab.position.y, tab.size.x, tab.size.y])
	var document: RefCounted = app.document
	var mesh_color: String = ""
	if app.preview.content != null:
		var arrays: Array = app.preview.content.mesh.surface_get_arrays(0)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		if not colors.is_empty(): mesh_color = colors[0].to_html(true)
	var file: FileAccess = FileAccess.open(proof + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"window_size": [root.size.x, root.size.y], "ready": true, "pid": OS.get_process_id(), "processed": processed, "revision": document.revision, "dirty": document.dirty(), "stone": document.definition("leyforge:stone"), "selected": app.selected_id, "validation": document.validation, "last_result": app.last_result, "page": app.pages.current_tab, "undo": document.history.cursor, "redo": document.history.commands.size() - document.history.cursor, "yaw": app.preview.yaw, "pitch": app.preview.pitch, "distance": app.preview.distance, "focus": [app.preview.focus.x, app.preview.focus.y, app.preview.focus.z], "mesh_color": mesh_color, "preview_nodes": app.preview.preview_root.get_child_count(), "preview_identity": app.preview.identity, "mesh": app.preview.content != null, "tabs": tabs, "widgets": widgets, "captures": captured}, "  "))
	file.close()
