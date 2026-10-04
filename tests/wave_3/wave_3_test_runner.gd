extends SceneTree

const Rules = preload("res://src/lfe/worldgen/wave_1_terrain_rules.gd")
var _checks: int = 0
var _failures: Array[String] = []
var _root: String = ""
var _output: String = ""
var _catalog: LfeBlockCatalog


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--wave3-test-root="):
			_root = argument.trim_prefix("--wave3-test-root=")
		if argument.begins_with("--wave3-test-out="):
			_output = argument.trim_prefix("--wave3-test-out=")
	if _root.is_empty() or not _root.is_absolute_path():
		quit(1)
		return
	_catalog = LfeBlockCatalog.new()
	_check(_catalog.load_default() == OK, "Canonical production catalog loads")
	_content()
	_transactions()
	_resources()
	_persistence()
	var report: Dictionary = {"passed": _failures.is_empty(), "checks": _checks, "failures": _failures,
		"runner": Engine.get_version_info().get("string"), "conservation": _failures.is_empty()}
	if not _output.is_empty():
		_write(_output.path_join("focused.json"), JSON.stringify(report, "	"))
	for failure: String in _failures:
		push_error("Wave 3: " + failure)
	print("WAVE_3_TEST_%s checks=%d failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _content() -> void:
	for id: StringName in _catalog.development_placeable_ids():
		_check(_catalog.is_inventory_content(id), "Block inventory projection " + String(id))
		_check(_catalog.content_definition(id) == _catalog.definition_for_id(id), "Single block definition " + String(id))
		_check(_catalog.placeable_voxel(id) == _catalog.get_voxel_id(id), "Canonical block placement " + String(id))
		_check(LfeItemStack.valid(LfeItemStack.make(id, 64), _catalog, false), "Bounded block stack " + String(id))
	_check(not _catalog.is_inventory_content(&"leyforge:air"), "Air is not inventory content")
	for value: Variant in [null, {}, {"content": "unknown:x", "quantity": 1},
			{"content": "leyforge:stone", "quantity": 0}, {"content": "leyforge:stone", "quantity": -1},
			{"content": "leyforge:stone", "quantity": 65}, {"content": "leyforge:stone", "quantity": 1.5},
			{"content": 3, "quantity": 1}, {"content": "leyforge:stone", "quantity": "1"}]:
		_check(not LfeItemStack.valid(value, _catalog, false), "Invalid stack rejected: %s" % str(value))
	_check(LfeItemStack.valid(null, _catalog), "Empty slot represented by null")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LfeBlockCatalog.DEFAULT_CATALOG_PATH))
	fixture["items"].append({"id": "test:hand_token", "display_name": "Equipment fixture", "kind": "item",
		"inventory_capable": true, "stack_limit": 1, "placeable": false, "equipment_slots": ["hand"]})
	_write(_root.path_join("test_content.json"), JSON.stringify(fixture))
	var test_catalog: LfeBlockCatalog = LfeBlockCatalog.new()
	_check(test_catalog.load_from_path(_root.path_join("test_content.json")) == OK, "Isolated standalone item loads")
	_check(test_catalog.has_content(&"test:hand_token") and not test_catalog.has_id(&"test:hand_token"), "Item-only identity has no voxel")
	_check(test_catalog.placeable_voxel(&"test:hand_token") == -1, "Non-placeable item rejects placement")
	var state: LfeResourceState = LfeResourceState.new(test_catalog)
	_check(LfeItemTransactions.add(state.inventory, &"test:hand_token", 1) == 1, "Fixture item added")
	_check(LfeItemTransactions.transfer(state.inventory, 0, state.equipment, 1, 0) == 1, "Compatible equipment transfer")
	_check(LfeItemTransactions.transfer(state.equipment, 0, state.equipment, 1, 1) == 0, "Incompatible equipment rejected")
	var restored: LfeResourceState = LfeResourceState.new(test_catalog)
	_check(restored.restore(state.snapshot()) and restored.equipment.total(&"test:hand_token") == 1, "Equipment roundtrip")
	var empty_world: Callable = func() -> Error: return OK
	LfeItemTransactions.transfer(state.equipment, 0, state.inventory, 1)
	_check(not state.place_from_inventory(0, empty_world), "Standalone item cannot place")
	# Permute numeric mappings while durable stack identity remains unchanged.
	var blocks: Array = fixture["blocks"]
	var old: int = int(blocks[1]["voxel_id"])
	blocks[1]["voxel_id"] = blocks[2]["voxel_id"]
	blocks[2]["voxel_id"] = old
	_write(_root.path_join("remapped.json"), JSON.stringify(fixture))
	var remapped: LfeBlockCatalog = LfeBlockCatalog.new()
	_check(remapped.load_from_path(_root.path_join("remapped.json")) == OK, "Remapped catalog loads")
	_check(LfeItemStack.valid(LfeItemStack.make(&"leyforge:grass", 4), remapped), "Stack ignores transient mapping")
	fixture["items"].append(fixture["blocks"][1])
	_write(_root.path_join("invalid_content.json"), JSON.stringify(fixture))
	_check(test_catalog.load_from_path(_root.path_join("invalid_content.json")) != OK, "Duplicate/malformed item content rejected")


