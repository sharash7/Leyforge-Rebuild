class_name LeyforgeWave1Playground
extends Node3D

signal runtime_ready

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/wave_1_player.tscn")
const PLAYTEST_DRIVER_SCRIPT: Script = preload("res://tests/wave_1/wave_1_playtest_driver.gd")
const WAVE2_PLAYTEST_DRIVER_SCRIPT: Script = preload("res://tests/wave_2/wave_2_playtest_driver.gd")
const TerrainRules = preload("res://src/lfe/worldgen/wave_1_terrain_rules.gd")

const STARTUP_TIMEOUT_FRAMES: int = 900
const DEFAULT_WORLD_ID: String = "development"
const SPAWN_X: int = 0
const SPAWN_Z: int = 0

var creation: LfeCreationState
var creation_presenter: LeyforgeCreationPresenter
var creation_panel: LeyforgeCreationPanel
var _harvest: Dictionary = {}
var _sheltered: bool = false
var _shelter_timer: float = 0.0
var _resting: bool = false
var resources: LfeResourceState
var resource_presenter: LeyforgeResourcePresenter
var inventory_panel: LeyforgeInventoryPanel

var terrain: VoxelTerrain
var player: LeyforgeFirstPersonPlayer
var block_catalog: LfeBlockCatalog
var world_save: LfeWorldSave
var active_seed: int = LfeDeterministicSeed.DEFAULT_WORLD_SEED
var spawn_position: Vector3 = Vector3.ZERO
var _generator: LfeWave1TerrainGenerator
var _runtime_is_ready: bool = false
var _playtest_mode: bool = false
var _save_in_progress: bool = false


