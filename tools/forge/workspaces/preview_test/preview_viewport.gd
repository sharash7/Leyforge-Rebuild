extends VBoxContainer
## A disposable plugin-meshed volume. No terrain, world, physics or network state.
var viewport: SubViewport
var surface: SubViewportContainer
var preview_root: Node3D
var camera: Camera3D
var content: MeshInstance3D
var identity: String = ""
var validated_revision: int = -1
var bounds: AABB = AABB(Vector3.ZERO, Vector3.ONE)
var yaw: float = 0.7
var pitch: float = 0.45
var distance: float = 3.4
var focus: Vector3 = Vector3(0.5, 0.5, 0.5)
var dragging: int = 0
var info: Label
var asset_mode: bool = false
signal asset_input(event: InputEvent)
signal capture_cancelled

func _ready() -> void:
	var toolbar: HBoxContainer = HBoxContainer.new(); add_child(toolbar)
	var frame: Button = Button.new(); frame.text = "Frame Selection (F)"; toolbar.add_child(frame)
	frame.pressed.connect(frame_selection)
	info = Label.new(); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; toolbar.add_child(info)
	surface = SubViewportContainer.new(); surface.stretch = true; surface.size_flags_vertical = Control.SIZE_EXPAND_FILL; surface.custom_minimum_size = Vector2(220, 180); surface.focus_mode = Control.FOCUS_ALL; add_child(surface)
	viewport = SubViewport.new(); viewport.own_world_3d = true; viewport.handle_input_locally = false; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; surface.add_child(viewport)
	preview_root = Node3D.new(); viewport.add_child(preview_root)
	camera = Camera3D.new(); camera.near = 0.01; camera.far = 100; preview_root.add_child(camera)
	var environment: WorldEnvironment = WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color("18232e"); environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color.WHITE; environment.environment.ambient_light_energy = 0.65; preview_root.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new(); light.rotation_degrees = Vector3(-40, -25, 0); preview_root.add_child(light)
	_grid()
	surface.gui_input.connect(_viewport_input)
	surface.mouse_exited.connect(func() -> void: dragging = 0; capture_cancelled.emit(); surface.release_focus())
	surface.focus_exited.connect(func() -> void: dragging = 0; capture_cancelled.emit())
	var help: Label = Label.new(); help.text = "Click to focus · LMB orbit · Shift+LMB / MMB pan · Wheel zoom · F frame"; help.add_theme_font_size_override("font_size", 13); add_child(help)
	_update_camera()

func _grid() -> void:
	var lines: ImmediateMesh = ImmediateMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.vertex_color_use_as_albedo = true
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for n: int in range(-3, 5):
		lines.surface_set_color(Color("354653")); lines.surface_add_vertex(Vector3(n, -0.015, -3)); lines.surface_add_vertex(Vector3(n, -0.015, 4)); lines.surface_add_vertex(Vector3(-3, -0.015, n)); lines.surface_add_vertex(Vector3(4, -0.015, n))
	for axis: int in 3:
		lines.surface_set_color([Color("ed6464"), Color("71c98b"), Color("68a8ee")][axis]); lines.surface_add_vertex(Vector3.ZERO)
		var endpoint: Vector3 = Vector3.ZERO; endpoint[axis] = 1.8; lines.surface_add_vertex(endpoint)
	lines.surface_end()
	var node: MeshInstance3D = MeshInstance3D.new(); node.mesh = lines; preview_root.add_child(node)