func _transactions() -> void:
	var a: LfeInventory = LfeInventory.new(_catalog, 3)
	var b: LfeInventory = LfeInventory.new(_catalog, 1)
	_check(a.snapshot() == [null, null, null], "New inventory empty")
	_check(LfeItemTransactions.add(a, &"leyforge:stone", 70) == 70, "Add distributes bounded stacks")
	_check(a.snapshot() == [LfeItemStack.make(&"leyforge:stone", 64), LfeItemStack.make(&"leyforge:stone", 6), null], "Add exact layout")
	var before: Array = a.snapshot()
	_check(LfeItemTransactions.add(a, &"leyforge:stone", 1000) == 0 and a.snapshot() == before, "Full add rollback")
	_check(LfeItemTransactions.transfer(a, 0, a, 4, 2) == 4, "Split to empty slot")
	_check(LfeItemTransactions.transfer(a, 2, a, 4, 1) == 4, "Merge same content")
	_check(a.total(&"leyforge:stone") == 70, "Split/merge conserve")
	_check(LfeItemTransactions.transfer(a, 0, b, 60) == 60, "Move into storage")
	var before_a: Array = a.snapshot()
	var before_b: Array = b.snapshot()
	_check(LfeItemTransactions.transfer(a, 1, b, 10) == 0 and a.snapshot() == before_a and b.snapshot() == before_b, "Full transfer exact rollback")
	_check(LfeItemTransactions.transfer(a, 1, b, 10, -1, true) == 4, "Partial destination exact acceptance")
	_check(a.total(&"leyforge:stone") + b.total(&"leyforge:stone") == 70, "Partial conservation")
	_check(LfeItemTransactions.transfer(a, 1, b, 6, -1, true) == 0, "Full destination rejects")
	_check(LfeItemTransactions.remove(a, 1, 7) == false, "Over-removal rejects")
	_check(LfeItemTransactions.add(a, &"leyforge:dirt", 5) == 5, "Different content added")
	_check(LfeItemTransactions.swap(a, 0, a, 1), "Unlike stacks swap")
	_check(a.stack_at(0)["content"] == "leyforge:stone" and a.stack_at(1)["content"] == "leyforge:dirt", "Swap layout")
	_check(LfeItemTransactions.transfer(a, 0, a, 6, 2) == 6 and a.stack_at(0).is_empty(), "Move empties source")
	_check(LfeItemTransactions.remove(a, 2, 6) and a.stack_at(2).is_empty(), "Final quantity empties slot")
	var leaked: Array = b.snapshot()
	leaked[0]["quantity"] = 1
	_check(b.total(&"leyforge:stone") == 64, "Snapshots cannot mutate authority")
	for values: Variant in [[null], [null, null, "bad"], [null, null, {"content":"leyforge:stone", "quantity":-1}]]:
		var original: Array = a.snapshot()
		_check(not a.restore(values) and a.snapshot() == original, "Malformed inventory restore rollback")


