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

var creation: Variant
var creation_presenter: LeyforgeCreationPresenter
var creation_panel: LeyforgeCreationPanel
var _actor_harvests: Dictionary = {}
var _harvest: Dictionary:
	get: return _actor_harvests.get(local_player_id,{})
	set(value): _actor_harvests[local_player_id] = value
var _primary_action_active: bool = false
var _sheltered: bool = false
var _shelter_timer: float = 0.0
var _resting: bool = false
var authority: LfeGameplayAuthority
var active_character: LfePlayerCharacter
var local_player_id: String = ""
var personal_resources: LfePlayerResourceState:
	get:return active_character.resources if active_character!=null else resource_network.replica.personal if resource_network!=null and resource_network.replica!=null else null
var world_resources: Variant:
	get:return authority.world_resources if authority!=null else resource_network.replica if resource_network!=null else null
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
var session_options: LfeSessionOptions
var movement: LeyforgePlayerMovement
var network_session: LfeNetworkSession
var resource_network: LeyforgeResourceNetwork
var voxel_network: LeyforgeVoxelNetwork
var client_voxel_overrides: LfeVoxelOverrideStore


func _ready() -> void:
	print("LEYFORGE_WAVE_0_BOOTSTRAP_READY")
	session_options = LfeSessionOptions.new()
	if not session_options.parse(OS.get_cmdline_user_args()):
		_fail_startup(session_options.error)
		return
	if session_options.mode == "JOIN":
		var view: LeyforgeSessionView = LeyforgeSessionView.new()
		add_child(view)
		if not view.start_join(session_options):
			_fail_startup("JOIN startup failed")
			return
		network_session = view.session
		local_player_id = view.local_player_id
		movement = LeyforgePlayerMovement.new()
		add_child(movement)
		movement.configure(self,network_session)
		_build_voxel_network()
		get_tree().auto_accept_quit = false
		return
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
	var profile: LfeLocalProfile = LfeLocalProfile.new()
	if profile.open_profile(session_options.profile_path) != OK:
		_fail_startup(profile.error)
		return
	world_save = LfeWorldSave.new()
	var open_error: Error = world_save.open_world(
		selected_id, requested_seed, seed_was_explicit, block_catalog, save_root, profile.player_id
	)
	if open_error != OK:
		_fail_startup(world_save.get_last_error())
		return
	local_player_id=world_save.local_player_id
	authority=LfeGameplayAuthority.new()
	if not authority.configure(world_save,block_catalog):
		_fail_startup("Invalid character/world state")
		return
	creation=authority.creation
	authority.relevant=region_relevant
	active_character=authority.character(local_player_id)
	active_seed = world_save.seed
	_build_environment()
	_build_terrain()
	if not _build_player():
		return
	if not player.development_selector:
		player.resource_state = personal_resources
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
		var wave4_driver: Node = load("res://tests/wave_5_part_1/w5_1_playtest_driver.gd" if arguments.has("--w51-playtest") else "res://tests/wave_4/wave_4_playtest_driver.gd").new()
		add_child(wave4_driver)
		wave4_driver.call("configure", self, player, terrain, block_catalog, active_seed)
	call_deferred("_finish_startup")


func _process(_delta: float) -> void:
	if world_save == null or player == null:
		return
	_sync_active_transform()
	player.set_persistence_debug(
		world_save.world_id,
		LfeWorldSave.SAVE_VERSION,
		world_save.is_dirty(authority.players_snapshot(),world_resources.snapshot(),creation.snapshot()),
		world_save.overrides.count(),
		"%s | %s" % [world_save.load_status, world_save.save_status]
	)


func _unhandled_input(event: InputEvent) -> void:
	if not _runtime_is_ready or not event is InputEventKey:
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	if session_options.mode == "JOIN":
		if key.keycode == KEY_F10: get_tree().quit(0)
		return
	if key.keycode == KEY_F5:
		request_save()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F10:
		request_save_and_quit()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if session_options != null and session_options.mode == "JOIN":
			get_tree().quit(0)
			return
		if _runtime_is_ready:
			request_save_and_quit()
		else:
			get_tree().quit(1)


func is_runtime_ready() -> bool:
	return _runtime_is_ready


func request_save() -> bool:
	if world_save == null or authority == null or not _runtime_is_ready or _save_in_progress:
		return false
	for actor: String in authority._grids.keys():
		if not authority.execute(actor,"close_grid").success:
			player.show_status("Save blocked: crafting staging must be returned",5000)
			return false
	if inventory_panel!=null and not close_inventory():
		return false
	_save_in_progress = true
	_sync_active_transform()
	var result: Error = world_save.save(authority.players_snapshot(),world_resources.snapshot(),creation.snapshot())
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
	_generator.configure(active_seed, block_catalog,int(network_session.world_manifest["worldgen_version"]) if world_save == null else world_save.worldgen_version)
	if world_save != null: _generator.set_override_store(world_save.overrides)
	else: _generator.set_override_store(client_voxel_overrides)

	var mesher: VoxelMesherBlocky = VoxelMesherBlocky.new()
	mesher.library = LfeBlockyLibraryFactory.create(block_catalog)

	terrain = VoxelTerrain.new()
	terrain.name = "VoxelTerrain"
	terrain.generator = _generator
	terrain.mesher = mesher
	terrain.material_override = LfeBlockyLibraryFactory.create_material()
	terrain.max_view_distance = 96
	terrain.generate_collisions = true
	terrain.collision_layer = LfeVoxelInteractionRules.WORLD_PHYSICAL_LAYER
	terrain.collision_mask = LfeVoxelInteractionRules.WORLD_PHYSICAL_LAYER
	terrain.set_generator_use_gpu(false)
	add_child(terrain)