func _ready() -> void:
	print("LEYFORGE_WAVE_0_BOOTSTRAP_READY")
	if not ClassDB.class_exists(&"VoxelTerrain"):
		_fail_startup("Voxel Tools is not registered: missing VoxelTerrain.")
		return

	block_catalog = LfeBlockCatalog.new()
	var catalog_error: Error = block_catalog.load_default()
	# Isolated test definitions exercise equipment without adding production canon.
	if OS.get_cmdline_user_args().has("--wave3-playtest"):
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--wave3-test-content="):
				var fixture: String = argument.trim_prefix("--wave3-test-content=")
				if not fixture.is_absolute_path():
					_fail_startup("Test content must be an absolute disposable fixture path.")
					return
				catalog_error = block_catalog.load_from_path(fixture)
	if catalog_error != OK:
		_fail_startup(block_catalog.get_last_error())
		return

	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	_playtest_mode = arguments.has("--wave1-playtest") or arguments.has("--wave2-playtest") or arguments.has("--wave3-playtest") or arguments.has("--wave4-playtest")
	var selected_id: String = DEFAULT_WORLD_ID
	var save_root: String = "user://worlds"
	var seed_was_explicit: bool = false
	for argument: String in arguments:
		if argument.begins_with("--world-id="):
			selected_id = argument.trim_prefix("--world-id=")
		elif argument.begins_with("--world-root="):
			save_root = argument.trim_prefix("--world-root=")
		elif argument.begins_with("--seed="):
			seed_was_explicit = true
	if save_root.begins_with("res://") or (not save_root.begins_with("user://") and not save_root.is_absolute_path()):
		_fail_startup("World save root must be user:// or an absolute path.")
		return
	if not save_root.begins_with("user://"):
		var normalized_root: String = save_root.replace("\\", "/").simplify_path().to_lower()
		var project_root: String = ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
		if normalized_root == project_root or normalized_root.begins_with(project_root + "/"):
			_fail_startup("World saves cannot be stored inside the project repository.")
			return
	var requested_seed: int = LfeDeterministicSeed.from_user_args(arguments)
	world_save = LfeWorldSave.new()
	var open_error: Error = world_save.open_world(
		selected_id, requested_seed, seed_was_explicit, block_catalog, save_root
	)
	if open_error != OK:
		_fail_startup(world_save.get_last_error())
		return
	resources = LfeResourceState.new(block_catalog)
	if not resources.restore(world_save.resource_state):
		_fail_startup("Wave 3 resources are invalid.")
		return
	creation = LfeCreationState.new(block_catalog)
	if not creation.content_error.is_empty() or not creation.recipes.error.is_empty() or not creation.restore(world_save.creation_state, resources.snapshot()):
		_fail_startup("Invalid canonical recipes or survival/creation state")
		return
	active_seed = world_save.seed
	_build_environment()
	_build_terrain()
	if not _build_player():
		return
	if not player.development_selector:
		player.resource_state = resources
		player.gameplay_authority = self
		_build_resources()
	player.block_broken.connect(_on_block_broken)
	player.block_placed.connect(_on_block_placed)
	if not _playtest_mode:
		get_tree().auto_accept_quit = false

	print("LEYFORGE_VOXEL_PLUGIN_READY class=VoxelTerrain")
	print("LEYFORGE_WAVE_1_SEED seed=%d" % active_seed)
	print("LEYFORGE_WAVE_1_SPAWN position=%s" % spawn_position)
	print("LEYFORGE_WAVE_2_WORLD id=%s seed=%d status=%s" % [
		world_save.world_id, active_seed, world_save.load_status
	])

	if arguments.has("--wave1-playtest"):
		var playtest_driver: Node = PLAYTEST_DRIVER_SCRIPT.new()
		add_child(playtest_driver)
		playtest_driver.call(
			"configure", self, player, terrain, block_catalog, active_seed
		)
	elif arguments.has("--wave2-playtest"):
		var wave2_driver: Node = WAVE2_PLAYTEST_DRIVER_SCRIPT.new()
		add_child(wave2_driver)
		wave2_driver.call(
			"configure", self, player, terrain, block_catalog, active_seed
		)

	elif arguments.has("--wave3-playtest"):
		var wave3_driver: Node = load("res://tests/wave_3/wave_3_playtest_driver.gd").new()
		add_child(wave3_driver)
		wave3_driver.call("configure", self, player, terrain, block_catalog, active_seed)

	if arguments.has("--wave4-playtest"):
		var wave4_driver: Node = load("res://tests/wave_4/wave_4_playtest_driver.gd").new()
		add_child(wave4_driver)
		wave4_driver.call("configure", self, player, terrain, block_catalog, active_seed)
	call_deferred("_finish_startup")


func _process(_delta: float) -> void:
	if world_save == null or player == null:
		return
	var current_state: Dictionary = player.get_persistent_state()
	player.set_persistence_debug(
		world_save.world_id,
		LfeWorldSave.SAVE_VERSION,
		world_save.is_dirty(current_state, resources.snapshot(), creation.snapshot()),
		world_save.overrides.count(),
		"%s | %s" % [world_save.load_status, world_save.save_status]
	)


func _unhandled_input(event: InputEvent) -> void:
	if not _runtime_is_ready or not event is InputEventKey:
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_F5:
		request_save()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F10:
		request_save_and_quit()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _runtime_is_ready:
			request_save_and_quit()
		else:
			get_tree().quit(1)


func is_runtime_ready() -> bool:
	return _runtime_is_ready


func request_save() -> bool:
	if not _runtime_is_ready or _save_in_progress:
		return false
	if inventory_panel!=null and not close_inventory():
		return false
	_save_in_progress = true
	var result: Error = world_save.save(player.get_persistent_state(), resources.snapshot(), creation.snapshot())
	_save_in_progress = false
	if result != OK:
		player.show_status("Save failed: %s" % world_save.get_last_error(), 8000)
		push_error("WAVE_2_SAVE_FAIL %s" % world_save.get_last_error())
		return false
	player.show_status("Saved", 2000)
	print("WAVE_2_SAVE_PASS id=%s overrides=%d" % [
		world_save.world_id, world_save.overrides.count()
	])
	return true


func request_save_and_quit() -> bool:
	if not request_save():
		return false
	get_tree().quit(0)
	return true


