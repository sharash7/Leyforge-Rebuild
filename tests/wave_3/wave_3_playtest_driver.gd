extends Node

const Rules = preload("res://src/lfe/worldgen/wave_1_terrain_rules.gd")
var _world: LeyforgeWave1Playground
var _player: LeyforgeFirstPersonPlayer
var _terrain: VoxelTerrain
var _catalog: LfeBlockCatalog
var _tool: VoxelTool
var _phase: String = ""
var _out: String = ""
var _checks: int = 0
var _failures: Array[String] = []
var _report: Dictionary = {}
var _edits: Array = []


func configure(world: LeyforgeWave1Playground, player: LeyforgeFirstPersonPlayer,
		terrain: VoxelTerrain, catalog: LfeBlockCatalog, _seed: int) -> void:
	_world = world; _player = player; _terrain = terrain; _catalog = catalog
	_tool = terrain.get_voxel_tool()
	_tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--wave3-run="):
			_phase = argument.trim_prefix("--wave3-run=")
		if argument.begins_with("--wave3-playtest-out="):
			_out = argument.trim_prefix("--wave3-playtest-out=")
	call_deferred("_run")


func _run() -> void:
	if not _world.is_runtime_ready():
		await _world.runtime_ready
	await _frames(12)
	_player.set_runtime_ready(false)
	_check(DisplayServer.get_name() != "headless", "Acceptance uses a real display")
	match _phase:
		"A": await _run_a()
		"B": await _run_b()
		"C": await _run_c()
		"M": await _migration()
		"N": await _migration_restart()
		_: _check(false, "Unknown rendered phase")
	_report.merge({"phase": _phase, "checks": _checks, "passed": _failures.is_empty(), "failures": _failures,
		"runner": Engine.get_version_info().get("string"), "world_id": _world.world_save.world_id, "seed": _world.active_seed})
	_write_report()
	for failure: String in _failures:
		push_error("Wave 3 rendered %s: %s" % [_phase, failure])
	print("WAVE_3_RENDERED_%s_%s checks=%d" % [_phase, "PASS" if _failures.is_empty() else "FAIL", _checks])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _run_a() -> void:
	var r: LfeResourceState = _world.resources
	_check(r.inventory.total(&"leyforge:grass") == 0 and r.drops().is_empty(), "New world starts without resources")
	var initial_position: Vector3 = _player.global_position
	_player.set_runtime_ready(true)
	Input.action_press("move_forward")
	await _frames(40)
	Input.action_release("move_forward")
	await _frames(10)
	_check(_player.global_position.distance_to(initial_position) > 1.0, "Existing movement works with inventory")
	_player.set_runtime_ready(false)
	var source: Vector3i = _surface(4, 2)
	await _aim(source)
	var block: StringName = _catalog.canonical_id_for_voxel_id(_tool.get_voxel(source))
	var before: int = r.total(block)
	_check(await _harvest_target(), "Player targeting breaks voxel")
	_check(r.total(block) == before + 1 and r.inventory.total(block) == 0, "Break creates only a physical conserved drop")
	_edits.append(_edit(source, &"leyforge:air"))
	await _frames(8)
	await _capture("01_physical_drop.png")
	var drop_id: String = r.drops()[0]["instance"]
	# Prove the actual proximity detector collects, then the same ID rejects.
	_player.global_position = Vector3(source) + Vector3(0.5, 0.9, 0.5)
	_player.set_runtime_ready(true)
	await _frames(90)
	_player.set_runtime_ready(false)
	_check(r.drop(drop_id).is_empty() and r.inventory.total(block) == 1, "Physical proximity pickup reaches inventory")
	_check(r.pickup(drop_id) == 0, "Second pickup path cannot duplicate")
	for x: int in [5, 6, 7, 8]:
		var cell: Vector3i = _surface(x, 2)
		await _aim(cell)
		_check(await _harvest_target(), "Harvest another voxel")
		_edits.append(_edit(cell, &"leyforge:air"))
		var entry: Dictionary = r.drops().back()
		_check(r.pickup(entry["instance"]) == 1, "Harvest drop collected exactly")
	var slot: int = _find_slot(r.inventory, block)
	_check(slot >= 0 and r.inventory.total(block) >= 2, "Known resource stack available")
	var initial: int = r.total(block)
	var panel: LeyforgeInventoryPanel = _world.inventory_panel
	panel.open()
	panel._click_slot(r.inventory, slot, false, false)
	panel._click_slot(r.inventory, 9, false, false)
	_check(r.inventory.stack_at(slot).is_empty() and r.inventory.total(block) == initial, "UI moves stack to backpack")
	panel._click_slot(r.inventory, 9, false, false)
	panel._click_slot(r.inventory, slot, false, false)
	panel._click_slot(r.inventory, slot, false, false)
	panel._click_slot(r.inventory, 9, true, false)
	_check(not r.inventory.stack_at(9).is_empty() and r.inventory.total(block) == initial, "UI right-click split conserves")
	panel._click_slot(r.inventory, 9, false, false)
	panel._click_slot(r.inventory, slot, false, false)
	_check(r.inventory.stack_at(9).is_empty() and r.inventory.total(block) == initial, "UI merges split quantity")
	panel.close()
	_check(LfeItemTransactions.transfer(r.inventory, slot, r.inventory, 1, 8) == 1, "Split harvested stack to hotbar nine")
	r.select(8)
	_world.inventory_panel.open()
	await _frames(2)
	await _capture("02_inventory_hotbar.png")
	_world.close_inventory()
	var ground: Vector3i = _surface(10, 2)
	await _aim(ground)
	var place: Vector3i = ground + Vector3i.UP
	_check(_player.try_place_target(), "Player inventory-backed placement")
	_check(r.inventory.stack_at(8).is_empty() and _tool.get_voxel(place) == _catalog.get_voxel_id(block), "Final hotbar unit places and empties slot")
	_edits.append(_edit(place, block))
	_check(r.total(block) + 1 == initial, "Placement consumes exactly one")
	_check(not _world.place_cell(place), "Empty selected slot cannot place")
	await _capture("03_placement_consumed.png")
	# Actual failure targets: occupied, body overlap, streaming/range invalid.
	slot = _find_slot(r.inventory, block)
	r.select(slot)
	var before_failure: Dictionary = r.snapshot()
	_check(not _world.place_cell(ground) and r.snapshot() == before_failure, "Occupied target consumes zero")
	var overlap: Vector3i = place + Vector3i.UP
	_player.global_position = Vector3(overlap) + Vector3(0.5, 0.0, 0.5)
	await _aim(place)
	_check(not _world.place_cell(overlap) and r.snapshot() == before_failure, "Body collision consumes zero")
	_check(not _world.place_cell(Vector3i(900, 90, -900)) and r.snapshot() == before_failure, "Unloaded/range target consumes zero")
	# Break the newly placed voxel: inventory->world->drop->inventory exact.
	await _aim(place)
	_check(await _harvest_target(), "Break newly placed voxel")
	var returned: Dictionary = r.drops().back()
	_check(r.pickup(returned["instance"]) == 1 and r.total(block) == initial, "Rendered break-after-place conservation")
	_edits.pop_back() # Placement collapsed back to its deterministic Air base.
	# Leave a fresh inventory-backed voxel at a negative chunk boundary.
	slot = _find_slot(r.inventory, block)
	r.select(slot)
	var boundary_ground: Vector3i = _surface(-17, 16)
	await _aim(boundary_ground)
	_player.global_position = initial_position
	_check(_player.try_place_target(), "Negative chunk-boundary placement")
	_edits.append(_edit(boundary_ground + Vector3i.UP, block))
	_check(r.total(block) + 1 == initial, "Boundary conversion exact")
	# Storage is a fixed origin crate. Use its real proximity UI.
	var crate: Dictionary = r.snapshot()["storage"][0]
	_restore_camera(initial_position)
	_check(_world.open_nearby_storage(), "Storage interaction opens near crate")
	var storage: LfeInventory = r.storage_inventory(crate["instance"])
	slot = _find_slot(r.inventory, block)
	panel._click_slot(r.inventory, slot, false, true)
	_check(r.inventory.total(block) == 0 and storage.total(block) + 1 == initial, "UI shift-click storage transfer")
	panel._click_slot(storage, 0, false, true)
	_check(storage.total(block) == 0 and r.inventory.total(block) + 1 == initial, "UI shift-click return")
	slot = _find_slot(r.inventory, block)
	_check(LfeItemTransactions.transfer(r.inventory, slot, storage, 1) == 1, "Transfer into world storage")
	_check(LfeItemTransactions.transfer(storage, 0, r.inventory, 1) == 1, "Transfer back to inventory")
	slot = _find_slot(r.inventory, block)
	_check(LfeItemTransactions.transfer(r.inventory, slot, storage, 1) == 1, "Retain persistent storage resource")
	await _frames(3)
	await _capture("04_storage.png")
	_world.close_inventory()
	# Retain one drop and nondefault hotbar/equipment state.
	slot = _find_slot(r.inventory, block)
	r.select(slot)
	_check(_world.drop_selected(), "Player-created physical world drop")
	_check(not r.drops().is_empty(), "Drop remains physically represented")
	_check(_catalog.has_content(&"test:hand_token"), "Equipment uses isolated test definition")
	_check(LfeItemTransactions.add(r.inventory, &"test:hand_token", 1) == 1, "Test equipment fixture acquired")
	var item_slot: int = _find_slot(r.inventory, &"test:hand_token")
	slot = _find_slot(r.inventory, block)
	panel.open()
	panel._click_slot(r.inventory, slot, false, false)
	panel._click_slot(r.inventory, item_slot, false, false)
	_check(r.inventory.stack_at(slot)["content"] == "test:hand_token" and r.inventory.stack_at(item_slot)["content"] == String(block), "UI swaps unlike stacks")
	panel.close()
	item_slot = _find_slot(r.inventory, &"test:hand_token")
	_check(LfeItemTransactions.transfer(r.inventory, item_slot, r.equipment, 1, 0) == 1, "Equipment transfer through transaction runtime")
	var number: InputEventKey = InputEventKey.new()
	number.keycode = KEY_8
	number.pressed = true
	_player._unhandled_input(number)
	_check(r.selected_slot() == 7, "Number key selects hotbar")
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	_player._unhandled_input(wheel)
	_check(r.selected_slot() == 8, "Mouse wheel cycles hotbar")
	_player._unhandled_input(number)
	_check(await _stream(_edits), "New edits and resource instances survive stream out/return")
	_restore_camera(initial_position)
	_player.rotation.y = 0.6
	var state: Dictionary = _player.get_persistent_state()
	state["pitch"] = -0.2
	_player.restore_persistent_state(state)
	_player.set_runtime_ready(true)
	await _frames(8)
	_player.set_runtime_ready(false)
	_check(_player.is_on_floor(), "Player safely supported before save")
	_check(_world.request_save(), "Explicit save persists integrated Wave 3")
	_check(not r.drops().is_empty(), "Saved acceptance retains a physical world drop")
	_report["saved_resources"] = r.snapshot()
	_report["saved_player"] = _world.world_save.player_state
	_report["edits"] = _edits
	_report["block"] = String(block)
	_report["conserved_total"] = r.total(block) + 1
	_report["streamed_out_and_back"] = true
	await _capture("05_saved_world.png")