func _build_player() -> bool:
	var restored_state: Dictionary = active_character.transform.duplicate(true) if active_character!=null else {}
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
	if active_character==null:
		active_character=authority.add_character(local_player_id,spawn_position)
		if active_character==null:
			_fail_startup("Could not create world-local character")
			return false
	print("WAVE_5_ACTIVE_CHARACTER player_id=%s owner=%s" % [local_player_id,world_save.owner_player_id])
	player = PLAYER_SCENE.instantiate() as LeyforgeFirstPersonPlayer
	add_child(player)
	player.character_record=active_character
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
	return world_save.overrides.voxel_id_at(cell, _generator.sample_voxel_id(cell)) if world_save != null else client_voxel_overrides.voxel_id_at(cell,_generator.sample_voxel_id(cell)) if client_voxel_overrides != null else _generator.sample_voxel_id(cell)


func _on_block_broken(cell: Vector3i, _previous_voxel_id: int) -> void:
	_record_edit(cell, block_catalog.get_voxel_id(&"leyforge:air"))


func _on_block_placed(cell: Vector3i, voxel_id: int) -> void:
	_record_edit(cell, voxel_id)


func _record_edit(cell: Vector3i, voxel_id: int) -> void:
	var tool: VoxelTool = terrain.get_voxel_tool()
	tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	var result: Error = _commit_voxel(cell,voxel_id,tool)
	if result != OK: push_error("WAVE_2_EDIT_FAIL %s" % world_save.get_last_error())
	else: print("WAVE_2_EDIT_RECORDED cell=%s block=%s" % [cell,block_catalog.canonical_id_for_voxel_id(voxel_id)])



func _finish_startup() -> void:
	var voxel_tool: VoxelTool = terrain.get_voxel_tool()
	voxel_tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	var floor_y: int = floori(spawn_position.y) - 1
	var spawn_area: AABB = AABB(
		Vector3(spawn_position.x - 2.5, float(floor_y - 2), spawn_position.z - 2.5),
		Vector3(5.0, 7.0, 5.0)
	)
	for _frame_index: int in range(3600 if session_options.mode == "JOIN" else STARTUP_TIMEOUT_FRAMES):
		await get_tree().physics_frame
		if (session_options.mode != "JOIN" or voxel_network.spawn_applied()) and voxel_tool.is_area_editable(spawn_area) and _spawn_floor_has_collision():
			for _settle_frame: int in range(4):
				await get_tree().physics_frame
			if session_options.mode == "HOST" and not _start_host_session():
				_fail_startup("Could not start host session; check UDP port availability")
				return
			_runtime_is_ready = true
			player.set_runtime_ready(true)
			player.show_status(world_save.load_status if world_save != null else "World synchronized / host authoritative voxels", 3000)
			print("LEYFORGE_WAVE_1_RUNTIME_READY seed=%d" % active_seed)
			runtime_ready.emit()
			if session_options.mode == "JOIN": print("W5_3_CLIENT_WORLD_READY player=%s" % local_player_id.left(8))
			if DisplayServer.get_name() == "headless" and not _playtest_mode and session_options.mode == "OFFLINE":
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
	world_resources.ensure_crate(crate_position)
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
	if inventory_panel == null: player.show_status("Synchronizing personal resources"); return
	if player.inventory_open:
		close_inventory()
	else:
		inventory_panel.open()


func close_inventory() -> bool:
	return inventory_panel.close() if inventory_panel != null else true


func open_nearby_storage() -> bool:
	for entry: Dictionary in world_resources.snapshot()["storage"]:
		var position: Array = entry["position"]
		var distance: float = player.global_position.distance_to(Vector3(float(position[0]), float(position[1]), float(position[2])))
		if distance <= 4.0:
			inventory_panel.open(true)
			return true
	player.show_status("Move closer to the storage crate")
	return false


func _apply_drop_selected(whole_stack: bool = false) -> bool:
	var slot: int = personal_resources.selected_slot()
	var stack: Dictionary = personal_resources.inventory.stack_at(slot)
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
	var id: String = world_resources.drop_from_inventory(personal_resources,slot, int(stack["quantity"]) if whole_stack else 1, position)
	if id.is_empty():
		player.show_status("Drop rejected")
		return false
	world_resources.ground_drop(id,drop_rest_position)
	resource_presenter.delay_pickup(id)
	resource_presenter.sync()
	player.show_status("Dropped resource")
	return true


func _apply_break_cell(cell: Vector3i) -> bool:
	return not _harvest.is_empty() and _harvest.get("cell") == cell and _complete_actor_voxel(local_player_id)


func _apply_place_cell(cell: Vector3i) -> bool:
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
	var success: bool = world_resources.place_from_inventory(personal_resources,personal_resources.selected_slot(),
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
	if world_save == null or not block_catalog.has_id(block_catalog.canonical_id_for_voxel_id(voxel)) or not LfeVoxelOverrideStore.valid_cell(cell) or not tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(cell)): return ERR_UNAUTHORIZED
	var result: Error = world_save.record_voxel_edit(cell, voxel, _generator.sample_voxel_id(cell))
	if result != OK:
		return result
	tool.set_voxel(cell, voxel)
	if voxel_network != null: voxel_network.committed(cell,voxel)
	return OK


func _physics_process(delta: float) -> void:
	if session_options.mode == "JOIN": return
	if not _runtime_is_ready or player == null or creation == null:
		return
	# Rendered drivers advance this same simulation seam with fixed durations,
	# so restart equality is independent of startup/render frame counts.
	if not OS.get_cmdline_user_args().has("--wave4-playtest"):
		player.sync_primary_action_input()
		advance_creation(delta)