func _build_environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.45, 0.68, 0.86)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.68, 0.76, 0.86)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)


func _build_terrain() -> void:
	_generator = LfeWave1TerrainGenerator.new()
	_generator.configure(active_seed, block_catalog,world_save.worldgen_version)
	_generator.set_override_store(world_save.overrides)

	var mesher: VoxelMesherBlocky = VoxelMesherBlocky.new()
	mesher.library = LfeBlockyLibraryFactory.create(block_catalog)

	terrain = VoxelTerrain.new()
	terrain.name = "VoxelTerrain"
	terrain.generator = _generator
	terrain.mesher = mesher
	terrain.material_override = LfeBlockyLibraryFactory.create_material()
	terrain.max_view_distance = 96
	terrain.generate_collisions = true
	terrain.collision_layer = 1
	terrain.collision_mask = 1
	terrain.set_generator_use_gpu(false)
	add_child(terrain)


func _build_player() -> bool:
	var restored_state: Dictionary = world_save.player_state.duplicate(true)
	var restore_saved_position: bool = false
	if not restored_state.is_empty():
		var saved_position: Array = restored_state["position"]
		var candidate: Vector3 = Vector3(
			float(saved_position[0]),
			float(saved_position[1]),
			float(saved_position[2])
		)
		if _position_is_safe(candidate):
			spawn_position = candidate
			restore_saved_position = true
	if not restore_saved_position:
		spawn_position = _find_safe_spawn()
		if is_inf(spawn_position.x):
			_fail_startup("No safe spawn found near the world origin; saved data was preserved.")
			return false
		if not restored_state.is_empty():
			restored_state["position"] = [spawn_position.x, spawn_position.y, spawn_position.z]
			world_save.load_status += "; unsafe saved player position, used safe spawn"
			print("WAVE_2_PLAYER_FALLBACK reason=unsafe_saved_position")
	player = PLAYER_SCENE.instantiate() as LeyforgeFirstPersonPlayer
	add_child(player)
	player.configure(terrain, block_catalog, active_seed, spawn_position)
	if not restored_state.is_empty():
		player.restore_persistent_state(restored_state)
	player.set_runtime_ready(false)
	return true


func _position_is_safe(position: Vector3) -> bool:
	if not LfeWorldSave._finite_in_range(position.x, 1000000.0) or not LfeWorldSave._finite_in_range(position.y, 1000000.0) or not LfeWorldSave._finite_in_range(position.z, 1000000.0):
		return false
	var body: AABB = LfeVoxelInteractionRules.player_body_aabb(position)
	var minimum_x: int = floori(body.position.x + 0.001)
	var maximum_x: int = floori(body.end.x - 0.001)
	var minimum_z: int = floori(body.position.z + 0.001)
	var maximum_z: int = floori(body.end.z - 0.001)
	for y: int in range(floori(body.position.y + 0.001), floori(body.end.y - 0.001) + 1):
		for x: int in range(minimum_x, maximum_x + 1):
			for z: int in range(minimum_z, maximum_z + 1):
				if block_catalog.is_solid_voxel(_voxel_id_at(Vector3i(x, y, z))):
					return false
	var support_y: int = floori(position.y - 0.08)
	for x: int in range(minimum_x, maximum_x + 1):
		for z: int in range(minimum_z, maximum_z + 1):
			if block_catalog.is_solid_voxel(_voxel_id_at(Vector3i(x, support_y, z))):
				return true
	return false


func _find_safe_spawn() -> Vector3:
	# Bounded, deterministic search. Never return an unchecked position.
	for radius: int in range(9):
		for z: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(z)) != radius:
					continue
				for y: int in range(TerrainRules.MAX_HEIGHT + 4, TerrainRules.MIN_HEIGHT - 8, -1):
					var candidate: Vector3 = Vector3(
						float(SPAWN_X + x) + 0.5, float(y) + 1.05, float(SPAWN_Z + z) + 0.5
					)
					if _position_is_safe(candidate):
						return candidate
	return Vector3(INF, INF, INF)