func show_selection(catalog: LfeBlockCatalog, id: String, revision: int) -> bool:
	if content != null: content.free(); content = null
	identity = id; validated_revision = revision
	info.text = id + " · unit bounds [0,1]³"
	var voxel_id: int = catalog.get_voxel_id(StringName(id))
	if voxel_id < 0 or not catalog.is_solid_voxel(voxel_id):
		info.text = id + " · read-only / no solid voxel"; return true
	var mesher: VoxelMesherBlocky = VoxelMesherBlocky.new()
	mesher.library = LfeBlockyLibraryFactory.create(catalog); mesher.library.bake()
	var padding: int = mesher.get_minimum_padding()
	var extent: int = 1 + padding + mesher.get_maximum_padding()
	var volume: VoxelBuffer = VoxelBuffer.new(); volume.create(extent, extent, extent)
	volume.set_voxel(voxel_id, padding, padding, padding, VoxelBuffer.CHANNEL_TYPE)
	var mesh: Mesh = mesher.build_mesh(volume, [LfeBlockyLibraryFactory.create_material()])
	if mesh == null or mesh.get_surface_count() == 0: info.text = "Plugin returned no preview mesh"; return false
	content = MeshInstance3D.new(); content.mesh = mesh; preview_root.add_child(content)
	bounds = mesh.get_aabb()
	return true

func selection_ray(position: Vector2) -> Dictionary:
	return {"origin": camera.project_ray_origin(position), "direction": camera.project_ray_normal(position), "id": identity, "bounds": bounds}

func frame_selection() -> void:
	focus = bounds.get_center()
	if asset_mode:
		var aspect: float = maxf(0.1, surface.size.x / maxf(1.0,surface.size.y))
		distance = maxf(0.15, bounds.size.length() / (2.0 * tan(deg_to_rad(camera.fov)*0.5) * minf(1.0,aspect)) * 1.3)
	else: distance = 3.4
	_update_camera()

func _viewport_input(event: InputEvent) -> void:
	if asset_mode:
		_asset_camera_input(event)
		asset_input.emit(event)
		return
	if event is InputEventMouseButton:
		if event.pressed: surface.grab_focus()
		if not surface.has_focus(): return
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]: dragging = event.button_index if event.pressed else 0
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance * (0.86 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.16), 1.2, 20.0)
	elif event is InputEventMouseMotion and surface.has_focus() and dragging != 0:
		if dragging == MOUSE_BUTTON_MIDDLE or event.shift_pressed:
			focus += (-camera.global_basis.x * event.relative.x + camera.global_basis.y * event.relative.y) * distance * 0.002
		else:
			yaw -= event.relative.x * 0.008; pitch = clampf(pitch + event.relative.y * 0.008, -1.4, 1.4)
	elif event is InputEventKey and surface.has_focus() and event.pressed and event.keycode == KEY_F: frame_selection()
	_update_camera()

func _asset_camera_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed: surface.grab_focus()
		if event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			dragging=event.button_index if event.pressed else 0; capture_cancelled.emit()
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			distance=clampf(distance*(0.86 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.16),0.08,30.0)
	elif event is InputEventMouseMotion and dragging!=0 and surface.has_focus():
		if dragging==MOUSE_BUTTON_MIDDLE: focus+=(-camera.global_basis.x*event.relative.x+camera.global_basis.y*event.relative.y)*distance*0.002
		else: yaw-=event.relative.x*0.008; pitch=clampf(pitch+event.relative.y*0.008,-1.55,1.55)
	elif event is InputEventKey and event.pressed and surface.has_focus() and event.keycode==KEY_F: frame_selection()
	_update_camera()

func asset_ray(position: Vector2) -> Dictionary:
	var pixels: Vector2 = position * Vector2(viewport.size) / surface.size
	return selection_ray(pixels)

func show_asset(bundle: Dictionary, id: String, revision: int) -> void:
	asset_mode=true; identity=id; validated_revision=revision
	if content!=null: content.free();content=null
	info.text=id+" · 16³ cells · 1 m · X right / Y up / −Z front"
	if not bundle.is_empty():
		var loader = preload("res://src/lfe/voxel/voxel_asset_loader.gd")
		content=MeshInstance3D.new();content.mesh=loader.mesh(bundle);content.material_override=loader.material();preview_root.add_child(content)
	bounds=AABB(Vector3.ZERO,Vector3.ONE)

func set_view(axis: String) -> void:
	match axis:
		"Front": yaw=PI;pitch=0
		"Top": yaw=0;pitch=1.55
		"Side": yaw=PI/2;pitch=0
	_update_camera()

func _update_camera() -> void:
	if camera == null: return
	camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(focus)