func advance_creation(seconds: float) -> bool:
	if not LfeWorldSave._finite_in_range(seconds,60) or seconds < 0:
		return false
	_shelter_timer -= seconds
	if _shelter_timer <= 0:
		_sheltered = detect_shelter()
		_shelter_timer = 0.5
	var sprinting: bool = not player.inventory_open and Input.is_action_pressed("sprint") and Input.get_vector("move_left","move_right","move_forward","move_back") != Vector2.ZERO and can_sprint()
	authority.advance_world(seconds)
	command(local_player_id,"advance_player",{"seconds":seconds,"sheltered":_sheltered,"resting":_resting,"sprinting":sprinting})
	if not active_character.survival.alive():
		player.global_position = _find_safe_spawn()
		player.velocity = Vector3.ZERO
		command(local_player_id,"recover",{"spawn":player.global_position})
		_resting = false
		set_primary_action(false)
		player.show_status("Recovered at safe spawn; inventory retained",5000)
	if not _harvest.is_empty():
		advance_harvest(seconds)
	if creation_presenter != null:
		creation_presenter.sync()
	return true

func can_sprint() -> bool:
	if session_options.mode == "JOIN": return true
	return creation != null and active_character.survival.alive() and float(active_character.survival.snapshot()["stamina"]) >= 1 and float(active_character.survival.snapshot()["fatigue"]) < 100

# Explicit input/authority seam: begin, held continuation and immediate cancel.
# Work is transient and never carried into another target or attempt.
func _apply_set_primary_action(active: bool) -> void:
	_primary_action_active=active and player!=null and not player.inventory_open and creation!=null and active_character.survival.alive()
	if not _primary_action_active:
		if not _harvest.is_empty():player.show_status("Gathering cancelled")
		_harvest.clear()

func has_active_harvest() -> bool:
	return not _harvest.is_empty()

func _harvest_input_valid() -> bool:
	return _primary_action_active and _runtime_is_ready and player!=null and not player.inventory_open and active_character.survival.alive()

func _apply_begin_harvest(cell: Vector3i) -> bool:
	if not _harvest_input_valid() or has_active_harvest(): return false
	var tool: VoxelTool = terrain.get_voxel_tool()
	tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	var reason: String = _begin_actor_voxel(local_player_id,cell,tool.get_voxel(cell),0.0)
	player.show_status("Gathering... hold LMB" if reason == "accepted" else "Harvest: " + reason)
	return reason == "accepted"

func _apply_begin_source_harvest(id: String) -> bool:
	if not _harvest_input_valid() or has_active_harvest():return false
	var entry: Dictionary = creation.source(id)
	if entry.is_empty() or int(entry["remaining"]) <= 0 or not source_target_valid(id):return false
	var effect: Dictionary = LfeHarvestRules.evaluate(creation.source_definition(entry["source"]),LfeHarvestRules.tool(personal_resources),block_catalog)
	if effect.is_empty():
		player.show_status("This resource needs the matching tool capability")
		return false
	_harvest = effect
	_harvest.merge({"actor":local_player_id,"source":id,"source_snapshot":entry,"work":0.0})
	player.show_status("Gathering... hold LMB (%.2f s)" % float(effect["seconds"]))
	_resting = false
	return true

func _harvest_target_valid() -> bool:
	if _harvest.is_empty(): return false
	if not _harvest.has("source"): return _actor_voxel_valid(local_player_id) == "accepted"
	if not _harvest_input_valid() or _harvest.get("actor") != local_player_id: return false
	var source: Dictionary = creation.source(_harvest["source"])
	if source != _harvest["source_snapshot"] or not source_target_valid(_harvest["source"]): return false
	var effect: Dictionary = LfeHarvestRules.evaluate(creation.source_definition(source["source"]),LfeHarvestRules.tool(personal_resources),block_catalog)
	return not effect.is_empty() and effect["instance"] == _harvest["instance"] and effect["wear"] == _harvest["wear"] and is_equal_approx(float(effect["seconds"]),float(_harvest["seconds"]))

func _apply_advance_harvest(seconds: float) -> bool:
	if _harvest.is_empty() or not LfeWorldSave._finite_in_range(seconds,60) or seconds < 0:return false
	if not _harvest_target_valid():
		_harvest.clear()
		return false
	_harvest["work"] = float(_harvest["work"]) + seconds
	if float(_harvest["work"]) < float(_harvest["seconds"]):return false
	# One completion per call. Excess time is discarded; a later input step may
	# begin another zero-work attempt while the physical action remains held.
	var result: bool = false
	if _harvest.has("source"):
		result = creation.harvest_source(_harvest["source"],personal_resources,active_character.survival)
		_harvest.clear()
		creation_presenter.sync()
	else:
		result = break_cell(_harvest["cell"])
		_harvest.clear()
	player.show_status("Harvest complete" if result else "Harvest rejected; personal_resources unchanged")
	return result


func craft_recipe(id: String) -> bool:
	var result: LfeCommandResult=command(local_player_id,"craft",{"recipe":id})
	player.show_status("Craft requested" if result.data.get("pending",false) else "Crafted" if result.success else "Craft rejected: ingredients, context or capacity")
	return result.success

func consume_selected() -> bool:
	if session_options.mode == "JOIN": player.show_status("Survival consumption arrives in W5.6"); return false
	var result: LfeCommandResult=command(local_player_id,"consume")
	player.show_status("Consumed" if result.success else "Cannot use selected item now")
	return result.success

func toggle_crafting() -> void:
	inventory_panel.open_context("",true)

func interact_creation() -> bool:
	player._update_targeting()
	return targeted_interaction()

func _interact_object(id: String, function: String) -> bool:
	if function == "source":
		return begin_source_harvest(id)
	if function == "rest" and session_options.mode == "JOIN":
		player.show_status("Rest survival arrives in W5.6")
		return false
	if function == "rest":
		return begin_rest(id)
	return inventory_panel.open_context(id)