func _voxel_id_at(cell: Vector3i) -> int:
	return world_save.overrides.voxel_id_at(cell, _generator.sample_voxel_id(cell))


func _on_block_broken(cell: Vector3i, _previous_voxel_id: int) -> void:
	_record_edit(cell, block_catalog.get_voxel_id(&"leyforge:air"))


func _on_block_placed(cell: Vector3i, voxel_id: int) -> void:
	_record_edit(cell, voxel_id)


func _record_edit(cell: Vector3i, voxel_id: int) -> void:
	var result: Error = world_save.record_voxel_edit(cell, voxel_id, _generator.sample_voxel_id(cell))
	if result != OK:
		push_error("WAVE_2_EDIT_FAIL %s" % world_save.get_last_error())
	else:
		print("WAVE_2_EDIT_RECORDED cell=%s block=%s" % [
			cell, block_catalog.canonical_id_for_voxel_id(voxel_id)
		])


func _finish_startup() -> void:
	var voxel_tool: VoxelTool = terrain.get_voxel_tool()
	voxel_tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	var floor_y: int = floori(spawn_position.y) - 1
	var spawn_area: AABB = AABB(
		Vector3(spawn_position.x - 2.5, float(floor_y - 2), spawn_position.z - 2.5),
		Vector3(5.0, 7.0, 5.0)
	)
	for _frame_index: int in range(STARTUP_TIMEOUT_FRAMES):
		await get_tree().physics_frame
		if voxel_tool.is_area_editable(spawn_area) and _spawn_floor_has_collision():
			for _settle_frame: int in range(4):
				await get_tree().physics_frame
			_runtime_is_ready = true
			player.set_runtime_ready(true)
			player.show_status(world_save.load_status, 3000)
			print("LEYFORGE_WAVE_1_RUNTIME_READY seed=%d" % active_seed)
			runtime_ready.emit()
			if DisplayServer.get_name() == "headless" and not _playtest_mode:
				await get_tree().process_frame
				get_tree().quit(0)
			return
	_fail_startup("Timed out waiting for streamed terrain collision at the player spawn.")


func _spawn_floor_has_collision() -> bool:
	for offset_x: float in [-0.34, 0.0, 0.34]:
		for offset_z: float in [-0.34, 0.0, 0.34]:
			var sample: Vector3 = spawn_position + Vector3(offset_x, 0.0, offset_z)
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				sample + Vector3.UP * 0.5, sample + Vector3.DOWN * 4.0, 1
			)
			query.exclude = [player.get_rid()]
			if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				return true
	return false


func _fail_startup(message: String) -> void:
	push_error(message)
	print("LEYFORGE_WAVE_1_STARTUP_FAIL message=%s" % message)
	get_tree().quit(1)


func _build_resources() -> void:
	# Fixed representative storage stays near the deterministic origin spawn,
	# regardless of the player's saved location. Existing storage restores its position.
	var origin: Vector3 = _find_safe_spawn()
	var crate_position: Vector3 = origin + Vector3(2.0, -0.6, 0.0)
	resources.ensure_crate(crate_position)
	resource_presenter = LeyforgeResourcePresenter.new()
	add_child(resource_presenter)
	resource_presenter.configure(self)
	inventory_panel = LeyforgeInventoryPanel.new()
	add_child(inventory_panel)
	inventory_panel.configure(self)
	if not creation.initialize_sources(active_seed,world_save.worldgen_version):
		_fail_startup("Invalid gathering source definitions")
		return
	creation_presenter = LeyforgeCreationPresenter.new()
	add_child(creation_presenter)
	creation_presenter.configure(self)
	creation_panel = LeyforgeCreationPanel.new()
	add_child(creation_panel)
	creation_panel.configure(self)


func toggle_inventory() -> void:
	if player.inventory_open:
		close_inventory()
	else:
		inventory_panel.open()


func close_inventory() -> bool:
	return inventory_panel.close()


