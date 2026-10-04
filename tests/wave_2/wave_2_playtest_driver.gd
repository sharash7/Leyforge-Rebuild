extends Node

const TerrainRules = preload("res://src/lfe/worldgen/wave_1_terrain_rules.gd")

var _world: LeyforgeWave1Playground
var _player: LeyforgeFirstPersonPlayer
var _terrain: VoxelTerrain
var _catalog: LfeBlockCatalog
var _seed: int
var _voxel_tool: VoxelTool
var _output_directory: String = ""
var _phase: String = ""
var _checks: int = 0
var _failures: Array[String] = []
var _report: Dictionary = {}
var _edits: Array = []


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
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--wave2-run="):
			_phase = argument.trim_prefix("--wave2-run=")
		elif argument.begins_with("--wave2-playtest-out="):
			_output_directory = argument.trim_prefix("--wave2-playtest-out=")
	call_deferred("_run")


func _run() -> void:
	if not _world.is_runtime_ready():
		await _world.runtime_ready
	for _index: int in range(8):
		await get_tree().physics_frame
	if _output_directory.is_empty():
		_failures.append("Missing rendered output directory.")
	else:
		_check(DirAccess.make_dir_recursive_absolute(_output_directory) == OK, "Could not create rendered output directory.")
	_report["phase"] = _phase
	_report["world_id"] = _world.world_save.world_id
	_report["seed"] = _seed
	_report["runner"] = Engine.get_version_info().get("string", "unknown")
	match _phase:
		"A":
			await _run_a()
		"B":
			await _run_b()
		"C":
			await _run_c()
		_:
			_failures.append("Unknown rendered phase %s." % _phase)
	_report["checks"] = _checks
	_report["failures"] = _failures
	_report["passed"] = _failures.is_empty()
	_write_report()
	if _failures.is_empty():
		print("WAVE_2_RENDERED_%s_PASS checks=%d" % [_phase, _checks])
		if _phase == "A":
			if not _world.request_save_and_quit():
				push_error("Wave 2 rendered controlled quit save failed.")
				get_tree().quit(1)
		else:
			get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("Wave 2 rendered %s: %s" % [_phase, failure])
		print("WAVE_2_RENDERED_%s_FAIL failures=%d" % [_phase, _failures.size()])
		get_tree().quit(1)