func _apply_begin_rest(id: String) -> bool:
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
	return command(local_player_id,"start_process",{"target":id,"recipe":recipe}).success

func object_near(id: String) -> bool:
	for entry: Dictionary in creation.objects():
		if entry["instance"] == id:
			var p: Array = entry["cell"]
			return _near_position([float(p[0])+0.5,float(p[1])+0.5,float(p[2])+0.5],4)
	return false

func transfer_object(id: String, channel: String, slot: int, quantity: int, withdrawing: bool) -> int:
	var source: String="storage/"+id
	if creation.station(id)!=null:source="station/"+id+"/"+channel
	var result: LfeCommandResult=command(local_player_id,"transfer",{"source":source if withdrawing else "inventory","destination":"inventory" if withdrawing else source,"source_slot":slot,"quantity":quantity})
	return int(result.data.get("quantity",0))

func damage_player(amount: float) -> bool:
	var result: bool=command(local_player_id,"damage",{"amount":amount}).success
	if result and not active_character.survival.alive():set_primary_action(false)
	return result

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
	if creation == null or inventory_panel == null: return false
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
	var result: LfeCommandResult=command(local_player_id,"transfer",{"source":authority.endpoint_name(local_player_id,source),"destination":authority.endpoint_name(local_player_id,destination),"source_slot":source_slot,"destination_slot":destination_slot,"quantity":quantity})
	return int(result.data.get("quantity",0))

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

func set_primary_action(active: bool) -> void:
	if session_options.mode == "JOIN": return
	command(local_player_id,"primary",{"active":active})

func drop_selected(whole_stack: bool = false) -> bool:
	return command(local_player_id,"drop_selected",{"whole_stack":whole_stack}).success

func break_cell(cell: Vector3i) -> bool:
	return command(local_player_id,"break_cell",{"cell":cell}).success

func place_cell(cell: Vector3i) -> bool:
	return command(local_player_id,"place_cell",{"cell":cell}).success

func begin_harvest(cell: Vector3i) -> bool:
	return command(local_player_id,"begin_harvest",{"cell":cell}).success

func begin_source_harvest(id: String) -> bool:
	return command(local_player_id,"begin_source_harvest",{"target":id}).success

func advance_harvest(seconds: float) -> bool:
	var result: LfeCommandResult=command(local_player_id,"advance_harvest",{"seconds":seconds})
	return result.success and bool(result.data.get("completed",false))

func begin_rest(id: String) -> bool:
	return command(local_player_id,"rest",{"target":id}).success

func _sync_active_transform() -> void:
	if active_character!=null and player!=null:
		active_character.transform=player.get_persistent_state()
	if movement != null and session_options.mode == "HOST": movement.sync_records()

# Single local controller submits directly. Future transport calls this same seam.
func command(actor: String,operation: String,args: Dictionary={}) -> LfeCommandResult:
	if session_options.mode == "JOIN": return client_resource_command(operation,args)
	if authority==null or authority.character(actor)==null:return LfeCommandResult.rejected("invalid_actor")
	_sync_active_transform()
	var local_ops: Array=["primary","drop_selected","break_cell","place_cell","begin_harvest","begin_source_harvest","advance_harvest","rest"]
	if operation not in local_ops:
		if not _runtime_is_ready:return LfeCommandResult.rejected("not_ready")
		return authority.execute(actor,operation,args)
	if actor!=local_player_id:return LfeCommandResult.rejected("not_ready")
	if operation=="primary":
		if not args.get("active") is bool:return LfeCommandResult.rejected("invalid_target")
		_apply_set_primary_action(args["active"])
		return LfeCommandResult.accepted()
	if not _runtime_is_ready:return LfeCommandResult.rejected("not_ready")
	for field: String in ["target"]:
		if args.has(field) and not args[field] is String:return LfeCommandResult.rejected("invalid_target")
	var success: bool=false
	match operation:
		"drop_selected":success=_apply_drop_selected(bool(args.get("whole_stack",false)))
		"break_cell","place_cell","begin_harvest":
			if not args.get("cell") is Vector3i:return LfeCommandResult.rejected("invalid_target")
			if operation=="break_cell":success=_apply_break_cell(args["cell"])
			elif operation=="place_cell":success=_apply_place_cell(args["cell"])
			else:success=_apply_begin_harvest(args["cell"])
		"begin_source_harvest":success=_apply_begin_source_harvest(args.get("target",""))
		"advance_harvest":
			if not LfeWorldSave._finite_in_range(args.get("seconds"),60) or float(args["seconds"])<0:return LfeCommandResult.rejected("invalid_target")
			if _harvest.is_empty():return LfeCommandResult.rejected("invalid_target")
			if not _harvest_target_valid():
				_harvest.clear()
				return LfeCommandResult.rejected("stale_state")
			success=_apply_advance_harvest(float(args["seconds"]))
			if success or not _harvest.is_empty():return LfeCommandResult.accepted({"completed":success})
		"rest":success=_apply_begin_rest(args.get("target",""))
	return LfeCommandResult.accepted() if success else LfeCommandResult.rejected("blocked")


func _start_host_session() -> bool:
	var fingerprint: String = LfeCompatibilityManifest.fingerprint()
	if fingerprint.is_empty(): return false
	network_session = LfeNetworkSession.new()
	add_child(network_session)
	if not network_session.start_host(session_options.port,LfeCompatibilityManifest.hello(local_player_id,fingerprint),LfeCompatibilityManifest.world(world_save,fingerprint),_admit_remote_character,_can_admit_remote_character): return false
	var view: LeyforgeSessionView = LeyforgeSessionView.new()
	add_child(view)
	view.build(network_session,local_player_id,true)
	movement = LeyforgePlayerMovement.new()
	add_child(movement)
	movement.configure(self,network_session)
	_build_voxel_network()
	return true