func _run_b() -> void:
	var a: Dictionary = _read_report("A")
	var r: LfeResourceState = _world.resources
	var expected: LfeResourceState = LfeResourceState.new(_catalog)
	_check(expected.restore(a["saved_resources"]), "Prior rendered resource report valid")
	_check(r.snapshot() == expected.snapshot(), "Exact inventory/hotbar/equipment/storage/drop identities restore")
	_check(_world.world_save.player_state == a["saved_player"], "Exact player persistent state restore")
	var coordinates: Array = a["saved_player"]["position"]
	_check(_player.global_position.distance_to(Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))) < 0.2, "Safe player position restore")
	_world.inventory_panel.open(true)
	await _frames(3)
	await _capture("06_restarted_inventory.png")
	_world.close_inventory()
	_check(await _stream(a["edits"]), "Restored edits/drops/storage survive confirmed streaming")
	await _capture("07_streamed_back.png")
	# Continue operating all restored state, including equipment and storage.
	_check(not r.drops().is_empty(), "Restart retained an uncollected physical drop")
	if r.drops().is_empty():
		return
	var restored_drop: Dictionary = r.drops()[0]
	var quantity: int = int(restored_drop["stack"]["quantity"])
	var total: int = r.total(StringName(a["block"]))
	_check(r.pickup(restored_drop["instance"]) == quantity, "Restored physical drop can be collected")
	_check(r.pickup(restored_drop["instance"]) == 0, "Restored instance cannot be collected twice")
	var storage: LfeInventory = r.storage_inventory(r.snapshot()["storage"][0]["instance"])
	_check(LfeItemTransactions.transfer(storage, 0, r.inventory, 1) == 1, "Restored storage transferable")
	_check(LfeItemTransactions.transfer(r.equipment, 0, r.inventory, 1) == 1, "Restored equipment removable")
	_check(r.total(StringName(a["block"])) == total, "Restored manipulation conserves quantities")
	_check(_world.request_save(), "Restored state can save again")
	_report["streamed_out_and_back"] = true
	_report["resources_restored"] = true


