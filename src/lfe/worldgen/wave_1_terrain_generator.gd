class_name LfeWave1TerrainGenerator
extends VoxelGeneratorScript

const TerrainRules = preload("res://src/lfe/worldgen/wave_1_terrain_rules.gd")
const CHANNEL: int = VoxelBuffer.CHANNEL_TYPE

var _seed: int = 0
var _air_id: int = 0
var _grass_id: int = 1
var _dirt_id: int = 2
var _stone_id: int = 3
var _sand_id: int = 4
var _worldgen_version: int = 1
var _wood_id: int = 11
var _leaves_id: int = 12
var _configured: bool = false
var _override_store: LfeVoxelOverrideStore


func configure(seed: int, catalog: LfeBlockCatalog, worldgen_version: int = 1) -> void:
	assert(worldgen_version in [1,2])
	_worldgen_version=worldgen_version
	_wood_id=catalog.get_voxel_id(&"leyforge:oak_heartwood")
	_leaves_id=catalog.get_voxel_id(&"leyforge:oak_leaves")
	_seed = LfeDeterministicSeed.normalize(seed)
	_air_id = catalog.get_voxel_id(&"leyforge:air")
	_grass_id = catalog.get_voxel_id(&"leyforge:grass")
	_dirt_id = catalog.get_voxel_id(&"leyforge:dirt")
	_stone_id = catalog.get_voxel_id(&"leyforge:stone")
	_sand_id = catalog.get_voxel_id(&"leyforge:sand")
	_configured = true


func set_override_store(store: LfeVoxelOverrideStore) -> void:
	_override_store = store


func get_seed() -> int:
	return _seed


func sample_voxel_id(world_position: Vector3i) -> int:
	var layer: LfeWave1TerrainRules.MaterialLayer = TerrainRules.material_at(
		_seed, world_position.x, world_position.y, world_position.z
	)
	if layer==TerrainRules.MaterialLayer.AIR and _worldgen_version==2:
		var decoration: int = LfeStarterTreeRules.material_at(_seed,world_position)
		if decoration!=0:return _wood_id if decoration==1 else _leaves_id
	return _voxel_id_for_layer(layer)


func _get_used_channels_mask() -> int:
	return 1 << CHANNEL


func _generate_block(
	out_buffer: VoxelBuffer,
	origin_in_voxels: Vector3i,
	lod: int
) -> void:
	if not _configured or lod != 0:
		out_buffer.fill(_air_id, CHANNEL)
		return

	var size: Vector3i = out_buffer.get_size()
	var block_top: int = origin_in_voxels.y + size.y - 1
	if origin_in_voxels.y > TerrainRules.MAX_HEIGHT:
		out_buffer.fill(_air_id, CHANNEL)
		_decorate(out_buffer, origin_in_voxels)
		_apply_overrides(out_buffer, origin_in_voxels)
		return
	if block_top <= TerrainRules.MIN_HEIGHT - TerrainRules.DIRT_DEPTH - 1:
		out_buffer.fill(_stone_id, CHANNEL)
		_apply_overrides(out_buffer, origin_in_voxels)
		return

	out_buffer.fill(_air_id, CHANNEL)
	for local_z: int in range(size.z):
		var world_z: int = origin_in_voxels.z + local_z
		for local_x: int in range(size.x):
			var world_x: int = origin_in_voxels.x + local_x
			var height: int = TerrainRules.height_at(_seed, world_x, world_z)
			var surface: LfeWave1TerrainRules.MaterialLayer = TerrainRules.surface_material_at(
				_seed, world_x, world_z, height
			)
			for local_y: int in range(size.y):
				var world_y: int = origin_in_voxels.y + local_y
				if world_y > height:
					continue
				var layer: LfeWave1TerrainRules.MaterialLayer = TerrainRules.material_for_column(
					surface, height, world_y
				)
				out_buffer.set_voxel(
					_voxel_id_for_layer(layer),
					local_x,
					local_y,
					local_z,
					CHANNEL
				)
	_decorate(out_buffer, origin_in_voxels)
	_apply_overrides(out_buffer, origin_in_voxels)


func _decorate(buffer: VoxelBuffer, origin: Vector3i) -> void:
	var size: Vector3i = buffer.get_size()
	if _worldgen_version!=2 or origin.y>LfeStarterTreeRules.MAX_TOP or origin.y+size.y<=TerrainRules.MIN_HEIGHT:return
	for tree: Dictionary in LfeStarterTreeRules.candidates(_seed,Vector2i(origin.x,origin.z),Vector2i(origin.x+size.x-1,origin.z+size.z-1)):
		var cells: Dictionary = LfeStarterTreeRules.cells(tree)
		for cell: Vector3i in cells:
			var local: Vector3i = cell-origin
			if local.x<0 or local.y<0 or local.z<0 or local.x>=size.x or local.y>=size.y or local.z>=size.z:continue
			if buffer.get_voxel(local.x,local.y,local.z,CHANNEL)==_air_id:
				buffer.set_voxel(_wood_id if cells[cell]==1 else _leaves_id,local.x,local.y,local.z,CHANNEL)


func _apply_overrides(out_buffer: VoxelBuffer, origin: Vector3i) -> void:
	if _override_store == null:
		return
	var snapshot: Dictionary = _override_store.snapshot_for_block(origin, out_buffer.get_size())
	for cell: Vector3i in snapshot:
		var local_cell: Vector3i = cell - origin
		out_buffer.set_voxel(
			int(snapshot[cell]),
			local_cell.x,
			local_cell.y,
			local_cell.z,
			CHANNEL
		)


func _voxel_id_for_layer(layer: LfeWave1TerrainRules.MaterialLayer) -> int:
	match layer:
		LfeWave1TerrainRules.MaterialLayer.GRASS:
			return _grass_id
		LfeWave1TerrainRules.MaterialLayer.DIRT:
			return _dirt_id
		LfeWave1TerrainRules.MaterialLayer.STONE:
			return _stone_id
		LfeWave1TerrainRules.MaterialLayer.SAND:
			return _sand_id
		_:
			return _air_id