func _admit_remote_character(player_id: String) -> bool:
	if authority.character(player_id) != null:
		print("LFE_SESSION reconnect player=%s" % player_id.left(8))
		return true
	var safe_spawn: Vector3 = find_network_spawn(player_id)
	if not safe_spawn.is_finite(): return false
	return authority.add_character(player_id,safe_spawn) != null

func _can_admit_remote_character(player_id: String) -> bool:
	return authority.character(player_id) != null or (authority.characters.size() < LfeWorldSave.MAX_PLAYERS and find_network_spawn(player_id).is_finite())

func build_client_world(state: Dictionary) -> bool:
	if session_options.mode != "JOIN" or world_save != null or authority != null or player != null or state.is_empty(): return false
	if block_catalog == null: return false
	client_voxel_overrides = voxel_network.replica.store
	active_seed = int(network_session.world_manifest["seed"])
	_build_environment()
	_build_terrain()
	spawn_position = LfeMovementProtocol.vec3(state["position"])
	player = PLAYER_SCENE.instantiate() as LeyforgeFirstPersonPlayer
	add_child(player)
	player.configure_movement_only()
	player.configure_remote_voxels()
	player.configure(terrain,block_catalog,active_seed,spawn_position)
	player.set_movement_look(float(state["yaw"]),float(state["pitch"]))
	player.set_runtime_ready(false)
	call_deferred("_finish_startup")
	return true

func network_spawn_safe(position: Vector3, player_id: String, support_depth: float = 0.1) -> bool:
	if not network_position_safe(position,support_depth): return false
	var body: AABB = LfeVoxelInteractionRules.player_body_aabb(position).grow(0.15)
	if player != null and local_player_id != player_id and body.intersects(LfeVoxelInteractionRules.player_body_aabb(player.global_position)): return false
	if movement != null:
		for id: String in movement.bodies:
			if id != player_id and body.intersects(LfeVoxelInteractionRules.player_body_aabb(movement.bodies[id].global_position)): return false
	if _runtime_is_ready:
		var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = body.size
		query.shape = box
		query.transform.origin = body.get_center()
		query.collision_mask = LfeVoxelInteractionRules.FINITE_SOURCE_LAYER
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	return true

func find_network_spawn(player_id: String) -> Vector3:
	for radius: int in range(9):
		for z: int in range(-radius,radius+1):
			for x: int in range(-radius,radius+1):
				if maxi(absi(x),absi(z)) != radius: continue
				for y: int in range(TerrainRules.MAX_HEIGHT+4,TerrainRules.MIN_HEIGHT-8,-1):
					var candidate: Vector3 = Vector3(float(x)+0.5,float(y)+1.05,float(z)+0.5)
					if network_spawn_safe(candidate,player_id): return candidate
	return Vector3(INF,INF,INF)

func movement_area_ready(position: Vector3) -> bool:
	var tool: VoxelTool = terrain.get_voxel_tool()
	if not tool.is_area_editable(AABB(position-Vector3(2,3,2),Vector3(4,7,4))): return false
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(position+Vector3.UP*0.5,position+Vector3.DOWN*4,LfeVoxelInteractionRules.WORLD_PHYSICAL_LAYER)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

# Match the physical capsule rather than treating its empty lower corners as solid.
# CharacterBody's 3 cm safe margin permits small contact penetration at voxel edges.
func network_position_safe(position: Vector3, support_depth: float = 0.1) -> bool:
	if not position.is_finite() or absf(position.x) > 1000000 or absf(position.y) > 1000000 or absf(position.z) > 1000000: return false
	var bounds: AABB = LfeVoxelInteractionRules.player_body_aabb(position)
	var radius: float = LfeVoxelInteractionRules.PLAYER_RADIUS
	var lower: float = position.y + radius
	var upper: float = position.y + LfeVoxelInteractionRules.PLAYER_HEIGHT - radius
	for y: int in range(floori(bounds.position.y),floori(bounds.end.y)+1):
		for x: int in range(floori(bounds.position.x),floori(bounds.end.x)+1):
			for z: int in range(floori(bounds.position.z),floori(bounds.end.z)+1):
				if not block_catalog.is_solid_voxel(_voxel_id_at(Vector3i(x,y,z))): continue
				var dx: float = position.x - clampf(position.x,float(x),float(x+1))
				var dz: float = position.z - clampf(position.z,float(z),float(z+1))
				var dy: float = maxf(0,maxf(float(y)-upper,lower-float(y+1)))
				if dx*dx + dy*dy + dz*dz < pow(radius-0.035,2): return false
	# Saved authoritative bodies can be airborne over a nearby landing surface.
	# New-character spawn searches retain the strict immediate-support default.
	for offset: Vector2 in [Vector2.ZERO,Vector2(-0.3,-0.3),Vector2(0.3,0.3),Vector2(-0.3,0.3),Vector2(0.3,-0.3)]:
		for y: int in range(floori(position.y-0.1),floori(position.y-support_depth)-1,-1):
			var cell: Vector3i = Vector3i(floori(position.x+offset.x),y,floori(position.z+offset.y))
			if block_catalog.is_solid_voxel(_voxel_id_at(cell)): return true
	return false

func _build_voxel_network() -> void:
	voxel_network = LeyforgeVoxelNetwork.new()
	add_child(voxel_network)
	voxel_network.configure(self,network_session)
	resource_network = LeyforgeResourceNetwork.new()
	add_child(resource_network)
	resource_network.configure(self,network_session)

func cancel_actor_harvest(actor: String) -> void:
	_actor_harvests.erase(actor)