func open_nearby_storage() -> bool:
	for entry: Dictionary in resources.snapshot()["storage"]:
		var position: Array = entry["position"]
		var distance: float = player.global_position.distance_to(Vector3(float(position[0]), float(position[1]), float(position[2])))
		if distance <= 4.0:
			inventory_panel.open(true)
			return true
	player.show_status("Move closer to the storage crate")
	return false


func drop_selected(whole_stack: bool = false) -> bool:
	var slot: int = resources.selected_slot()
	var stack: Dictionary = resources.inventory.stack_at(slot)
	if stack.is_empty():
		player.show_status("Selected slot is empty")
		return false
	var position: Vector3 = player.global_position + Vector3.UP * 1.0 - player.global_basis.z * 2.0
	var tool: VoxelTool = terrain.get_voxel_tool()
	tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	var cell: Vector3i = Vector3i(position.floor())
	if not tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(cell)) or block_catalog.is_solid_voxel(tool.get_voxel(cell)):
		player.show_status("Drop location is blocked")
		return false
	var id: String = resources.drop_from_inventory(slot, int(stack["quantity"]) if whole_stack else 1, position)
	if id.is_empty():
		player.show_status("Drop rejected")
		return false
	resources.ground_drop(id,drop_rest_position)
	resource_presenter.delay_pickup(id)
	resource_presenter.sync()
	player.show_status("Dropped resource")
	return true


func break_cell(cell: Vector3i) -> bool:
	var tool: VoxelTool = terrain.get_voxel_tool()
	tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	if not _cell_interaction_valid(cell, tool):
		return false
	var previous: int = tool.get_voxel(cell)
	if _harvest.get("cell") != cell or float(_harvest.get("work",0)) < float(_harvest.get("seconds",1)) or _harvest.get("block") != previous:
		return false
	if not creation.can_remove(cell) or not block_catalog.is_breakable_voxel(previous):
		return false
	var air: int = block_catalog.get_voxel_id(&"leyforge:air")
	var position: Vector3 = Vector3(cell) + Vector3.ONE * 0.5
	var prior_drops: Array = resources.drops().map(func(entry: Dictionary)->String:return entry["instance"])
	var success: bool = resources.break_to_drop(block_catalog.canonical_id_for_voxel_id(previous), position,
		func() -> Error: return _commit_voxel(cell, air, tool), block_catalog.definition_for_voxel_id(previous)["harvest"]["outputs"])
	if success:
		creation.remove_object(cell)
		creation_presenter.sync()
		if _harvest.get("wear",false):
			LfeHarvestRules.wear(resources, _harvest["instance"])
		_harvest.clear()
		for entry: Dictionary in resources.drops():
			if entry["instance"] not in prior_drops:
				resources.ground_drop(entry["instance"],drop_rest_position)
				resource_presenter.delay_pickup(entry["instance"])
		resource_presenter.sync()
		player.show_status("Broke %s" % block_catalog.display_name_for_voxel_id(previous))
	else:
		player.show_status("Break rejected")
	return success


func place_cell(cell: Vector3i) -> bool:
	var tool: VoxelTool = terrain.get_voxel_tool()
	tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	var voxel: int = player.get_selected_voxel_id()
	if voxel < 0 or not _cell_interaction_valid(cell, tool) or not LfeVoxelInteractionRules.can_place(
		tool.get_voxel(cell), block_catalog.get_voxel_id(&"leyforge:air"), cell,
		LfeVoxelInteractionRules.player_body_aabb(player.global_position)):
		player.show_status("Placement blocked or selected slot is empty")
		return false
	var definition: Dictionary = block_catalog.definition_for_voxel_id(voxel)
	if definition.has("function") and (not creation.object_at(cell).is_empty() or creation.objects().size() >= 10000):
		return false
	var success: bool = resources.place_from_inventory(resources.selected_slot(),
		func() -> Error: return _commit_voxel(cell, voxel, tool))
	if success:
		creation.add_object(block_catalog.canonical_id_for_voxel_id(voxel), cell, posmod(roundi(player.rotation.y / (PI / 2)),4))
		creation_presenter.sync()
	player.show_status("Placed %s" % block_catalog.display_name_for_voxel_id(voxel) if success else "Placement rejected")
	return success


