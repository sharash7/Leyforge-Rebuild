extends Node

const TerrainRules = preload("res://src/lfe/worldgen/wave_1_terrain_rules.gd")
const WALK_SAMPLE_FRAMES: int = 55
const SPRINT_SAMPLE_FRAMES: int = 55
const TRAVERSAL_FRAMES: int = 210

var _world: LeyforgeWave1Playground
var _player: LeyforgeFirstPersonPlayer
var _terrain: VoxelTerrain
var _catalog: LfeBlockCatalog
var _seed: int = 0
var _voxel_tool: VoxelTool
var _output_directory: String = ""
var _failures: Array[String] = []
var _checks: int = 0
var _report: Dictionary = {}
var _started: bool = false


func configure(
	world: LeyforgeWave1Playground,
	player: LeyforgeFirstPersonPlayer,
	terrain: VoxelTerrain,
	catalog: LfeBlockCatalog,
	seed: int
) -> void:
	_world = world
	_player = player
	_terrain = terrain
	_catalog = catalog
	_seed = seed
	_voxel_tool = terrain.get_voxel_tool()
	_voxel_tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	_output_directory = _resolve_output_directory()
	call_deferred("_run")


func _run() -> void:
	if _started:
		return
	_started = true
	if not _world.is_runtime_ready():
		await _world.runtime_ready
	for _warmup_frame: int in range(8):
		await get_tree().process_frame

	var directory_error: Error = DirAccess.make_dir_recursive_absolute(_output_directory)
	_check(directory_error == OK, "Could not create rendered-playtest output directory.")
	_report["runner"] = Engine.get_version_info().get("string", "unknown")
	_report["seed"] = _seed
	_report["output_directory"] = _output_directory

	await _capture_frame("01_spawn.png")
	await _exercise_movement()
	await _exercise_chunk_boundary_editing()
	await _capture_frame("03_after_boundary_break.png")
	_release_all_actions()

	_report["checks"] = _checks
	_report["failures"] = _failures
	_report["passed"] = _failures.is_empty()
	_write_report()

	if _failures.is_empty():
		print(
			"WAVE_1_PLAYTEST_PASS checks=%d evidence=%s"
			% [_checks, _output_directory]
		)
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("Wave 1 playtest: %s" % failure)
		print(
			"WAVE_1_PLAYTEST_FAIL checks=%d failures=%d evidence=%s"
			% [_checks, _failures.size(), _output_directory]
		)
		get_tree().quit(1)


func _exercise_movement() -> void:
	await _wait_for_floor(120)
	_check(_player.is_on_floor(), "Player did not settle on streamed terrain.")

	var walk_start: Vector3 = _player.global_position
	var walk_peak_speed: float = 0.0
	Input.action_press("move_forward")
	for _frame_index: int in range(WALK_SAMPLE_FRAMES):
		await get_tree().physics_frame
		walk_peak_speed = maxf(walk_peak_speed, _horizontal_speed())
	Input.action_release("move_forward")
	await _wait_physics_frames(12)
	var walk_distance: float = _horizontal_distance(walk_start, _player.global_position)
	_report["walk_distance"] = walk_distance
	_report["walk_peak_speed"] = walk_peak_speed
	_check(walk_distance > 1.5, "WASD forward input did not move the player far enough.")
	_check(walk_peak_speed > 3.5, "Walk speed never reached a playable value.")

	await _wait_for_floor(120)
	var jump_start_y: float = _player.global_position.y
	var jump_peak_y: float = jump_start_y
	Input.action_press("jump")
	await _wait_physics_frames(3)
	Input.action_release("jump")
	for _frame_index: int in range(100):
		await get_tree().physics_frame
		jump_peak_y = maxf(jump_peak_y, _player.global_position.y)
		if _frame_index > 20 and _player.is_on_floor():
			break
	var jump_rise: float = jump_peak_y - jump_start_y
	_report["jump_rise"] = jump_rise
	_check(jump_rise > 0.65, "Jump input did not produce a clear upward movement.")

	var sprint_start: Vector3 = _player.global_position
	var sprint_peak_speed: float = 0.0
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for _frame_index: int in range(SPRINT_SAMPLE_FRAMES):
		await get_tree().physics_frame
		sprint_peak_speed = maxf(sprint_peak_speed, _horizontal_speed())
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await _wait_physics_frames(12)
	var sprint_distance: float = _horizontal_distance(sprint_start, _player.global_position)
	_report["sprint_distance"] = sprint_distance
	_report["sprint_peak_speed"] = sprint_peak_speed
	_check(sprint_distance > walk_distance * 1.15, "Sprint did not outpace the walk sample.")
	_check(sprint_peak_speed > walk_peak_speed + 1.5, "Sprint input did not raise horizontal speed.")

	var traversal_start: Vector3 = _player.global_position
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for frame_index: int in range(TRAVERSAL_FRAMES):
		if frame_index % 42 == 0:
			Input.action_press("jump")
		elif frame_index % 42 == 4:
			Input.action_release("jump")
		await get_tree().physics_frame
	Input.action_release("jump")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await _wait_physics_frames(8)
	var traversal_distance: float = _horizontal_distance(
		traversal_start,
		_player.global_position
	)
	_report["traversal_distance"] = traversal_distance
	_check(
		traversal_distance > 16.0,
		"Player did not traverse at least one full 16-voxel chunk during the rendered run."
	)
	_check(
		_player.global_position.y > float(TerrainRules.MIN_HEIGHT) - 8.0,
		"Player fell out of the generated terrain during traversal."
	)