func _run_c() -> void:
	var a: Dictionary = _read_report("A")
	var r: LfeResourceState = _world.resources
	_check(_world.active_seed == int(a["seed"]) and _world.world_save.world_id != a["world_id"], "Same seed, independent world ID")
	_check(_world.world_save.player_state.is_empty() and _world.world_save.overrides.count() == 0, "Player and overrides isolated")
	_check(r.inventory.snapshot().all(func(value: Variant) -> bool: return value == null), "Inventory isolated")
	_check(r.equipment.snapshot() == [null, null] and r.selected_slot() == 0 and r.drops().is_empty(), "Equipment/hotbar/drops isolated")
	var storage: Dictionary = r.snapshot()["storage"][0]
	_check(storage["slots"].all(func(value: Variant) -> bool: return value == null), "Storage isolated")
	_check(storage["instance"] != a["saved_resources"]["storage"][0]["instance"], "Storage instance identity world-isolated")
	for edit: Dictionary in a["edits"]:
		var cell: Vector3i = _cell(edit["position"])
		await _aim(cell)
		var generated: int = (_terrain.generator as LfeWave1TerrainGenerator).sample_voxel_id(cell)
		_check(_tool.get_voxel(cell) == generated, "Same-seed deterministic generated terrain without inherited edit")
	await _capture("08_isolated_world.png")
	_report["same_seed_isolation"] = true


