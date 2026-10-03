extends SceneTree

const TerrainRules = preload("res://src/lfe/worldgen/wave_1_terrain_rules.gd")

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog: LfeBlockCatalog = LfeBlockCatalog.new()
	var catalog_error: Error = catalog.load_default()
	_check(catalog_error == OK, "Canonical block catalog failed to load: %s" % catalog.get_last_error())
	if catalog_error == OK:
		_test_canonical_identities(catalog)
		_test_generation(catalog)
	_test_determinism()
	_test_interaction_safety(catalog)

	if _failures.is_empty():
		print("WAVE_1_TEST_PASS checks=%d" % _checks)
		quit(0)
	else:
		for failure: String in _failures:
			push_error("Wave 1 test failure: %s" % failure)
		print("WAVE_1_TEST_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _test_canonical_identities(catalog: LfeBlockCatalog) -> void:
	_check(catalog.block_count() >= LfeBlockCatalog.REQUIRED_CANONICAL_IDS.size(), "Wave 1 catalog must expose exactly five blocks.")
	var seen_voxel_ids: Dictionary = {}
	for canonical_id: StringName in LfeBlockCatalog.REQUIRED_CANONICAL_IDS:
		_check(catalog.has_id(canonical_id), "Missing canonical ID %s." % canonical_id)
		var voxel_id: int = catalog.get_voxel_id(canonical_id)
		_check(voxel_id >= 0, "Canonical ID %s did not resolve." % canonical_id)
		_check(not seen_voxel_ids.has(voxel_id), "Voxel ID %d is not unique." % voxel_id)
		seen_voxel_ids[voxel_id] = true
		_check(
			catalog.canonical_id_for_voxel_id(voxel_id) == canonical_id,
			"Canonical/voxel round trip failed for %s." % canonical_id
		)
	_check(catalog.get_voxel_id(&"leyforge:air") == 0, "Air must remain voxel ID zero.")
	_check(catalog.development_placeable_ids().size() == 4, "Exactly four solid blocks should be development-placeable.")

	var library: VoxelBlockyLibrary = LfeBlockyLibraryFactory.create(catalog)
	_check(library.get_models().size() == catalog.block_count(), "Blocky library does not match canonical voxel IDs.")
	_check(library.get_model(0) is VoxelBlockyModelEmpty, "Voxel ID zero must use the empty model.")
	for voxel_id: int in range(1, 5):
		_check(
			library.get_model(voxel_id) is VoxelBlockyModelCube,
			"Solid voxel ID %d must use a cube model." % voxel_id
		)


func _test_determinism() -> void:
	var samples: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 1),
		Vector2i(15, 15),
		Vector2i(16, 16),
		Vector2i(-17, 31),
		Vector2i(128, -96),
	]
	var seed: int = 184552221
	var first_signature: PackedInt32Array = TerrainRules.signature(seed, samples)
	var second_signature: PackedInt32Array = TerrainRules.signature(seed, samples)
	var different_signature: PackedInt32Array = TerrainRules.signature(seed + 1, samples)
	_check(first_signature == second_signature, "Repeated generation changed for a fixed seed.")
	_check(first_signature != different_signature, "Different seeds produced the same representative signature.")
	_check(
		LfeDeterministicSeed.from_text("Leyforge") == LfeDeterministicSeed.from_text("Leyforge"),
		"Text seed derivation is not deterministic."
	)
	_check(
		LfeDeterministicSeed.from_text("Leyforge") != LfeDeterministicSeed.from_text("Leyforge-2"),
		"Distinct text seeds did not derive distinct representative values."
	)