func _cell_interaction_valid(cell: Vector3i, tool: VoxelTool) -> bool:
	return _runtime_is_ready and LfeVoxelInteractionRules.cell_is_within_range(
		player.get_camera().global_position, cell, LeyforgeFirstPersonPlayer.INTERACTION_RANGE
	) and tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(cell))


func _commit_voxel(cell: Vector3i, voxel: int, tool: VoxelTool) -> Error:
	var result: Error = world_save.record_voxel_edit(cell, voxel, _generator.sample_voxel_id(cell))
	if result != OK:
		return result
	tool.set_voxel(cell, voxel)
	return OK


func _physics_process(delta: float) -> void:
	if not _runtime_is_ready or player == null or creation == null:
		return
	# Rendered drivers advance this same simulation seam with fixed durations,
	# so restart equality is independent of startup/render frame counts.
	if not OS.get_cmdline_user_args().has("--wave4-playtest"):
		advance_creation(delta)

func advance_creation(seconds: float) -> bool:
	if not LfeWorldSave._finite_in_range(seconds,60) or seconds < 0:
		return false
	_shelter_timer -= seconds
	if _shelter_timer <= 0:
		_sheltered = detect_shelter()
		_shelter_timer = 0.5
	var sprinting: bool = not player.inventory_open and Input.is_action_pressed("sprint") and Input.get_vector("move_left","move_right","move_forward","move_back") != Vector2.ZERO and can_sprint()
	creation.advance(seconds,_sheltered,_resting,sprinting)
	if not creation.survival.alive():
		player.global_position = _find_safe_spawn()
		player.velocity = Vector3.ZERO
		creation.survival.respawn()
		_resting = false
		_harvest.clear()
		player.show_status("Recovered at safe spawn; inventory retained",5000)
	if not _harvest.is_empty():
		advance_harvest(seconds)
	if creation_presenter != null:
		creation_presenter.sync()
	return true

func can_sprint() -> bool:
	return creation != null and creation.survival.alive() and float(creation.survival.snapshot()["stamina"]) >= 1 and float(creation.survival.snapshot()["fatigue"]) < 100

func begin_harvest(cell: Vector3i) -> bool:
	var tool: VoxelTool = terrain.get_voxel_tool()
	tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	if not _cell_interaction_valid(cell,tool) or not creation.can_remove(cell) or not creation.survival.alive():
		player.show_status("Harvest blocked; empty station/storage or recover health")
		return false
	var block: int = tool.get_voxel(cell)
	var rule: Dictionary = block_catalog.definition_for_voxel_id(block).get("harvest",{})
	var effect: Dictionary = LfeHarvestRules.evaluate(rule,LfeHarvestRules.tool(resources),block_catalog)
	if effect.is_empty():
		player.show_status("Needs matching %s capability %d" % [rule.get("class","tool"),int(rule.get("capability",0))])
		return false
	_harvest = effect
	_harvest.merge({"cell":cell,"block":block,"work":0.0})
	player.show_status("Gathering %.1f s" % float(effect["seconds"]))
	_resting = false
	return true

func begin_source_harvest(id: String) -> bool:
	var entry: Dictionary = creation.source(id)
	if entry.is_empty() or int(entry["remaining"]) <= 0 or not source_target_valid(id) or not creation.survival.alive():
		return false
	var effect: Dictionary = LfeHarvestRules.evaluate(creation.source_definition(entry["source"]),LfeHarvestRules.tool(resources),block_catalog)
	if effect.is_empty():
		player.show_status("This resource needs the matching tool capability")
		return false
	_harvest = effect
	_harvest.merge({"source":id,"work":0.0})
	player.show_status("Gathering %.1f s" % float(effect["seconds"]))
	_resting = false
	return true