func _migration() -> void:
	var r: LfeResourceState = _world.resources
	_check(_world.world_save.load_status.contains("migrated v1"), "Actual runtime loads v1 through migration")
	_check(_world.world_save.overrides.canonical_id_at(Vector3i(-16, 0, 0)) == "leyforge:air", "v1 negative override preserved")
	_check(r.inventory.snapshot().all(func(value: Variant) -> bool: return value == null) and r.drops().is_empty() and r.equipment.snapshot() == [null, null] and r.selected_slot() == 0, "Migration safe inventory/equipment/drop/hotbar defaults")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_world.world_save.get_primary_path()))
	_check(int(raw["save_version"]) == 1, "Opening migration fixture did not rewrite authority")
	var original: String = FileAccess.get_file_as_string(_world.world_save.get_primary_path())
	var saved: Dictionary = _world.world_save.player_state
	_check(_player.get_persistent_state()["selected_block"] == saved["selected_block"], "Legacy v1 player selection preserved")
	_check(absf(_player.rotation.y - float(saved["yaw"])) < 0.001, "Migration player orientation restored")
	_check(_world.request_save(), "Runtime explicit save writes v2")
	raw = JSON.parse_string(FileAccess.get_file_as_string(_world.world_save.get_primary_path()))
	_check(int(raw["save_version"]) == LfeWorldSave.SAVE_VERSION, "Migrated runtime format now v2")
	_check(FileAccess.get_file_as_string(_world.world_save.get_world_directory().path_join(LfeWorldSave.PREVIOUS_FILE)) == original, "Original v1 retained by atomic lifecycle")
	_report["saved_resources"] = r.snapshot()
	_report["saved_player"] = _world.world_save.player_state
	_world.inventory_panel.open()
	await _frames(2)
	await _capture("09_migrated_v1.png")