func _exercise_chunk_boundary_editing() -> void:
	var boundary_case: Dictionary = _find_boundary_case()
	_check(not boundary_case.is_empty(), "Could not find an exposed generated face at a chunk boundary.")
	if boundary_case.is_empty():
		return

	var target_cell: Vector3i = boundary_case["target"] as Vector3i
	var placement_cell: Vector3i = boundary_case["placement"] as Vector3i
	var outward_sign: int = int(boundary_case["outward_sign"])
	_report["boundary_target"] = str(target_cell)
	_report["boundary_placement"] = str(placement_cell)

	var surface_height: int = maxi(
		TerrainRules.height_at(_seed, target_cell.x, target_cell.z),
		TerrainRules.height_at(_seed, placement_cell.x, placement_cell.z)
	)
	_player.global_position = Vector3(
		float(placement_cell.x) + float(outward_sign) * 2.0 + 0.5,
		float(surface_height) + 2.05,
		float(placement_cell.z) + 0.5
	)
	_player.velocity = Vector3.ZERO

	var edit_area: AABB = AABB(
		Vector3(
			float(mini(target_cell.x, placement_cell.x) - 1),
			float(target_cell.y - 2),
			float(target_cell.z - 1)
		),
		Vector3(4.0, 5.0, 3.0)
	)
	var editable: bool = false
	for _frame_index: int in range(300):
		await get_tree().physics_frame
		if _voxel_tool.is_area_editable(edit_area):
			editable = true
			break
	_check(editable, "Chunk-boundary edit area did not become editable.")
	if not editable:
		return

	var camera: Camera3D = _player.get_camera()
	camera.top_level = true
	camera.global_position = (
		Vector3(target_cell)
		+ Vector3(0.5 + float(outward_sign) * 3.0, 0.5, 0.5)
	)
	camera.look_at(Vector3(target_cell) + Vector3.ONE * 0.5, Vector3.UP)
	await _wait_physics_frames(4)

	_check(_player.has_voxel_target(), "Camera ray did not acquire the boundary voxel.")
	_check(
		_player.get_target_cell() == target_cell,
		"Camera ray targeted %s instead of expected %s."
		% [_player.get_target_cell(), target_cell]
	)
	_check(
		_player.get_placement_cell() == placement_cell,
		"Adjacent placement cell was %s instead of expected %s."
		% [_player.get_placement_cell(), placement_cell]
	)

	var selected_before: int = _player.get_selected_voxel_id()
	await _tap_action("cycle_block")
	var selected_after: int = _player.get_selected_voxel_id()
	_check(selected_after != selected_before, "Development block cycling did not change selection.")

	await _tap_action("place_block")
	await _wait_physics_frames(18)
	var placed_voxel_id: int = _voxel_tool.get_voxel(placement_cell)
	_check(
		placed_voxel_id == selected_after,
		"Placement input did not write the selected block at the adjacent boundary cell."
	)
	_check(
		_cell_top_has_collision(placement_cell),
		"Placed boundary voxel did not acquire physics collision."
	)
	await _capture_frame("02_boundary_place.png")

	await _tap_action("break_block")
	await _wait_physics_frames(18)
	var air_voxel_id: int = _catalog.get_voxel_id(&"leyforge:air")
	_check(
		_voxel_tool.get_voxel(placement_cell) == air_voxel_id,
		"Break input did not clear the placed boundary voxel."
	)
	_check(
		not _cell_top_has_collision(placement_cell),
		"Broken boundary voxel retained stale physics collision."
	)

	_player.global_position = Vector3(placement_cell) + Vector3(0.5, 0.0, 0.5)
	_player.velocity = Vector3.ZERO
	await _wait_physics_frames(1)
	await _tap_action("place_block")
	await _wait_physics_frames(3)
	_check(
		_voxel_tool.get_voxel(placement_cell) == air_voxel_id,
		"Placement inside the player's occupied body volume was not rejected."
	)