func actor_harvest_progress(actor: String) -> float:
	var state: Dictionary = _actor_harvests.get(actor,{})
	return clampf(float(state.get("work",0.0)) / float(state.get("seconds",1.0)),0,1)

func actor_harvest_state(actor: String, packet: Dictionary, now: float) -> String:
	if not packet["active"]:
		cancel_actor_harvest(actor)
		return "cancelled"
	var cell: Vector3i = LfeVoxelProtocol.cell(packet["target_cell"])
	var expected_block: int = block_catalog.get_voxel_id(StringName(packet["expected_block"]))
	var previous: Dictionary = _actor_harvests.get(actor,{})
	if not previous.is_empty() and (previous.get("cell") != cell or previous.get("block") != expected_block):
		cancel_actor_harvest(actor)
	if not _actor_harvests.get(actor,{}).is_empty():
		var reason: String = _actor_voxel_valid(actor)
		if reason != "accepted":
			cancel_actor_harvest(actor)
			return reason
		_actor_harvests[actor]["lease"] = now + LfeVoxelProtocol.HOLD_SECONDS
		return "accepted"
	return _begin_actor_voxel(actor,cell,expected_block,now)

func _actor_target_reason(actor: String, cell: Vector3i, expected_block: int) -> String:
	if not _runtime_is_ready or authority == null or authority.character(actor) == null or not authority.character(actor).survival.alive(): return "not_ready"
	var origin: Vector3
	var direction: Vector3
	if actor == local_player_id:
		if not _harvest_input_valid(): return "not_ready"
		player._update_targeting()
		if not player.target_source().is_empty() or not player.has_voxel_target() or player.get_target_cell() != cell: return "blocked"
		origin = player.get_camera().global_position
		direction = -player.get_camera().global_basis.z
	else:
		if movement == null or not movement.bodies.has(actor): return "not_ready"
		var body: LeyforgeAuthoritativePlayerBody = movement.bodies[actor]
		if not body.ready_for_movement: return "not_ready"
		origin = body.global_position + Vector3.UP * LfeVoxelInteractionRules.PLAYER_EYE_HEIGHT
		direction = -(Basis(Vector3.UP,body.rotation.y) * Basis(Vector3.RIGHT,body.pitch)).z
	if not LfeVoxelInteractionRules.cell_is_within_range(origin,cell,LeyforgeFirstPersonPlayer.INTERACTION_RANGE): return "out_of_range"
	var tool: VoxelTool = terrain.get_voxel_tool()
	tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	if not tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(cell)): return "not_ready"
	if tool.get_voxel(cell) != expected_block: return "stale_state"
	if not block_catalog.is_breakable_voxel(expected_block) or not creation.can_remove(cell): return "blocked"
	var ray: VoxelRaycastResult = tool.raycast(origin,direction,LeyforgeFirstPersonPlayer.INTERACTION_RANGE)
	if ray == null or ray.position != cell: return "blocked"
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin,origin+direction*ray.distance,LfeVoxelInteractionRules.SOURCE_TARGET_MASK)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return "blocked"
	var rule: Dictionary = block_catalog.definition_for_voxel_id(expected_block).get("harvest",{})
	var effect: Dictionary = LfeHarvestRules.evaluate(rule,LfeHarvestRules.tool(authority.character(actor).resources),block_catalog)
	if effect.is_empty(): return "tool_required"
	return "accepted"

func _begin_actor_voxel(actor: String, cell: Vector3i, block: int, now: float) -> String:
	var reason: String = _actor_target_reason(actor,cell,block)
	if reason != "accepted": return reason
	var rule: Dictionary = block_catalog.definition_for_voxel_id(block)["harvest"]
	var effect: Dictionary = LfeHarvestRules.evaluate(rule,LfeHarvestRules.tool(authority.character(actor).resources),block_catalog)
	effect.merge({"actor":actor,"cell":cell,"block":block,"work":0.0,"lease":now+LfeVoxelProtocol.HOLD_SECONDS})
	_actor_harvests[actor] = effect
	if actor == local_player_id: _resting = false
	return "accepted"

func _actor_voxel_valid(actor: String) -> String:
	var state: Dictionary = _actor_harvests.get(actor,{})
	if state.is_empty() or state.get("actor") != actor or not state.has("cell"): return "stale_state"
	if actor != local_player_id and Time.get_ticks_msec()/1000.0 > float(state["lease"]): return "cancelled"
	var reason: String = _actor_target_reason(actor,state["cell"],state["block"])
	if reason != "accepted": return reason
	var effect: Dictionary = LfeHarvestRules.evaluate(block_catalog.definition_for_voxel_id(state["block"])["harvest"],LfeHarvestRules.tool(authority.character(actor).resources),block_catalog)
	if effect.is_empty() or effect["instance"] != state["instance"] or effect["wear"] != state["wear"] or not is_equal_approx(float(effect["seconds"]),float(state["seconds"])): return "tool_required"
	return "accepted"

func advance_remote_harvests(seconds: float, _now: float) -> void:
	for actor: String in _actor_harvests.keys():
		if actor == local_player_id or _actor_harvests[actor].is_empty(): continue
		if _actor_harvests[actor].has("source"):
			_advance_actor_source(actor,seconds,_now)
			continue
		var reason: String = _actor_voxel_valid(actor)
		if reason != "accepted":
			cancel_actor_harvest(actor)
			voxel_network.harvest_finished(actor,reason)
			continue
		var state: Dictionary = _actor_harvests[actor]
		state["work"] = float(state["work"]) + seconds
		if float(state["work"]) >= float(state["seconds"]):
			var result: bool = _complete_actor_voxel(actor)
			cancel_actor_harvest(actor)
			voxel_network.harvest_finished(actor,"completed" if result else "stale_state")

