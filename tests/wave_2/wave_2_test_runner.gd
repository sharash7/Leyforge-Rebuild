extends SceneTree

const TerrainGenerator = preload("res://src/lfe/worldgen/wave_1_terrain_generator.gd")

var _checks: int = 0
var _failures: Array[String] = []
var _root: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--wave2-test-root="):
			_root = argument.trim_prefix("--wave2-test-root=")
	if _root.is_empty() or not _root.is_absolute_path():
		push_error("Wave 2 test root must be an absolute disposable path.")
		quit(1)
		return
	var catalog: LfeBlockCatalog = LfeBlockCatalog.new()
	_check(catalog.load_default() == OK, "Default block catalog did not load.")
	if _failures.is_empty():
		_test_worlds(catalog)
		_test_bad_data(catalog)
	if _failures.is_empty():
		print("WAVE_2_TEST_PASS checks=%d" % _checks)
		quit(0)
	else:
		for failure: String in _failures:
			push_error("Wave 2 test: %s" % failure)
		print("WAVE_2_TEST_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _test_worlds(catalog: LfeBlockCatalog) -> void:
	var seed: int = 184552221
	var world_a: LfeWorldSave = LfeWorldSave.new()
	_check(world_a.open_world("alpha", seed, true, catalog, _root) == OK, "World alpha did not create.")
	_check(world_a.world_id == "alpha", "New world ID changed.")
	_check(world_a.seed == seed, "New world seed changed.")
	var generator: LfeWave1TerrainGenerator = TerrainGenerator.new()
	generator.configure(seed, catalog)
	var air: int = catalog.get_voxel_id(&"leyforge:air")
	var stone: int = catalog.get_voxel_id(&"leyforge:stone")
	var grass: int = catalog.get_voxel_id(&"leyforge:grass")
	var dirt: int = catalog.get_voxel_id(&"leyforge:dirt")
	var break_cells: Array[Vector3i] = [
		Vector3i(0, 0, 0), Vector3i(15, 0, 0), Vector3i(-17, 0, -1)
	]
	var place_cells: Array[Vector3i] = [
		Vector3i(16, 40, 0), Vector3i(-1, 40, 0)
	]
	for cell: Vector3i in break_cells:
		_check(generator.sample_voxel_id(cell) == stone, "Break test base is not Stone at %s." % cell)
		_check(world_a.record_voxel_edit(cell, air, stone) == OK, "Break did not record at %s." % cell)
	_check(world_a.record_voxel_edit(place_cells[0], grass, air) == OK, "Grass placement did not record.")
	_check(world_a.record_voxel_edit(place_cells[1], dirt, air) == OK, "Negative boundary placement did not record.")
	var collapse_cell: Vector3i = Vector3i(32, 0, 0)
	_check(world_a.record_voxel_edit(collapse_cell, air, stone) == OK, "Collapse break did not record.")
	_check(world_a.record_voxel_edit(collapse_cell, stone, stone) == OK, "Collapse restore did not record.")
	_check(world_a.overrides.canonical_id_at(collapse_cell).is_empty(), "Restored base state left an override.")
	_check(world_a.overrides.count() == 5, "Sparse override count is wrong.")
	_check(
		world_a.overrides.snapshot_for_block(Vector3i(16, 32, 0), Vector3i(16, 16, 16)).has(place_cells[0]),
		"Positive boundary override is absent from streamed block snapshot."
	)
	_check(
		world_a.overrides.snapshot_for_block(Vector3i(-16, 32, 0), Vector3i(16, 16, 16)).has(place_cells[1]),
		"Negative boundary override is absent from streamed block snapshot."
	)
	var state_a: Dictionary = {
		"position": [8.5, 19.05, 2.5],
		"yaw": 0.7,
		"pitch": -0.22,
		"selected_block": "leyforge:dirt",
	}
	_check(world_a.save(state_a) == OK, "World alpha save failed: %s" % world_a.get_last_error())
	var primary_a: String = world_a.get_primary_path()
	var save_text: String = FileAccess.get_file_as_string(primary_a)
	_check(save_text.length() < 12000, "Save contains more than sparse Wave 2 state.")
	_check(not save_text.contains("voxel_id"), "Save leaked transient numeric voxel IDs.")
	var envelope: Dictionary = JSON.parse_string(save_text)
	var payload: Dictionary = JSON.parse_string(String(envelope["payload_json"]))
	_check((payload["voxel_overrides"] as Array).size() == 5, "Save did not contain exactly five sparse edits.")
	_check(int((payload["metadata"] as Dictionary)["worldgen_version"]) == world_a.worldgen_version, "Worldgen identity was not saved.")
	var loaded_a: LfeWorldSave = LfeWorldSave.new()
	_check(loaded_a.open_world("alpha", 999, false, catalog, _root) == OK, "World alpha did not reload.")
	_check(loaded_a.seed == seed, "Saved seed did not win over default requested seed.")
	_check(loaded_a.player_state == state_a, "Player position or orientation did not survive.")
	for cell: Vector3i in break_cells:
		_check(loaded_a.overrides.voxel_id_at(cell, stone) == air, "Broken voxel did not survive at %s." % cell)
	_check(loaded_a.overrides.voxel_id_at(place_cells[0], air) == grass, "Grass placement did not survive.")
	_check(loaded_a.overrides.voxel_id_at(place_cells[1], air) == dirt, "Negative placement did not survive.")
	_check(loaded_a.overrides.voxel_id_at(Vector3i(24, 0, 0), stone) == stone, "Untouched terrain was not regenerated.")
	var conflict: LfeWorldSave = LfeWorldSave.new()
	_check(conflict.open_world("alpha", 999, true, catalog, _root) != OK, "Conflicting explicit seed was accepted.")
	_check(FileAccess.get_file_as_string(primary_a) == save_text, "Seed conflict mutated the authoritative save.")

	var world_b: LfeWorldSave = LfeWorldSave.new()
	_check(world_b.open_world("beta", seed, true, catalog, _root) == OK, "World beta did not create.")
	_check(world_b.record_voxel_edit(Vector3i(0, 0, 0), grass, stone) == OK, "World beta edit failed.")
	var state_b: Dictionary = {
		"position": [-6.5, 20.05, 3.5], "yaw": -0.4, "pitch": 0.1,
		"selected_block": "leyforge:grass",
	}
	_check(world_b.save(state_b) == OK, "World beta save failed.")
	var loaded_b: LfeWorldSave = LfeWorldSave.new()
	_check(loaded_b.open_world("beta", seed, true, catalog, _root) == OK, "World beta did not reload.")
	_check(loaded_b.overrides.voxel_id_at(Vector3i(0, 0, 0), stone) == grass, "World beta edit disappeared.")
	_check(loaded_b.overrides.voxel_id_at(Vector3i(15, 0, 0), stone) == stone, "World alpha edit bled into beta.")
	_check(loaded_b.player_state == state_b, "World beta player state is wrong.")
	_check(FileAccess.get_file_as_string(primary_a) == save_text, "World beta save modified alpha.")

	var remapped_catalog_path: String = _root.path_join("remapped_blocks.json")
	var catalog_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LfeBlockCatalog.DEFAULT_CATALOG_PATH))
	for block: Dictionary in catalog_data["blocks"]:
		if block["id"] == "leyforge:grass":
			block["voxel_id"] = 2
		elif block["id"] == "leyforge:dirt":
			block["voxel_id"] = 1
	_write_text(remapped_catalog_path, JSON.stringify(catalog_data))
	var remapped_catalog: LfeBlockCatalog = LfeBlockCatalog.new()
	_check(remapped_catalog.load_from_path(remapped_catalog_path) == OK, "Remapped canonical catalog did not load.")
	var remapped_world: LfeWorldSave = LfeWorldSave.new()
	_check(remapped_world.open_world("alpha", seed, true, remapped_catalog, _root) == OK, "Canonical remap did not reload.")
	_check(
		remapped_world.overrides.voxel_id_at(place_cells[0], air) == remapped_catalog.get_voxel_id(&"leyforge:grass"),
		"Saved Grass depended on its old numeric voxel ID."
	)