func _find_boundary_case() -> Dictionary:
	var boundaries: Array[int] = [15, -1, 31, -17]
	for left_x: int in boundaries:
		var right_x: int = left_x + 1
		for world_z: int in range(-48, 49):
			var left_height: int = TerrainRules.height_at(_seed, left_x, world_z)
			var right_height: int = TerrainRules.height_at(_seed, right_x, world_z)
			if left_height > right_height:
				return {
					"target": Vector3i(left_x, left_height, world_z),
					"placement": Vector3i(right_x, left_height, world_z),
					"outward_sign": 1,
				}
			if right_height > left_height:
				return {
					"target": Vector3i(right_x, right_height, world_z),
					"placement": Vector3i(left_x, right_height, world_z),
					"outward_sign": -1,
				}
	return {}


func _cell_top_has_collision(cell: Vector3i) -> bool:
	var cell_center: Vector3 = Vector3(cell) + Vector3.ONE * 0.5
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		cell_center + Vector3.UP * 0.9,
		cell_center + Vector3.UP * 0.1,
		1
	)
	query.exclude = [_player.get_rid()]
	return not _player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _capture_frame(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var image_path: String = _output_directory.path_join(file_name)
	var save_error: Error = image.save_png(image_path)
	_check(save_error == OK, "Could not save rendered frame %s." % image_path)


func _tap_action(action: StringName) -> void:
	Input.action_press(action)
	await _wait_physics_frames(3)
	Input.action_release(action)
	await _wait_physics_frames(3)


func _wait_physics_frames(frame_count: int) -> void:
	for _frame_index: int in range(frame_count):
		await get_tree().physics_frame


func _wait_for_floor(maximum_frames: int) -> void:
	for _frame_index: int in range(maximum_frames):
		if _player.is_on_floor():
			return
		await get_tree().physics_frame


func _horizontal_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


func _horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


func _check(condition: bool, failure_message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(failure_message)


func _resolve_output_directory() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--wave1-playtest-out="):
			var requested_path: String = argument.trim_prefix("--wave1-playtest-out=")
			if requested_path.begins_with("res://") or requested_path.begins_with("user://"):
				return ProjectSettings.globalize_path(requested_path)
			return requested_path
	return ProjectSettings.globalize_path("res://.verification/wave1")


func _write_report() -> void:
	var report_path: String = _output_directory.path_join("playtest_report.json")
	var report_file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		_failures.append("Could not write playtest report %s." % report_path)
		return
	report_file.store_string(JSON.stringify(_report, "\t") + "\n")


func _release_all_actions() -> void:
	for action: StringName in [
		&"move_forward",
		&"move_back",
		&"move_left",
		&"move_right",
		&"jump",
		&"sprint",
		&"break_block",
		&"place_block",
		&"cycle_block",
	]:
		Input.action_release(action)