func _resources() -> void:
	var r: LfeResourceState = LfeResourceState.new(_catalog)
	_check(r.inventory.capacity() == 27 and r.selected_slot() == 0, "Backpack/hotbar defaults")
	_check(r.select(8) and not r.select(9) and r.selected_slot() == 8, "Hotbar selection bounded")
	_check(not r.place_from_inventory(8, func() -> Error: return OK), "Empty hotbar cannot place")
	_check(LfeItemTransactions.add(r.inventory, &"leyforge:stone", 25) == 25, "Known conserved matter created for test")
	var id: String = r.drop_from_inventory(0, 10, Vector3(16.5, 20, -16.5))
	_check(not id.is_empty() and r.inventory.total(&"leyforge:stone") == 15, "Player drop conversion")
	_check(r.pickup(id) == 10 and r.pickup(id) == 0, "Drop collected once across repeated paths")
	var crate: String = r.ensure_crate(Vector3(2.5, 10, 0.5))
	var storage: LfeInventory = r.storage_inventory(crate)
	_check(storage != null and storage.capacity() == 9, "Persistent storage identity/capacity")
	_check(LfeItemTransactions.transfer(r.inventory, 0, storage, 12) == 12, "Inventory to storage")
	_check(LfeItemTransactions.transfer(storage, 0, r.inventory, 12) == 12, "Storage to inventory")
	var voxels: Dictionary = {"placed": 0}
	_check(r.place_from_inventory(0, func() -> Error: voxels["placed"] += 1; return OK), "Inventory-to-voxel conversion")
	_check(r.inventory.total(&"leyforge:stone") == 24 and r.total(&"leyforge:stone") + int(voxels["placed"]) == 25, "Placement consumes exactly one")
	var before: Dictionary = r.snapshot()
	_check(not r.place_from_inventory(0, func() -> Error: return ERR_INVALID_DATA) and r.snapshot() == before, "Failed placement consumes zero")
	_check(not r.break_to_drop(&"leyforge:stone", Vector3.ZERO, func() -> Error: return ERR_INVALID_DATA) and r.snapshot() == before, "Failed break creates no resource")
	_check(r.break_to_drop(&"leyforge:stone", Vector3.ZERO, func() -> Error: voxels["placed"] -= 1; return OK), "Voxel-to-drop conversion")
	id = r.drops()[0]["instance"]
	_check(r.pickup(id) == 1 and r.total(&"leyforge:stone") == 25 and voxels["placed"] == 0, "Complete material roundtrip exact")
	# Drive repeated randomized movements through the actual runtime and assert
	# conservation at every step, including full inventories and rejected targets.
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 74193
	for index: int in 300:
		match random.randi_range(0, 4):
			0:
				var slot: int = random.randi_range(0, 26)
				var stack: Dictionary = r.inventory.stack_at(slot)
				if not stack.is_empty():
					r.drop_from_inventory(slot, 1, Vector3(index, 20, -index))
			1:
				if not r.drops().is_empty():
					r.pickup(r.drops()[0]["instance"])
			2:
				LfeItemTransactions.transfer(r.inventory, random.randi_range(0, 26), storage, 1, -1, true)
			3:
				LfeItemTransactions.transfer(storage, random.randi_range(0, 8), r.inventory, 1, -1, true)
			4:
				LfeItemTransactions.transfer(r.inventory, random.randi_range(0, 26), r.inventory, 1, random.randi_range(0, 26), true)
		_check(r.total(&"leyforge:stone") == 25, "Conservation randomized step %d" % index)
	# Capacity/partial/repeated pickup: 1728 total player capacity, exact overflow.
	var full: LfeResourceState = LfeResourceState.new(_catalog)
	LfeItemTransactions.add(full.inventory, &"leyforge:stone", 1728)
	id = full.drop_from_inventory(0, 10, Vector3.ZERO)
	LfeItemTransactions.add(full.inventory, &"leyforge:stone", 6)
	_check(full.pickup(id) == 4 and int(full.drop(id)["stack"]["quantity"]) == 6, "Partial pickup leaves exact physical remainder")
	before = full.snapshot()
	_check(full.pickup(id) == 0 and full.snapshot() == before, "Full pickup leaves entire remainder")
	LfeItemTransactions.remove(full.inventory, 0, 6)
	_check(full.pickup(id) == 6 and full.pickup(id) == 0, "Repeated partial pickup exact")
	var first: String = full.drop_from_inventory(0, 1, Vector3.ZERO)
	var second: String = full.drop_from_inventory(0, 1, Vector3.ZERO)
	_check(first != second and full.drops().size() == 2, "Identical drops have stable distinct identity")
	var loaded: LfeResourceState = LfeResourceState.new(_catalog)
	_check(loaded.restore(full.snapshot()) and loaded.snapshot() == full.snapshot(), "Drop and remainder persistence")
	_check(loaded.total(&"leyforge:stone") == full.total(&"leyforge:stone"), "Persistence conserves")
	var mutations: Array = []
	before = full.snapshot()
	var bad: Dictionary = before.duplicate(true)
	bad["drops"][1]["instance"] = bad["drops"][0]["instance"]
	mutations.append(bad)
	bad = before.duplicate(true); bad["drops"][0]["stack"]["content"] = "unknown:item"; mutations.append(bad)
	bad = before.duplicate(true); bad["hotbar_selected"] = 9; mutations.append(bad)
	bad = before.duplicate(true); bad["drops"][0]["position"][0] = "bad"; mutations.append(bad)
	bad = before.duplicate(true); bad["equipment"][0] = LfeItemStack.make(&"leyforge:stone", 1); mutations.append(bad)
	for mutation: Dictionary in mutations:
		_check(not full.restore(mutation) and full.snapshot() == before, "Malformed resources fail without mutation")
	# Storage rejection, partial transfer and swap use the same production seam.
	var full_storage: LfeInventory = r.storage_inventory(crate)
	LfeItemTransactions.add(full_storage, &"leyforge:dirt", 576)
	LfeItemTransactions.add(r.inventory, &"leyforge:dirt", 10)
	var dirt_slot: int = -1
	for slot: int in 27:
		if r.inventory.stack_at(slot).get("content") == "leyforge:dirt":
			dirt_slot = slot
			break
	before = r.snapshot()
	_check(LfeItemTransactions.transfer(r.inventory, dirt_slot, full_storage, 10) == 0 and r.snapshot() == before, "Full storage exact rollback")
	LfeItemTransactions.remove(full_storage, 0, 3)
	_check(LfeItemTransactions.transfer(r.inventory, dirt_slot, full_storage, 10, -1, true) == 3, "Partial storage accepts exactly three")