func _run_a() -> void:
	_check(_world.world_save.load_status.begins_with("New world"), "Run A did not create a clean world.")
	_check(_player.is_on_floor(), "Run A player did not settle on terrain.")
	await _capture_frame("01_world_a_before.png")
	var movement_start: Vector3 = _player.global_position
	Input.action_press("move_forward")
	for _index: int in range(70):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	for _index: int in range(10):
		await get_tree().physics_frame
	_report["moved_distance"] = Vector2(
		_player.global_position.x - movement_start.x,
		_player.global_position.z - movement_start.z
	).length()
	_check(float(_report["moved_distance"]) > 2.0, "Run A did not move the player.")
	_player.set_runtime_ready(false)

	var break_locations: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(16, -35)
	]
	for location: Vector2i in break_locations:
		var target: Vector3i = Vector3i(
			location.x, TerrainRules.height_at(_seed, location.x, location.y), location.y
		)
		await _aim_at(target)
		var previous_id: int = _voxel_tool.get_voxel(target)
		_check(_player.try_break_target(), "Run A could not break %s." % target)
		_check(_voxel_tool.get_voxel(target) == _catalog.get_voxel_id(&"leyforge:air"), "Run A break did not change voxel %s." % target)
		_edits.append({
			"position": [target.x, target.y, target.z],
			"block": "leyforge:air",
			"base_block": String(_catalog.canonical_id_for_voxel_id(previous_id)),
		})

	var place_locations: Array[Vector2i] = [
		Vector2i(3, 0), Vector2i(4, 0), Vector2i(-17, 0)
	]
	for index: int in range(place_locations.size()):
		if index > 0:
			_player.cycle_development_block()
		var location: Vector2i = place_locations[index]
		var ground: Vector3i = Vector3i(
			location.x, TerrainRules.height_at(_seed, location.x, location.y), location.y
		)
		var cell: Vector3i = ground + Vector3i.UP
		await _aim_at(ground)
		var chosen_id: int = _player.get_selected_voxel_id()
		_check(_player.try_place_target(), "Run A could not place at %s." % cell)
		_check(_voxel_tool.get_voxel(cell) == chosen_id, "Run A placement voxel was wrong at %s." % cell)
		_edits.append({
			"position": [cell.x, cell.y, cell.z],
			"block": String(_catalog.canonical_id_for_voxel_id(chosen_id)),
			"base_block": "leyforge:air",
		})

	_check(_world.world_save.overrides.count() == _edits.size(), "Run A sparse edit count disagrees with changed cells.")
	_report["new_edits_streamed_out_and_back"] = await _stream_away_and_back(_edits)
	await _capture_frame("02_world_a_after.png")
	var camera: Camera3D = _player.get_camera()
	camera.top_level = false
	camera.position = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	var state: Dictionary = _player.get_persistent_state()
	state["yaw"] = 0.6
	state["pitch"] = -0.2
	_player.restore_persistent_state(state)
	for _index: int in range(20):
		await get_tree().physics_frame
	_player.set_runtime_ready(true)
	for _index: int in range(4):
		await get_tree().physics_frame
	_check(_player.is_on_floor(), "Run A player floor did not stream back after edits.")
	_check(_world.request_save(), "Run A save action failed.")
	_report["saved_player"] = LfeTestWorldSave.player_transform(_world.world_save)
	_report["edits"] = _edits
	_report["override_count"] = _world.world_save.overrides.count()
	_check(FileAccess.file_exists(_world.world_save.get_primary_path()), "Run A save file was not promoted.")


func _run_b() -> void:
	_check(_world.world_save.load_status.begins_with("Loaded world"), "Run B did not load Run A world.")
	var previous_report: Dictionary = _read_report("A")
	if previous_report.is_empty():
		return
	_check(_world.world_save.world_id == String(previous_report["world_id"]), "World ID changed on restart.")
	_check(_seed == int(previous_report["seed"]), "Seed changed on restart.")
	var expected_player: Dictionary = previous_report["saved_player"]
	_check(LfeTestWorldSave.player_transform(_world.world_save) == expected_player, "Saved player state changed on restart.")
	var expected_position: Array = expected_player["position"]
	var expected_vector: Vector3 = Vector3(
		float(expected_position[0]), float(expected_position[1]), float(expected_position[2])
	)
	_check(_player.global_position.distance_to(expected_vector) < 0.2, "Player position was not restored safely.")
	_check(absf(_player.rotation.y - float(expected_player["yaw"])) < 0.001, "Player yaw was not restored.")
	_check(absf(float(_player.get_persistent_state()["pitch"]) - float(expected_player["pitch"])) < 0.001, "Player pitch was not restored.")
	await _capture_frame("03_world_a_restarted.png")
	_player.set_runtime_ready(false)
	var edits: Array = previous_report["edits"]
	for entry: Dictionary in edits:
		await _verify_edit(entry)
	_report["streamed_out_and_back"] = await _stream_away_and_back(edits)
	_report["restored_edit_count"] = edits.size()
	await _capture_frame("04_world_a_streamed_back.png")


func _stream_away_and_back(edits: Array) -> bool:
	var first_position: Array = (edits[0] as Dictionary)["position"]
	var first_cell: Vector3i = Vector3i(
		int(first_position[0]), int(first_position[1]), int(first_position[2])
	)
	var camera: Camera3D = _player.get_camera()
	camera.top_level = true
	camera.global_position = Vector3(340.0, 45.0, 340.0)
	var unloaded: bool = false
	for _index: int in range(360):
		await get_tree().physics_frame
		if not _voxel_tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(first_cell)):
			unloaded = true
			break
	_check(unloaded, "Edited blocks did not stream out during far travel.")
	for entry: Dictionary in edits:
		await _verify_edit(entry)
	return unloaded