func advance_harvest(seconds: float) -> bool:
	if _harvest.is_empty() or not LfeWorldSave._finite_in_range(seconds,60) or seconds < 0:
		return false
	var equipped: Dictionary = LfeHarvestRules.tool(resources)
	if _harvest["instance"] != equipped.get("instance","") or not creation.survival.alive():
		_harvest.clear()
		return false
	if _harvest.has("source"):
		var source: Dictionary = creation.source(_harvest["source"])
		if source.is_empty() or not source_target_valid(_harvest["source"]):
			_harvest.clear()
			return false
	else:
		var tool: VoxelTool = terrain.get_voxel_tool()
		if not _cell_interaction_valid(_harvest["cell"],tool) or tool.get_voxel(_harvest["cell"]) != _harvest["block"]:
			_harvest.clear()
			return false
	_harvest["work"] = float(_harvest["work"]) + seconds
	if float(_harvest["work"]) < float(_harvest["seconds"]):
		return false
	var result: bool = false
	if _harvest.has("source"):
		result = creation.harvest_source(_harvest["source"],resources)
		_harvest.clear()
		creation_presenter.sync()
	else:
		result = break_cell(_harvest["cell"])
		_harvest.clear()
	player.show_status("Harvest complete" if result else "Harvest rejected; resources unchanged")
	return result

func craft_recipe(id: String) -> bool:
	var result: bool = creation.survival.alive() and inventory_panel.crafting!=null and inventory_panel.context_valid() and inventory_panel.crafting.take(resources.inventory,id)
	player.show_status("Crafted" if result else "Craft rejected: ingredients, context or capacity")
	return result

func consume_selected() -> bool:
	var result: bool = creation.survival.consume(resources.inventory,resources.selected_slot())
	player.show_status("Consumed" if result else "Cannot use selected item now")
	return result

func toggle_crafting() -> void:
	inventory_panel.open_context("",true)

func interact_creation() -> bool:
	player._update_targeting()
	return targeted_interaction()

func _interact_object(id: String, function: String) -> bool:
	if function == "source":
		return begin_source_harvest(id)
	if function == "rest":
		return begin_rest(id)
	return inventory_panel.open_context(id)

func begin_rest(id: String) -> bool:
	for entry: Dictionary in creation.objects():
		if entry["instance"] == id and block_catalog.content_definition(StringName(entry["content"])).get("function") == "rest":
			var p: Array = entry["cell"]
			if _near_position([float(p[0])+0.5,float(p[1])+0.5,float(p[2])+0.5],3) and detect_shelter():
				_resting = true
				player.show_status("Resting in shelter; move to stop")
				return true
	player.show_status("Rest needs a covered, enclosed rest point")
	return false

func detect_shelter() -> bool:
	# Five short rays through authoritative voxel state, cached twice a second.
	var center: Vector3i = Vector3i((player.global_position + Vector3.UP).floor())
	var covered: bool = false
	for distance: int in range(1,5):
		if block_catalog.is_solid_voxel(_voxel_id_at(center + Vector3i.UP * distance)):
			covered = true
			break
	if not covered:
		return false
	var walls: int = 0
	for direction: Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		for distance: int in range(1,4):
			if block_catalog.is_solid_voxel(_voxel_id_at(center + direction * distance)):
				walls += 1
				break
	return walls >= 3

func _near_position(coordinates: Array, distance: float) -> bool:
	return player.global_position.distance_to(Vector3(float(coordinates[0]),float(coordinates[1]),float(coordinates[2]))) <= distance

func start_process(id: String, recipe: String) -> bool:
	var station: LfeWorkstation = creation.station(id)
	return station != null and object_near(id) and station.start(recipe)

func object_near(id: String) -> bool:
	for entry: Dictionary in creation.objects():
		if entry["instance"] == id:
			var p: Array = entry["cell"]
			return _near_position([float(p[0])+0.5,float(p[1])+0.5,float(p[2])+0.5],4)
	return false