func _test_bad_data(catalog: LfeBlockCatalog) -> void:
	var seed: int = 42
	var state: Dictionary = {
		"position": [0.5, 10.05, 0.5], "yaw": 0.0, "pitch": 0.0,
		"selected_block": "leyforge:stone",
	}
	var invalid_id: LfeWorldSave = LfeWorldSave.new()
	_check(invalid_id.open_world("../escape", seed, true, catalog, _root) != OK, "Unsafe world ID was accepted.")
	var unsupported: LfeWorldSave = LfeWorldSave.new()
	_check(unsupported.open_world("unsupported", seed, true, catalog, _root) == OK, "Version test world did not create.")
	_check(unsupported.save(state) == OK, "Version test save failed.")
	var unsupported_path: String = unsupported.get_primary_path()
	var version_envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(unsupported_path))
	version_envelope["save_version"] = LfeWorldSave.SAVE_VERSION + 1
	_write_text(unsupported_path, JSON.stringify(version_envelope))
	var unsupported_load: LfeWorldSave = LfeWorldSave.new()
	_check(unsupported_load.open_world("unsupported", seed, true, catalog, _root) != OK, "Future save version loaded.")
	_check(unsupported_load.get_last_error().contains("Unsupported save version"), "Future version error was unclear.")

	var unknown: LfeWorldSave = LfeWorldSave.new()
	_check(unknown.open_world("unknown", seed, true, catalog, _root) == OK, "Unknown-ID test world did not create.")
	_check(unknown.record_voxel_edit(Vector3i(0, 0, 0), catalog.get_voxel_id(&"leyforge:air"), catalog.get_voxel_id(&"leyforge:stone")) == OK, "Unknown-ID edit failed.")
	_check(unknown.save(state) == OK, "Unknown-ID test save failed.")
	var unknown_path: String = unknown.get_primary_path()
	var unknown_envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(unknown_path))
	var unknown_payload: Dictionary = JSON.parse_string(String(unknown_envelope["payload_json"]))
	(unknown_payload["voxel_overrides"] as Array)[0]["block"] = "unknown:future"
	unknown_envelope["payload_json"] = JSON.stringify(unknown_payload)
	unknown_envelope["sha256"] = String(unknown_envelope["payload_json"]).sha256_text()
	_write_text(unknown_path, JSON.stringify(unknown_envelope))
	var unknown_load: LfeWorldSave = LfeWorldSave.new()
	_check(unknown_load.open_world("unknown", seed, true, catalog, _root) != OK, "Unknown canonical block loaded.")
	_check(unknown_load.get_last_error().contains("Unknown canonical block ID"), "Unknown block error was unclear.")

	var corrupt: LfeWorldSave = LfeWorldSave.new()
	_check(corrupt.open_world("corrupt", seed, true, catalog, _root) == OK, "Corruption test world did not create.")
	_check(corrupt.save(state) == OK, "Corruption test save failed.")
	var corrupt_path: String = corrupt.get_primary_path()
	var truncated: String = "{\"save_version\":1,\"payload_json\":"
	_write_text(corrupt_path, truncated)
	var corrupt_load: LfeWorldSave = LfeWorldSave.new()
	_check(corrupt_load.open_world("corrupt", seed, true, catalog, _root) != OK, "Truncated save loaded.")
	_check(FileAccess.get_file_as_string(corrupt_path) == truncated, "Loader overwrote malformed authoritative data.")
	_check(corrupt_load.save(state) != OK, "Failed load allowed a later save.")
	_check(corrupt.save(state) != OK, "Running world overwrote externally corrupted authoritative data.")
	_check(FileAccess.get_file_as_string(corrupt_path) == truncated, "Rejected save replaced the corrupted file.")

	var checksum_world: LfeWorldSave = LfeWorldSave.new()
	_check(checksum_world.open_world("checksum", seed, true, catalog, _root) == OK, "Checksum test world did not create.")
	_check(checksum_world.save(state) == OK, "Checksum test save failed.")
	var checksum_path: String = checksum_world.get_primary_path()
	var checksum_envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(checksum_path))
	checksum_envelope["sha256"] = "incorrect"
	_write_text(checksum_path, JSON.stringify(checksum_envelope))
	var checksum_load: LfeWorldSave = LfeWorldSave.new()
	_check(checksum_load.open_world("checksum", seed, true, catalog, _root) != OK, "Checksum mismatch loaded.")
	_check(checksum_load.get_last_error().contains("checksum mismatch"), "Checksum failure was unclear.")

	var generator_world: LfeWorldSave = LfeWorldSave.new()
	_check(generator_world.open_world("generator", seed, true, catalog, _root) == OK, "Generator test world did not create.")
	_check(generator_world.save(state) == OK, "Generator test save failed.")
	var generator_path: String = generator_world.get_primary_path()
	var generator_envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(generator_path))
	var generator_payload: Dictionary = JSON.parse_string(String(generator_envelope["payload_json"]))
	(generator_payload["metadata"] as Dictionary)["worldgen_version"] = 3
	generator_envelope["payload_json"] = JSON.stringify(generator_payload)
	generator_envelope["sha256"] = String(generator_envelope["payload_json"]).sha256_text()
	_write_text(generator_path, JSON.stringify(generator_envelope))
	var generator_load: LfeWorldSave = LfeWorldSave.new()
	_check(generator_load.open_world("generator", seed, true, catalog, _root) != OK, "Unsupported generator version loaded.")
	_check(generator_load.get_last_error().contains("Unsupported worldgen version"), "Generator incompatibility was unclear.")

	var maximum_seed_world: LfeWorldSave = LfeWorldSave.new()
	_check(maximum_seed_world.open_world("maximum_seed", 2147483647, true, catalog, _root) == OK, "Maximum supported seed did not create.")
	_check(maximum_seed_world.save(state) == OK, "Maximum supported seed did not save.")
	var maximum_seed_load: LfeWorldSave = LfeWorldSave.new()
	_check(maximum_seed_load.open_world("maximum_seed", 0, false, catalog, _root) == OK, "Maximum supported seed did not load.")
	_check(maximum_seed_load.seed == 2147483647, "Maximum supported seed changed on load.")

	var unsafe: LfeWorldSave = LfeWorldSave.new()
	_check(unsafe.open_world("unsafe", seed, true, catalog, _root) == OK, "Unsafe-position test world did not create.")
	var unsafe_state: Dictionary = state.duplicate(true)
	unsafe_state["position"] = [0.5, -10.0, 0.5]
	_check(unsafe.save(unsafe_state) == OK, "Unsafe-position test save failed.")

	var recover: LfeWorldSave = LfeWorldSave.new()
	_check(recover.open_world("recover", seed, true, catalog, _root) == OK, "Recovery test world did not create.")
	_check(recover.save(state) == OK, "Recovery test save failed.")
	var recover_path: String = recover.get_primary_path()
	var previous_path: String = recover.get_world_directory().path_join(LfeWorldSave.PREVIOUS_FILE)
	_check(DirAccess.rename_absolute(recover_path, previous_path) == OK, "Could not simulate interrupted promotion.")
	var recovered: LfeWorldSave = LfeWorldSave.new()
	_check(recovered.open_world("recover", seed, true, catalog, _root) == OK, "Valid previous copy did not recover.")
	_check(recovered.load_status.contains("Recovered"), "Recovery was not reported.")
	_check(recovered.save(state) == OK, "Recovered world could not save.")
	_check(FileAccess.file_exists(recover_path), "Recovered save was not promoted.")
	_write_text(recovered.get_world_directory().path_join(LfeWorldSave.PENDING_FILE), "incomplete temporary save")
	var healthy_load: LfeWorldSave = LfeWorldSave.new()
	_check(healthy_load.open_world("recover", seed, true, catalog, _root) == OK, "Incomplete pending file displaced a healthy authoritative save.")


func _write_text(path: String, value: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write disposable test file %s." % path)
		return
	file.store_string(value)
	file.flush()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