func _complete_actor_voxel(actor: String) -> bool:
	var state: Dictionary = _actor_harvests.get(actor,{})
	if state.is_empty() or _actor_voxel_valid(actor) != "accepted" or float(state["work"]) < float(state["seconds"]): return false
	var cell: Vector3i = state["cell"]
	var previous: int = int(state["block"])
	var tool: VoxelTool = terrain.get_voxel_tool()
	tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	var position: Vector3 = Vector3(cell) + Vector3.ONE * 0.5
	var prior_drops: Array = world_resources.drops().map(func(entry: Dictionary)->String:return entry["instance"])
	var success: bool = world_resources.break_to_drop(block_catalog.canonical_id_for_voxel_id(previous),position,
		func() -> Error: return _commit_voxel(cell,block_catalog.get_voxel_id(&"leyforge:air"),tool),block_catalog.definition_for_voxel_id(previous)["harvest"]["outputs"])
	if not success: return false
	creation.remove_object(cell)
	creation_presenter.sync()
	if state.get("wear",false): LfeHarvestRules.wear(authority.character(actor).resources,state["instance"])
	cancel_actor_harvest(actor)
	for entry: Dictionary in world_resources.drops():
		if entry["instance"] not in prior_drops:
			world_resources.ground_drop(entry["instance"],drop_rest_position)
			resource_presenter.delay_pickup(entry["instance"])
	resource_presenter.sync()
	if actor == local_player_id: player.show_status("Broke %s" % block_catalog.display_name_for_voxel_id(previous))
	return true

# Shared resource read/command seam. JOIN views never allocate authority or saves.
func resource_endpoint_name(inventory: LfeInventory) -> String:
	return authority.endpoint_name(local_player_id,inventory) if authority != null else resource_network.replica.endpoint_name(inventory)

func resource_grid(object_id: String) -> LfeCraftingGrid:
	return authority.open_grid(local_player_id,object_id) if authority != null else resource_network.replica.grid

func build_client_resources() -> void:
	creation = resource_network.replica
	player.resource_state = personal_resources
	player.gameplay_authority = self
	player._instruction_label.text = "WASD move | Hold LMB gather | RMB interact/place | I inventory | C craft | Q drop | F10 leave"
	resource_presenter = LeyforgeResourcePresenter.new()
	add_child(resource_presenter); resource_presenter.configure(self)
	creation_presenter = LeyforgeCreationPresenter.new()
	add_child(creation_presenter); creation_presenter.configure(self)
	inventory_panel = LeyforgeInventoryPanel.new()
	add_child(inventory_panel); inventory_panel.configure(self)
	print("W5_5_PERSONAL_RESOURCES_READY")

func client_resource_command(operation: String, args: Dictionary) -> LfeCommandResult:
	if resource_network == null or resource_network.replica == null: return LfeCommandResult.rejected("not_ready")
	if operation == "primary": return LfeCommandResult.accepted()
	if operation in ["consume","rest"]: return LfeCommandResult.rejected("not_ready")
	if operation == "drop_selected":
		var slot: int = personal_resources.selected_slot()
		var stack: Dictionary = personal_resources.inventory.stack_at(slot)
		if stack.is_empty(): return LfeCommandResult.rejected("insufficient_resources")
		return resource_network.submit("drop",{"slot":slot,"quantity":int(stack["quantity"]) if args.get("whole_stack",false) else 1,"expected":stack})
	if operation == "place_cell":
		var cell: Vector3i = args["cell"]
		var slot: int = personal_resources.selected_slot()
		return resource_network.submit("place",{"cell":LfeVoxelProtocol.array3(cell),"expected_block":String(block_catalog.canonical_id_for_voxel_id(_voxel_id_at(cell))),"slot":slot,"expected":personal_resources.inventory.stack_at(slot)})
	if operation in LfeResourceProtocol.OPERATIONS: return resource_network.submit(operation,args)
	return LfeCommandResult.rejected("invalid_target")