func _migration_restart() -> void:
	var m: Dictionary = _read_report("M")
	var expected: LfeResourceState = LfeResourceState.new(_catalog)
	expected.restore(m["saved_resources"])
	_check(_world.resources.snapshot() == expected.snapshot(), "Migrated v2 resource defaults restore in fresh process")
	_check(_world.world_save.player_state == m["saved_player"], "Migrated Wave 2 player exact on restart")
	_check(_world.world_save.overrides.canonical_id_at(Vector3i(-16, 0, 0)) == "leyforge:air", "Migrated voxel exact on restart")
	_check(not _world.world_save.load_status.contains("migrated v1"), "Restart loads v2 without repeated migration")
	await _capture("10_migrated_restart.png")


func _stream(edits: Array) -> bool:
	var resources_before: Dictionary = _world.resources.snapshot()
	var first: Vector3i = _cell(edits[0]["position"])
	var camera: Camera3D = _player.get_camera()
	camera.top_level = true
	camera.global_position = Vector3(340, 45, 340)
	var unloaded: bool = false
	for index: int in 360:
		await get_tree().physics_frame
		if not _tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(first)):
			unloaded = true
			break
	_check(unloaded, "Source terrain really streams out")
	_check(_world.resources.snapshot() == resources_before, "Resources unchanged while chunks absent")
	for edit: Dictionary in edits:
		var cell: Vector3i = _cell(edit["position"])
		await _aim(cell)
		_check(_tool.get_voxel(cell) == _catalog.get_voxel_id(StringName(edit["block"])), "Streamed voxel edit exact")
		await _frames(15)
		var center: Vector3 = Vector3(cell) + Vector3.ONE * 0.5
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(center + Vector3.UP * 0.9, center + Vector3.UP * 0.1, 1)
		query.exclude = [_player.get_rid()]
		var collision: bool = not _player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		_check(collision == _catalog.is_solid_voxel(_tool.get_voxel(cell)), "Streamed voxel collision exact")
	_check(_world.resources.snapshot() == resources_before, "Return preserves all resource identities/quantities")
	_world.resource_presenter.sync()
	_check(_world.resource_presenter._nodes.size() == _world.resources.drops().size(), "One visible node per persistent drop after return")
	return unloaded


func _aim(cell: Vector3i) -> void:
	var camera: Camera3D = _player.get_camera()
	camera.top_level = true
	var center: Vector3 = Vector3(cell) + Vector3.ONE * 0.5
	camera.global_position = center + Vector3(0.25, 3, 0.25)
	camera.look_at(center, Vector3.UP)
	var loaded: bool = false
	for index: int in 360:
		await get_tree().physics_frame
		if _tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(cell)):
			loaded = true
			break
	_check(loaded, "Interaction cell streams in")
	await _frames(8)


func _restore_camera(position: Vector3) -> void:
	var camera: Camera3D = _player.get_camera()
	camera.top_level = false
	camera.position = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	_player.global_position = position


func _surface(x: int, z: int) -> Vector3i:
	return Vector3i(x, Rules.height_at(_world.active_seed, x, z), z)


func _cell(values: Array) -> Vector3i:
	return Vector3i(int(values[0]), int(values[1]), int(values[2]))


func _edit(cell: Vector3i, block: StringName) -> Dictionary:
	return {"position": [cell.x, cell.y, cell.z], "block": String(block)}


func _find_slot(inventory: LfeInventory, id: StringName) -> int:
	for slot: int in inventory.capacity():
		if inventory.stack_at(slot).get("content") == String(id):
			return slot
	return -1


func _frames(count: int) -> void:
	for index: int in count:
		await get_tree().physics_frame


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(_out.path_join(name)) == OK, "Rendered evidence frame " + name)


func _read_report(phase: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_out.path_join("run_%s.json" % phase)))


func _write_report() -> void:
	var file: FileAccess = FileAccess.open(_out.path_join("run_%s.json" % _phase), FileAccess.WRITE)
	if file == null:
		_check(false, "Cannot write rendered report")
		return
	file.store_string(JSON.stringify(_report, "	", true, true) + "
")
	file.flush()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _harvest_target() -> bool:
	if not _player.try_break_target():
		return false
	for frame: int in 180:
		await get_tree().physics_frame
		if _world._harvest.is_empty():
			return _player._voxel_tool.get_voxel(_player.get_target_cell()) == _catalog.get_voxel_id(&"leyforge:air")
	return false
