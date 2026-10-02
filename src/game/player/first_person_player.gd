class_name LeyforgeFirstPersonPlayer
extends CharacterBody3D

signal block_broken(cell: Vector3i, previous_voxel_id: int)
signal block_placed(cell: Vector3i, voxel_id: int)

const WALK_SPEED: float = 5.0
const SPRINT_SPEED: float = 8.5
const GROUND_ACCELERATION: float = 24.0
const AIR_ACCELERATION: float = 8.0
const DECELERATION: float = 30.0
const JUMP_VELOCITY: float = 6.25
const MOUSE_SENSITIVITY: float = 0.0022
const INTERACTION_RANGE: float = 6.0
const MAX_LOOK_ANGLE: float = deg_to_rad(89.0)

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _viewer: VoxelViewer = $Head/Camera3D/VoxelViewer
@onready var _target_highlight: MeshInstance3D = $TargetHighlight
@onready var _debug_label: Label = $Interface/DebugLabel
@onready var _instruction_label: Label = $Interface/InstructionLabel

var _terrain: VoxelTerrain
var _catalog: LfeBlockCatalog
var _voxel_tool: VoxelTool
var _active_seed: int = 0
var _configured: bool = false
var _runtime_ready: bool = false
var _placeable_ids: Array[StringName] = []
var _selected_placeable_index: int = 0
var _has_target: bool = false
var _target_cell: Vector3i = Vector3i.ZERO
var _placement_cell: Vector3i = Vector3i.ZERO
var _status_message: String = "Waiting for streamed terrain..."
var _status_expires_at_msec: int = 0
var _gravity: float = 9.8
var _playtest_mode: bool = false


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_playtest_mode = OS.get_cmdline_user_args().has("--wave1-playtest")
	_build_target_highlight()
	_instruction_label.text = (
		"WASD move  |  Shift sprint  |  Space jump  |  Q cycle block\n"
		+ "Left mouse break  |  Right mouse place  |  Escape release mouse"
	)
	if DisplayServer.get_name() != "headless" and not _playtest_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_debug_overlay()


func configure(
	terrain: VoxelTerrain,
	catalog: LfeBlockCatalog,
	active_seed: int,
	spawn_position: Vector3
) -> void:
	_terrain = terrain
	_catalog = catalog
	_active_seed = active_seed
	global_position = spawn_position
	_voxel_tool = terrain.get_voxel_tool()
	_voxel_tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	_voxel_tool.set_raycast_normal_enabled(true)
	_placeable_ids = catalog.development_placeable_ids()
	_configured = true
	_update_debug_overlay()


func set_runtime_ready(ready: bool) -> void:
	_runtime_ready = ready
	if ready:
		_set_status("Terrain ready", 1500)
	else:
		velocity = Vector3.ZERO


func is_runtime_ready() -> bool:
	return _runtime_ready


func get_camera() -> Camera3D:
	return _camera


func get_viewer() -> VoxelViewer:
	return _viewer


func has_voxel_target() -> bool:
	return _has_target


func get_target_cell() -> Vector3i:
	return _target_cell


func get_placement_cell() -> Vector3i:
	return _placement_cell


func get_selected_voxel_id() -> int:
	if _catalog == null or _placeable_ids.is_empty():
		return -1
	return _catalog.get_voxel_id(_placeable_ids[_selected_placeable_index])


func get_selected_canonical_id() -> StringName:
	if _placeable_ids.is_empty():
		return &""
	return _placeable_ids[_selected_placeable_index]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _playtest_mode:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
		rotation.y -= mouse_motion.relative.x * MOUSE_SENSITIVITY
		_head.rotation.x = clampf(
			_head.rotation.x - mouse_motion.relative.y * MOUSE_SENSITIVITY,
			-MAX_LOOK_ANGLE,
			MAX_LOOK_ANGLE
		)


func _physics_process(delta: float) -> void:
	if not _configured:
		return
	if not _runtime_ready:
		velocity = Vector3.ZERO
		_update_debug_overlay()
		return

	_update_targeting()
	_handle_interaction_actions()
	_apply_movement(delta)
	_update_debug_overlay()


func _apply_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var input_vector: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)
	var movement_direction: Vector3 = (
		transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)
	).normalized()
	var movement_speed: float = SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var acceleration: float = GROUND_ACCELERATION if is_on_floor() else AIR_ACCELERATION

	if movement_direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, movement_direction.x * movement_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, movement_direction.z * movement_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, DECELERATION * delta)
		velocity.z = move_toward(velocity.z, 0.0, DECELERATION * delta)

	move_and_slide()


func _handle_interaction_actions() -> void:
	if Input.is_action_just_pressed("cycle_block"):
		cycle_development_block()
	if not _playtest_mode and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if Input.is_action_just_pressed("break_block"):
		try_break_target()
	if Input.is_action_just_pressed("place_block"):
		try_place_target()


func cycle_development_block() -> void:
	if _placeable_ids.is_empty():
		return
	_selected_placeable_index = (_selected_placeable_index + 1) % _placeable_ids.size()
	_set_status(
		"Selected %s" % _catalog.display_name_for_voxel_id(get_selected_voxel_id()),
		1200
	)