func resource_world_command(actor: String, operation: String, args: Dictionary, now: float) -> LfeCommandResult:
	var personal: LfePlayerResourceState = authority.character(actor).resources
	var body: Node3D = player if actor == local_player_id else movement.bodies.get(actor)
	if body == null: return LfeCommandResult.rejected("not_ready")
	if operation == "pickup":
		if Time.get_ticks_msec() < int(resource_presenter._cooldowns.get(args["target"],0)): return LfeCommandResult.rejected("not_ready")
		return authority.execute(actor,"pickup",args)
	if operation == "drop":
		var position: Vector3 = body.global_position+Vector3.UP-body.global_basis.z*2.0
		var cell: Vector3i = Vector3i(position.floor())
		var tool: VoxelTool = terrain.get_voxel_tool(); tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
		if not tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(cell)) or block_catalog.is_solid_voxel(tool.get_voxel(cell)): return LfeCommandResult.rejected("blocked")
		var r: LfeCommandResult = authority.execute(actor,"drop",{"slot":args["slot"],"quantity":args["quantity"],"position":position})
		if r.success:
			var id: String = r.data["drop_id"]
			world_resources.ground_drop(id,drop_rest_position); resource_presenter.delay_pickup(id)
		return r
	if operation == "place":
		var cell: Vector3i = LfeVoxelProtocol.cell(args["cell"])
		if int(args["slot"]) != personal.selected_slot(): return LfeCommandResult.rejected("stale_state")
		var voxel: int = block_catalog.placeable_voxel(StringName(args["expected"]["content"]))
		if voxel < 0: return LfeCommandResult.rejected("invalid_target")
		var tool: VoxelTool = terrain.get_voxel_tool(); tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
		if not tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(cell)): return LfeCommandResult.rejected("not_ready")
		if tool.get_voxel(cell) != block_catalog.get_voxel_id(StringName(args["expected_block"])): return LfeCommandResult.rejected("stale_state")
		var origin: Vector3 = body.global_position+Vector3.UP*LfeVoxelInteractionRules.PLAYER_EYE_HEIGHT
		var pitch: float = player.get_camera().rotation.x if actor == local_player_id else movement.bodies[actor].pitch
		var direction: Vector3 = -(Basis(Vector3.UP,body.rotation.y)*Basis(Vector3.RIGHT,pitch)).z
		var ray: VoxelRaycastResult = tool.raycast(origin,direction,LeyforgeFirstPersonPlayer.INTERACTION_RANGE)
		if ray == null or ray.previous_position != cell: return LfeCommandResult.rejected("blocked")
		var obstruction: Dictionary = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin+direction*ray.distance,LfeVoxelInteractionRules.SOURCE_TARGET_MASK))
		if not obstruction.is_empty(): return LfeCommandResult.rejected("blocked")
		if not LfeVoxelInteractionRules.can_place(tool.get_voxel(cell),block_catalog.get_voxel_id(&"leyforge:air"),cell,LfeVoxelInteractionRules.player_body_aabb(player.global_position)): return LfeCommandResult.rejected("blocked")
		for remote: Node3D in movement.bodies.values():
			if not LfeVoxelInteractionRules.can_place(tool.get_voxel(cell),block_catalog.get_voxel_id(&"leyforge:air"),cell,LfeVoxelInteractionRules.player_body_aabb(remote.global_position)): return LfeCommandResult.rejected("blocked")
		if not creation.object_at(cell).is_empty() or creation.objects().size() >= 10000: return LfeCommandResult.rejected("blocked")
		var success: bool = world_resources.place_from_inventory(personal,int(args["slot"]),func()->Error:
			if not creation.add_object(block_catalog.canonical_id_for_voxel_id(voxel),cell,posmod(roundi(body.rotation.y/(PI/2)),4)): return ERR_CANT_CREATE
			var error: Error = _commit_voxel(cell,voxel,tool)
			if error != OK: creation.remove_object(cell)
			return error)
		return LfeCommandResult.accepted() if success else LfeCommandResult.rejected("blocked")
	if operation == "source_hold":
		if not args["active"]: cancel_actor_harvest(actor); return LfeCommandResult.accepted()
		var id: String = args["target"]
		var reason: String = _actor_source_reason(actor,id)
		if reason != "ok": cancel_actor_harvest(actor); return LfeCommandResult.rejected(reason)
		var previous: Dictionary = _actor_harvests.get(actor,{})
		if previous.get("source") != id: cancel_actor_harvest(actor)
		if _actor_harvests.get(actor,{}).is_empty():
			var s: Dictionary = creation.source(id)
			var effect: Dictionary = LfeHarvestRules.evaluate(creation.source_definition(s["source"]),LfeHarvestRules.tool(personal),block_catalog)
			effect.merge({"actor":actor,"source":id,"source_snapshot":s,"work":0.0,"lease":now+LfeVoxelProtocol.HOLD_SECONDS})
			_actor_harvests[actor] = effect
		else: _actor_harvests[actor]["lease"] = now+LfeVoxelProtocol.HOLD_SECONDS
		return LfeCommandResult.accepted()
	return LfeCommandResult.rejected("invalid_target")

func _actor_source_reason(actor: String, id: String) -> String:
	var s: Dictionary = creation.source(id)
	if s.is_empty() or int(s["remaining"]) == 0: return "stale_state"
	var body: Node3D = movement.bodies.get(actor)
	if body == null or not movement.bodies[actor].ready_for_movement: return "not_ready"
	if not authority.near(actor,s["position"],6): return "out_of_range"
	var origin: Vector3 = body.global_position+Vector3.UP*LfeVoxelInteractionRules.PLAYER_EYE_HEIGHT
	var direction: Vector3 = -(Basis(Vector3.UP,body.rotation.y)*Basis(Vector3.RIGHT,movement.bodies[actor].pitch)).z
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin+direction*6,LfeVoxelInteractionRules.SOURCE_TARGET_MASK))
	if hit.is_empty() or hit["collider"].get_meta("source","") != id: return "blocked"
	var tool: VoxelTool = terrain.get_voxel_tool(); tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	var ray: VoxelRaycastResult = tool.raycast(origin,direction,6)
	if ray != null and ray.distance < origin.distance_to(hit["position"])-0.05: return "blocked"
	if not authority.character(actor).survival.alive(): return "not_ready"
	var effect: Dictionary = LfeHarvestRules.evaluate(creation.source_definition(s["source"]),LfeHarvestRules.tool(authority.character(actor).resources),block_catalog)
	return "tool_required" if effect.is_empty() else "ok"

func _advance_actor_source(actor: String, seconds: float, now: float) -> void:
	var state: Dictionary = _actor_harvests[actor]
	var reason: String = _actor_source_reason(actor,state["source"])
	if now > float(state["lease"]): reason = "not_ready"
	var s: Dictionary = creation.source(state["source"])
	var effect: Dictionary = LfeHarvestRules.evaluate(creation.source_definition(s.get("source","")),LfeHarvestRules.tool(authority.character(actor).resources),block_catalog) if not s.is_empty() else {}
	if s != state["source_snapshot"] or effect.is_empty() or effect["instance"] != state["instance"]: reason = "stale_state"
	if reason != "ok":
		cancel_actor_harvest(actor); voxel_network.harvest_finished(actor,reason); return
	state["work"] = float(state["work"])+seconds
	if float(state["work"]) >= float(state["seconds"]):
		var success: bool = creation.harvest_source(state["source"],authority.character(actor).resources,authority.character(actor).survival)
		cancel_actor_harvest(actor); creation_presenter.sync()
		voxel_network.harvest_finished(actor,"completed" if success else "stale_state")
