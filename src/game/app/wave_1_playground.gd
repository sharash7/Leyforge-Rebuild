class_name LeyforgeWave1Playground
extends Node3D

signal runtime_ready

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/wave_1_player.tscn")
const PLAYTEST_DRIVER_SCRIPT: Script = preload("res://tests/wave_1/wave_1_playtest_driver.gd")
const TerrainRules = preload("res://src/lfe/worldgen/wave_1_terrain_rules.gd")

const STARTUP_TIMEOUT_FRAMES: int = 900
const SPAWN_X: int = 0
const SPAWN_Z: int = 0

var terrain: VoxelTerrain
var player: LeyforgeFirstPersonPlayer
var block_catalog: LfeBlockCatalog
var active_seed: int = LfeDeterministicSeed.DEFAULT_WORLD_SEED
var spawn_position: Vector3 = Vector3.ZERO
var _runtime_is_ready: bool = false
var _playtest_mode: bool = false


func _ready() -> void:
	print("LEYFORGE_WAVE_0_BOOTSTRAP_READY")
	if not ClassDB.class_exists(&"VoxelTerrain"):
		_fail_startup("Voxel Tools is not registered: missing VoxelTerrain.")
		return

	block_catalog = LfeBlockCatalog.new()
	var catalog_error: Error = block_catalog.load_default()
	if catalog_error != OK:
		_fail_startup(block_catalog.get_last_error())
		return

	active_seed = LfeDeterministicSeed.from_user_args(OS.get_cmdline_user_args())
	_playtest_mode = OS.get_cmdline_user_args().has("--wave1-playtest")
	_build_environment()
	_build_terrain()
	_build_player()

	print("LEYFORGE_VOXEL_PLUGIN_READY class=VoxelTerrain")
	print("LEYFORGE_WAVE_1_SEED seed=%d" % active_seed)
	print("LEYFORGE_WAVE_1_SPAWN position=%s" % spawn_position)

	if _playtest_mode:
		var playtest_driver: Node = PLAYTEST_DRIVER_SCRIPT.new()
		add_child(playtest_driver)
		playtest_driver.call(
			"configure",
			self,
			player,
			terrain,
			block_catalog,
			active_seed
		)

	call_deferred("_finish_startup")


func is_runtime_ready() -> bool:
	return _runtime_is_ready


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
	var generator: LfeWave1TerrainGenerator = LfeWave1TerrainGenerator.new()
	generator.configure(active_seed, block_catalog)

	var mesher: VoxelMesherBlocky = VoxelMesherBlocky.new()
	mesher.library = LfeBlockyLibraryFactory.create(block_catalog)

	terrain = VoxelTerrain.new()
	terrain.name = "VoxelTerrain"
	terrain.generator = generator
	terrain.mesher = mesher
	terrain.material_override = LfeBlockyLibraryFactory.create_material()
	terrain.max_view_distance = 96
	terrain.generate_collisions = true
	terrain.collision_layer = 1
	terrain.collision_mask = 1
	terrain.set_generator_use_gpu(false)
	add_child(terrain)


func _build_player() -> void:
	var surface_height: int = TerrainRules.height_at(active_seed, SPAWN_X, SPAWN_Z)
	spawn_position = Vector3(
		float(SPAWN_X) + 0.5,
		float(surface_height) + 1.05,
		float(SPAWN_Z) + 0.5
	)
	player = PLAYER_SCENE.instantiate() as LeyforgeFirstPersonPlayer
	add_child(player)
	player.configure(terrain, block_catalog, active_seed, spawn_position)
	player.set_runtime_ready(false)


func _finish_startup() -> void:
	var voxel_tool: VoxelTool = terrain.get_voxel_tool()
	voxel_tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	var surface_height: int = TerrainRules.height_at(active_seed, SPAWN_X, SPAWN_Z)
	var spawn_area: AABB = AABB(
		Vector3(float(SPAWN_X - 2), float(surface_height - 3), float(SPAWN_Z - 2)),
		Vector3(5.0, 7.0, 5.0)
	)

	for _frame_index: int in range(STARTUP_TIMEOUT_FRAMES):
		await get_tree().physics_frame
		if voxel_tool.is_area_editable(spawn_area) and _spawn_floor_has_collision():
			for _settle_frame: int in range(4):
				await get_tree().physics_frame
			_runtime_is_ready = true
			player.set_runtime_ready(true)
			print("LEYFORGE_WAVE_1_RUNTIME_READY seed=%d" % active_seed)
			runtime_ready.emit()
			if DisplayServer.get_name() == "headless" and not _playtest_mode:
				await get_tree().process_frame
				get_tree().quit(0)
			return

	_fail_startup("Timed out waiting for streamed terrain collision at the player spawn.")


func _spawn_floor_has_collision() -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		spawn_position + Vector3.UP * 0.5,
		spawn_position + Vector3.DOWN * 4.0,
		1
	)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty()


func _fail_startup(message: String) -> void:
	push_error(message)
	print("LEYFORGE_WAVE_1_STARTUP_FAIL message=%s" % message)
	if DisplayServer.get_name() == "headless" or _playtest_mode:
		get_tree().quit(1)