func _test_generation(catalog: LfeBlockCatalog) -> void:
	var seed: int = LfeDeterministicSeed.DEFAULT_WORLD_SEED
	var grass_coordinate: Vector2i = _find_surface_coordinate(
		seed,
		LfeWave1TerrainRules.MaterialLayer.GRASS
	)
	var sand_coordinate: Vector2i = _find_surface_coordinate(
		seed,
		LfeWave1TerrainRules.MaterialLayer.SAND
	)
	_check(grass_coordinate != Vector2i(999999, 999999), "No representative grass surface was generated.")
	_check(sand_coordinate != Vector2i(999999, 999999), "No representative sand surface was generated.")

	if grass_coordinate != Vector2i(999999, 999999):
		var grass_height: int = TerrainRules.height_at(seed, grass_coordinate.x, grass_coordinate.y)
		_check(
			TerrainRules.material_at(seed, grass_coordinate.x, grass_height + 1, grass_coordinate.y)
			== LfeWave1TerrainRules.MaterialLayer.AIR,
			"Voxel above a grass column is not Air."
		)
		_check(
			TerrainRules.material_at(seed, grass_coordinate.x, grass_height, grass_coordinate.y)
			== LfeWave1TerrainRules.MaterialLayer.GRASS,
			"Grass column surface is not Grass."
		)
		_check(
			TerrainRules.material_at(seed, grass_coordinate.x, grass_height - 1, grass_coordinate.y)
			== LfeWave1TerrainRules.MaterialLayer.DIRT,
			"Grass column subsurface is not Dirt."
		)
		_check(
			TerrainRules.material_at(seed, grass_coordinate.x, grass_height - 4, grass_coordinate.y)
			== LfeWave1TerrainRules.MaterialLayer.STONE,
			"Grass column deep layer is not Stone."
		)

	if sand_coordinate != Vector2i(999999, 999999):
		var sand_height: int = TerrainRules.height_at(seed, sand_coordinate.x, sand_coordinate.y)
		_check(
			TerrainRules.material_at(seed, sand_coordinate.x, sand_height, sand_coordinate.y)
			== LfeWave1TerrainRules.MaterialLayer.SAND,
			"Low-elevation surface is not Sand."
		)
		_check(
			TerrainRules.material_at(seed, sand_coordinate.x, sand_height - 1, sand_coordinate.y)
			== LfeWave1TerrainRules.MaterialLayer.SAND,
			"Sand column shallow layer is not Sand."
		)
		_check(
			TerrainRules.material_at(seed, sand_coordinate.x, sand_height - 3, sand_coordinate.y)
			== LfeWave1TerrainRules.MaterialLayer.STONE,
			"Sand column deep layer is not Stone."
		)

	var generator: LfeWave1TerrainGenerator = LfeWave1TerrainGenerator.new()
	generator.configure(seed, catalog)
	var origin_height: int = TerrainRules.height_at(seed, 0, 0)
	_check(
		generator.sample_voxel_id(Vector3i(0, origin_height + 1, 0))
		== catalog.get_voxel_id(&"leyforge:air"),
		"Generator mapping disagrees with the Air canonical ID."
	)
	_check(
		catalog.is_solid_voxel(generator.sample_voxel_id(Vector3i(0, origin_height, 0))),
		"Generated surface did not map to a solid canonical block."
	)


func _test_interaction_safety(catalog: LfeBlockCatalog) -> void:
	var air_voxel_id: int = catalog.get_voxel_id(&"leyforge:air")
	var stone_voxel_id: int = catalog.get_voxel_id(&"leyforge:stone")
	var player_aabb: AABB = LfeVoxelInteractionRules.player_body_aabb(Vector3(0.5, 1.0, 0.5))

	_check(
		not LfeVoxelInteractionRules.can_place(
			air_voxel_id,
			air_voxel_id,
			Vector3i(0, 1, 0),
			player_aabb
		),
		"Placement inside the player body was allowed."
	)
	_check(
		not LfeVoxelInteractionRules.can_place(
			stone_voxel_id,
			air_voxel_id,
			Vector3i(3, 1, 0),
			player_aabb
		),
		"Placement into an occupied solid voxel was allowed."
	)
	_check(
		LfeVoxelInteractionRules.can_place(
			air_voxel_id,
			air_voxel_id,
			Vector3i(3, 1, 0),
			player_aabb
		),
		"Valid placement in an empty, unoccupied cell was rejected."
	)
	_check(
		LfeVoxelInteractionRules.cell_is_within_range(Vector3.ZERO, Vector3i(5, 0, 0), 6.0),
		"An in-range target was rejected."
	)
	_check(
		not LfeVoxelInteractionRules.cell_is_within_range(Vector3.ZERO, Vector3i(8, 0, 0), 6.0),
		"An out-of-range target was accepted."
	)


func _find_surface_coordinate(
	seed: int,
	expected_surface: LfeWave1TerrainRules.MaterialLayer
) -> Vector2i:
	for world_z: int in range(-256, 257, 4):
		for world_x: int in range(-256, 257, 4):
			var height: int = TerrainRules.height_at(seed, world_x, world_z)
			if TerrainRules.surface_material_at(seed, world_x, world_z, height) == expected_surface:
				return Vector2i(world_x, world_z)
	return Vector2i(999999, 999999)


func _check(condition: bool, failure_message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(failure_message)