func transfer_object(id: String, channel: String, slot: int, quantity: int, withdrawing: bool) -> int:
	if not object_near(id) or quantity <= 0:
		return 0
	var inventory: LfeInventory = creation.storage(id)
	var station: LfeWorkstation = creation.station(id)
	if station != null:
		match channel:
			"input": inventory = station.input
			"fuel": inventory = station.fuel
			"output": inventory = station.output
			_: return 0
	if inventory == null or (channel == "output" and not withdrawing):
		return 0
	return LfeItemTransactions.transfer(inventory if withdrawing else resources.inventory,slot,resources.inventory if withdrawing else inventory,quantity,-1,true)


func damage_player(amount: float) -> bool:
	return _runtime_is_ready and creation.survival.damage(amount)


# Voxel data relevance is the shared materialisation authority for local entities.
func region_relevant(position: Vector3) -> bool:
	if terrain == null:
		return false
	return terrain.get_voxel_tool().is_area_editable(LfeVoxelInteractionRules.cell_aabb(Vector3i(position.floor())))

func source_target_valid(id: String) -> bool:
	player._update_targeting()
	if creation_presenter == null or not creation_presenter._nodes.has(id):
		return false
	var entry: Dictionary = creation.source(id)
	if entry.is_empty() or int(entry["remaining"])<=0:
		return false
	var p: Array = entry["position"]
	var position: Vector3 = Vector3(float(p[0]),float(p[1]),float(p[2]))
	return region_relevant(position) and _near_position(p,6) and player.target_source()==id

func targeted_interaction() -> bool:
	var id: String = creation.object_at(player.get_target_cell()) if player.has_voxel_target() else ""
	for entry: Dictionary in creation.objects():
		if entry["instance"]!=id:
			continue
		var function: String = block_catalog.content_definition(StringName(entry["content"])).get("function","")
		if function in ["kiln","storage","rest","workbench"]:
			if not object_near(id):
				player.show_status("Move closer to interact")
				return true
			_interact_object(id,function)
			return true # A failed rest still owns RMB; never fall through to placement.
	if not player.target_crate().is_empty():
		return open_nearby_storage()
	return false

func workstation_slot_transfer(id: String, source: LfeInventory, source_slot: int, destination: LfeInventory, destination_slot: int, quantity: int) -> int:
	if not object_near(id):
		return 0
	var station: LfeWorkstation = creation.station(id)
	var storage: LfeInventory = creation.storage(id)
	var allowed: Array = [resources.inventory]
	if station!=null:
		allowed.append_array([station.input,station.fuel,station.output])
	if storage!=null:
		allowed.append(storage)
	if source not in allowed or destination not in allowed or (station!=null and destination==station.output):
		return 0
	return LfeItemTransactions.transfer(source,source_slot,destination,quantity,destination_slot,true)

func drop_path_clear(a: Vector3,b: Vector3) -> bool:
	var tool: VoxelTool = terrain.get_voxel_tool()
	tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	if not region_relevant(a) or not region_relevant(b):
		return false
	var distance: float = a.distance_to(b)
	if distance<=0.001:
		return true
	# Ignore the endpoints: harvested block drops can still occupy their resting cell.
	for index: int in range(1,9):
		var point: Vector3 = a.lerp(b,index/9.0)
		if block_catalog.is_solid_voxel(tool.get_voxel(Vector3i(point.floor()))):
			return false
	return true


# Resting centre = support top + 0.125m half-cube + 0.05m clearance.
# No loaded support within the bounded probe leaves the record for a later settle.
func drop_rest_position(position: Vector3) -> Variant:
	var tool: VoxelTool = terrain.get_voxel_tool();tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	var start: Vector3i = Vector3i(position.floor())
	for depth: int in 64:
		var cell: Vector3i = start-Vector3i(0,depth,0)
		if not tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(cell)):return null
		if block_catalog.is_solid_voxel(tool.get_voxel(cell)):
			var centre: Vector3 = Vector3(position.x,cell.y+1.175,position.z)
			if not tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(Vector3i(centre.floor()))):return null
			return centre
	return null
