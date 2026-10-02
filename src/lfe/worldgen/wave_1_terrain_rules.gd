class_name LfeWave1TerrainRules
extends RefCounted

enum MaterialLayer {
	AIR,
	GRASS,
	DIRT,
	STONE,
	SAND,
}

const MIN_HEIGHT: int = 4
const MAX_HEIGHT: int = 22
const SAND_MAX_HEIGHT: int = 8
const EXPOSED_STONE_MIN_HEIGHT: int = 19
const DIRT_DEPTH: int = 3
const SAND_DEPTH: int = 2

const _MASK: int = 0x7fffffff
const _BROAD_SEED_OFFSET: int = 0x13579B
const _HILL_SEED_OFFSET: int = 0x2468AC
const _DETAIL_SEED_OFFSET: int = 0x10203


static func height_at(seed: int, world_x: int, world_z: int) -> int:
	var broad: float = _value_noise(seed ^ _BROAD_SEED_OFFSET, world_x, world_z, 96)
	var hills: float = _value_noise(seed ^ _HILL_SEED_OFFSET, world_x, world_z, 32)
	var detail: float = _value_noise(seed ^ _DETAIL_SEED_OFFSET, world_x, world_z, 13)
	var height_value: float = 13.0 + broad * 5.0 + hills * 3.0 + detail
	return clampi(int(round(height_value)), MIN_HEIGHT, MAX_HEIGHT)


static func surface_material_at(seed: int, world_x: int, world_z: int, height: int) -> MaterialLayer:
	if height <= SAND_MAX_HEIGHT:
		return MaterialLayer.SAND

	if height >= EXPOSED_STONE_MIN_HEIGHT:
		var slope: int = 0
		slope = maxi(slope, absi(height - height_at(seed, world_x + 1, world_z)))
		slope = maxi(slope, absi(height - height_at(seed, world_x - 1, world_z)))
		slope = maxi(slope, absi(height - height_at(seed, world_x, world_z + 1)))
		slope = maxi(slope, absi(height - height_at(seed, world_x, world_z - 1)))
		if slope >= 2:
			return MaterialLayer.STONE

	return MaterialLayer.GRASS


static func material_at(seed: int, world_x: int, world_y: int, world_z: int) -> MaterialLayer:
	var height: int = height_at(seed, world_x, world_z)
	var surface_material: MaterialLayer = surface_material_at(seed, world_x, world_z, height)
	return material_for_column(surface_material, height, world_y)


static func material_for_column(
	surface_material: MaterialLayer,
	height: int,
	world_y: int
) -> MaterialLayer:
	if world_y > height:
		return MaterialLayer.AIR
	if world_y == height:
		return surface_material

	var depth: int = height - world_y
	if surface_material == MaterialLayer.SAND and depth <= SAND_DEPTH:
		return MaterialLayer.SAND
	if surface_material == MaterialLayer.GRASS and depth <= DIRT_DEPTH:
		return MaterialLayer.DIRT
	return MaterialLayer.STONE


static func signature(seed: int, sample_coordinates: Array[Vector2i]) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	for coordinate: Vector2i in sample_coordinates:
		result.append(height_at(seed, coordinate.x, coordinate.y))
	return result


static func _value_noise(seed: int, world_x: int, world_z: int, scale: int) -> float:
	var cell_x: int = floori(float(world_x) / float(scale))
	var cell_z: int = floori(float(world_z) / float(scale))
	var local_x: float = float(world_x - cell_x * scale) / float(scale)
	var local_z: float = float(world_z - cell_z * scale) / float(scale)
	var smooth_x: float = local_x * local_x * (3.0 - 2.0 * local_x)
	var smooth_z: float = local_z * local_z * (3.0 - 2.0 * local_z)

	var value_00: float = _unit_hash(seed, cell_x, cell_z)
	var value_10: float = _unit_hash(seed, cell_x + 1, cell_z)
	var value_01: float = _unit_hash(seed, cell_x, cell_z + 1)
	var value_11: float = _unit_hash(seed, cell_x + 1, cell_z + 1)
	var row_0: float = lerpf(value_00, value_10, smooth_x)
	var row_1: float = lerpf(value_01, value_11, smooth_x)
	return lerpf(row_0, row_1, smooth_z) * 2.0 - 1.0


static func _unit_hash(seed: int, x: int, z: int) -> float:
	var value: int = seed & _MASK
	value = _mix(value, x)
	value = _mix(value, z)
	return float(value) / float(_MASK)


static func _mix(current: int, component: int) -> int:
	var value: int = (current ^ (component & _MASK)) & _MASK
	value = (value * 1103515245 + 12345) & _MASK
	value = (value ^ (value >> 16)) & _MASK
	return value