func _run_c() -> void:
	_check(_world.world_save.load_status.begins_with("New world"), "Isolation world was not new.")
	_check(_world.world_save.overrides.count() == 0, "Isolation world inherited overrides.")
	var previous_report: Dictionary = _read_report("A")
	if previous_report.is_empty():
		return
	_check(_seed == int(previous_report["seed"]), "Isolation world seed differs.")
	_check(_world.world_save.world_id != String(previous_report["world_id"]), "Isolation world ID did not differ.")
	_player.set_runtime_ready(false)
	for entry: Dictionary in previous_report["edits"]:
		var coordinates: Array = entry["position"]
		var cell: Vector3i = Vector3i(int(coordinates[0]), int(coordinates[1]), int(coordinates[2]))
		await _aim_at(cell)
		var base_id: int = (_terrain.generator as LfeWave1TerrainGenerator).sample_voxel_id(cell)
		_check(_voxel_tool.get_voxel(cell) == base_id, "Isolation world inherited edit at %s." % cell)
	_check(LfeTestWorldSave.player_transform(_world.world_save).is_empty(), "Isolation world inherited player state.")
	await _capture_frame("05_isolated_world.png")
	_report["isolated_edit_count"] = 0


func _aim_at(target: Vector3i) -> void:
	var camera: Camera3D = _player.get_camera()
	camera.top_level = true
	var center: Vector3 = Vector3(target) + Vector3.ONE * 0.5
	camera.global_position = center + Vector3(0.25, 3.0, 0.25)
	camera.look_at(center, Vector3.UP)
	var area: AABB = LfeVoxelInteractionRules.cell_aabb(target)
	var editable: bool = false
	for _index: int in range(360):
		await get_tree().physics_frame
		if _voxel_tool.is_area_editable(area):
			editable = true
			break
	_check(editable, "Cell did not stream in at %s." % target)
	for _index: int in range(5):
		await get_tree().physics_frame


func _verify_edit(entry: Dictionary) -> void:
	var coordinates: Array = entry["position"]
	var cell: Vector3i = Vector3i(int(coordinates[0]), int(coordinates[1]), int(coordinates[2]))
	await _aim_at(cell)
	var expected: int = _catalog.get_voxel_id(StringName(entry["block"]))
	_check(_voxel_tool.get_voxel(cell) == expected, "Restored voxel differs at %s." % cell)
	for _index: int in range(15):
		await get_tree().physics_frame
	var collides: bool = _cell_has_collision(cell)
	_check(collides == _catalog.is_solid_voxel(expected), "Restored collision differs at %s." % cell)


func _cell_has_collision(cell: Vector3i) -> bool:
	var center: Vector3 = Vector3(cell) + Vector3.ONE * 0.5
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		center + Vector3.UP * 0.9, center + Vector3.UP * 0.1, 1
	)
	query.exclude = [_player.get_rid()]
	return not _player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _capture_frame(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = _output_directory.path_join(file_name)
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "Could not save rendered frame %s." % path)


func _read_report(phase: String) -> Dictionary:
	var path: String = _output_directory.path_join("run_%s.json" % phase)
	if not FileAccess.file_exists(path):
		_failures.append("Earlier rendered report is missing: %s." % path)
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary:
		_failures.append("Earlier rendered report is malformed.")
		return {}
	return value


func _write_report() -> void:
	var path: String = _output_directory.path_join("run_%s.json" % _phase)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write rendered report.")
		return
	file.store_string(JSON.stringify(_report, "\t", true, true) + "\n")
	file.flush()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