func _persistence() -> void:
	var seed: int = 184552221
	var position: Array = [0.5, float(Rules.height_at(seed, 0, 0)) + 1.05, 0.5]
	var player: Dictionary = {"position": position, "yaw": 0.7, "pitch": -0.2, "selected_block": "leyforge:stone"}
	var r: LfeResourceState = LfeResourceState.new(_catalog)
	LfeItemTransactions.add(r.inventory, &"leyforge:dirt", 14)
	var crate: String = r.ensure_crate(Vector3(2.5, float(position[1]) - 0.6, 0.5))
	LfeItemTransactions.transfer(r.inventory, 0, r.storage_inventory(crate), 4)
	r.drop_from_inventory(0, 3, Vector3(16, 35, -16))
	r.select(5)
	var world: LfeWorldSave = LfeWorldSave.new()
	_check(world.open_world("resources", seed, true, _catalog, _root) == OK, "v2 world creates")
	_check(world.record_voxel_edit(Vector3i(-16, 0, 0), 0, 3) == OK, "Negative boundary override")
	_check(world.save(player, r.snapshot()) == OK, "v2 all resources save")
	var loaded: LfeWorldSave = LfeWorldSave.new()
	_check(loaded.open_world("resources", seed, true, _catalog, _root) == OK, "v2 reload")
	_check(loaded.resource_state == r.snapshot() and loaded.player_state == player, "All persisted state exact")
	_check(not loaded.is_dirty(player, r.snapshot()), "Loaded state clean")
	r.select(6)
	_check(loaded.is_dirty(player, r.snapshot()), "Hotbar-only changes dirty")
	var isolated: LfeWorldSave = LfeWorldSave.new()
	_check(isolated.open_world("isolation", seed, true, _catalog, _root) == OK, "Same-seed distinct world")
	_check(isolated.seed == loaded.seed and isolated.overrides.count() == 0 and isolated.resource_state == LfeResourceState.new(_catalog).snapshot(), "Complete same-seed isolation")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(world.get_primary_path()))
	var original_payload: Dictionary = JSON.parse_string(envelope["payload_json"])
	_check(original_payload["metadata"]["save_version"] == LfeWorldSave.SAVE_VERSION and original_payload["metadata"]["worldgen_version"] == world.worldgen_version and original_payload["metadata"]["content_version"] == 1, "Only save schema increments")
	var v1: Dictionary = original_payload.duplicate(true)
	v1["metadata"]["world_id"] = "migration"
	v1["metadata"]["save_version"] = 1
	v1["metadata"]["worldgen_version"] = 1
	v1.erase("resources")
	var v1_text: String = _envelope(v1, 1)
	var migration_path: String = _root.path_join("migration/world.json")
	_write(migration_path, v1_text)
	var migration: LfeWorldSave = LfeWorldSave.new()
	_check(migration.open_world("migration", seed, false, _catalog, _root) == OK, "Real v1 loads")
	_check(migration.player_state == player and migration.overrides.count() == 1 and migration.created_utc == v1["metadata"]["created_utc"], "Migration preserves original player/voxel/metadata")
	_check(migration.resource_state == LfeResourceState.new(_catalog).snapshot(), "Migration initializes safe Wave 3 defaults")
	_check(FileAccess.get_file_as_string(migration_path) == v1_text, "Opening v1 does not rewrite authority")
	_check(migration.save(player) == OK, "Explicit migrated save writes v2")
	_check(FileAccess.get_file_as_string(_root.path_join("migration/world.json.previous")) == v1_text, "Original v1 retained in previous copy")
	var migrated: LfeWorldSave = LfeWorldSave.new()
	_check(migrated.open_world("migration", seed, false, _catalog, _root) == OK and migrated.player_state == player, "Migrated v2 reload exact")
	# Leave a second disposable v1 for the rendered runtime migration/restart test.
	v1["metadata"]["world_id"] = "rendered_migration"
	_write(_root.path_join("rendered_migration/world.json"), _envelope(v1, 1))
	var mutations: Array = []
	var bad: Dictionary = original_payload.duplicate(true); bad["resources"]["inventory"][0]["quantity"] = 0; mutations.append(bad)
	bad = original_payload.duplicate(true); bad["resources"]["drops"][0]["stack"]["content"] = "unknown:item"; mutations.append(bad)
	bad = original_payload.duplicate(true); bad["resources"]["storage"][0]["slots"].pop_back(); mutations.append(bad)
	bad = original_payload.duplicate(true); bad["resources"]["storage"][0]["content"] = "unknown:crate"; mutations.append(bad)
	bad = original_payload.duplicate(true); bad["resources"]["hotbar_selected"] = -1; mutations.append(bad)
	bad = original_payload.duplicate(true); bad["resources"]["equipment"][0] = LfeItemStack.make(&"leyforge:dirt", 1); mutations.append(bad)
	bad = original_payload.duplicate(true); bad["metadata"]["save_version"] = 1; mutations.append(bad)
	bad = original_payload.duplicate(true); bad.erase("resources"); mutations.append(bad)
	for index: int in mutations.size():
		var data: Dictionary = mutations[index]
		var id: String = "bad_%d" % index
		data["metadata"]["world_id"] = id
		var text: String = _envelope(data, 2)
		var path: String = _root.path_join(id + "/world.json")
		_write(path, text)
		var rejected: LfeWorldSave = LfeWorldSave.new()
		_check(rejected.open_world(id, seed, false, _catalog, _root) != OK, "Corrupt resources reject %d" % index)
		_check(rejected.save(player) != OK and FileAccess.get_file_as_string(path) == text, "Failed load prohibits overwrite %d" % index)
	var save_before: String = FileAccess.get_file_as_string(world.get_primary_path())
	bad = r.snapshot(); bad["inventory"][0]["content"] = "unknown:item"
	_check(world.save(player, {}) != OK, "Explicit empty resources reject")
	_check(world.save(player, bad) != OK and FileAccess.get_file_as_string(world.get_primary_path()) == save_before, "Malformed runtime save cannot replace authority")
	_write(world.get_primary_path(), save_before + " ")
	_check(world.save(player, r.snapshot()) != OK, "External authority change detected")
	# Recover a complete v2 previous copy and ignore a pending file.
	_check(loaded.open_world("resources", seed, false, _catalog, _root) == OK, "Reopen externally changed valid file")
	_check(loaded.save(player, r.snapshot()) == OK, "Rotate complete v2 previous")
	_check(DirAccess.remove_absolute(loaded.get_primary_path()) == OK, "Simulate interrupted promotion")
	var recovery: LfeWorldSave = LfeWorldSave.new()
	_check(recovery.open_world("resources", seed, false, _catalog, _root) == OK and recovery.load_status.contains("Recovered"), "v2 previous recovery")
	var expected_recovery: LfeResourceState = LfeResourceState.new(_catalog)
	expected_recovery.restore(original_payload["resources"])
	_check(recovery.resource_state == expected_recovery.snapshot(), "Recovery retains exact resources")
	_write(recovery.get_world_directory().path_join(LfeWorldSave.PENDING_FILE), "broken pending")
	_check(recovery.save(player, recovery.resource_state) == OK, "Recovery validates/promotes v2")
	var corrupt_v1: Dictionary = v1.duplicate(true)
	corrupt_v1["metadata"]["world_id"] = "bad_v1"; corrupt_v1["player"]["position"] = [1, 2]
	_write(_root.path_join("bad_v1/world.json"), _envelope(corrupt_v1, 1))
	_check(LfeWorldSave.new().open_world("bad_v1", seed, false, _catalog, _root) != OK, "Malformed v1 remains rejected")


func _envelope(payload: Dictionary, version: int) -> String:
	var serialized: String = JSON.stringify(payload, "", true, true)
	return JSON.stringify({"save_version": version, "payload_json": serialized, "sha256": serialized.sha256_text()}, "	") + "
"


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Cannot write disposable fixture " + path)
		return
	file.store_string(text)
	file.flush()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