func try_break_target() -> bool:
	_update_targeting()
	if not _has_target:
		_set_status("Nothing in range", 900)
		return false
	if not _voxel_tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(_target_cell)):
		_set_status("Target chunk is still streaming", 900)
		return false

	var current_voxel_id: int = _voxel_tool.get_voxel(_target_cell)
	if not _catalog.is_breakable_voxel(current_voxel_id):
		_set_status("Target is not breakable", 900)
		return false

	_voxel_tool.set_voxel(_target_cell, _catalog.get_voxel_id(&"leyforge:air"))
	block_broken.emit(_target_cell, current_voxel_id)
	print(
		"WAVE_1_BLOCK_BROKEN cell=%s block=%s"
		% [_target_cell, _catalog.canonical_id_for_voxel_id(current_voxel_id)]
	)
	_set_status("Broke %s" % _catalog.display_name_for_voxel_id(current_voxel_id), 1000)
	_has_target = false
	_target_highlight.visible = false
	return true


func try_place_target() -> bool:
	_update_targeting()
	if not _has_target:
		_set_status("Nothing in range", 900)
		return false
	if not _voxel_tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(_placement_cell)):
		_set_status("Placement chunk is still streaming", 900)
		return false

	var current_voxel_id: int = _voxel_tool.get_voxel(_placement_cell)
	var air_voxel_id: int = _catalog.get_voxel_id(&"leyforge:air")
	var player_aabb: AABB = LfeVoxelInteractionRules.player_body_aabb(global_position)
	if not LfeVoxelInteractionRules.can_place(
		current_voxel_id,
		air_voxel_id,
		_placement_cell,
		player_aabb
	):
		_set_status("Placement blocked", 900)
		return false

	var selected_voxel_id: int = get_selected_voxel_id()
	_voxel_tool.set_voxel(_placement_cell, selected_voxel_id)
	block_placed.emit(_placement_cell, selected_voxel_id)
	print(
		"WAVE_1_BLOCK_PLACED cell=%s block=%s"
		% [_placement_cell, _catalog.canonical_id_for_voxel_id(selected_voxel_id)]
	)
	_set_status("Placed %s" % _catalog.display_name_for_voxel_id(selected_voxel_id), 1000)
	return true


func _update_targeting() -> void:
	if _voxel_tool == null:
		_clear_target()
		return

	var result: VoxelRaycastResult = _voxel_tool.raycast(
		_camera.global_position,
		-_camera.global_basis.z,
		INTERACTION_RANGE
	)
	if result == null:
		_clear_target()
		return

	var hit_cell: Vector3i = result.position
	if not LfeVoxelInteractionRules.cell_is_within_range(
		_camera.global_position,
		hit_cell,
		INTERACTION_RANGE
	):
		_clear_target()
		return

	_has_target = true
	_target_cell = hit_cell
	_placement_cell = result.previous_position
	_target_highlight.global_position = Vector3(_target_cell) + Vector3.ONE * 0.5
	_target_highlight.visible = true


func _clear_target() -> void:
	_has_target = false
	_target_highlight.visible = false


func _set_status(message: String, duration_msec: int) -> void:
	_status_message = message
	_status_expires_at_msec = Time.get_ticks_msec() + duration_msec


func _update_debug_overlay() -> void:
	if _debug_label == null:
		return
	if _status_expires_at_msec > 0 and Time.get_ticks_msec() >= _status_expires_at_msec:
		_status_message = "Ready"
		_status_expires_at_msec = 0

	var target_text: String = "none"
	if _has_target:
		target_text = "%s -> place %s" % [_target_cell, _placement_cell]

	var selected_text: String = "none"
	if _catalog != null and get_selected_voxel_id() >= 0:
		selected_text = "%s (%s)" % [
			_catalog.display_name_for_voxel_id(get_selected_voxel_id()),
			get_selected_canonical_id(),
		]

	_debug_label.text = (
		"Leyforge — Wave 1\n"
		+ "Seed: %d\n" % _active_seed
		+ "Position: (%.1f, %.1f, %.1f)\n" % [global_position.x, global_position.y, global_position.z]
		+ "Target: %s\n" % target_text
		+ "Development block: %s\n" % selected_text
		+ "Status: %s" % _status_message
	)


func _build_target_highlight() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.84, 0.2, 1.0)

	var line_mesh: ImmediateMesh = ImmediateMesh.new()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var corners: Array[Vector3] = [
		Vector3(-0.505, -0.505, -0.505),
		Vector3(0.505, -0.505, -0.505),
		Vector3(0.505, 0.505, -0.505),
		Vector3(-0.505, 0.505, -0.505),
		Vector3(-0.505, -0.505, 0.505),
		Vector3(0.505, -0.505, 0.505),
		Vector3(0.505, 0.505, 0.505),
		Vector3(-0.505, 0.505, 0.505),
	]
	var edges: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
		Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
	]
	for edge: Vector2i in edges:
		line_mesh.surface_add_vertex(corners[edge.x])
		line_mesh.surface_add_vertex(corners[edge.y])
	line_mesh.surface_end()

	_target_highlight.mesh = line_mesh
	_target_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_target_highlight.visible = false
