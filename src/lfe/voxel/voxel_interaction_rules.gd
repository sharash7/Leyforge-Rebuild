class_name LfeVoxelInteractionRules
extends RefCounted

# Bit masks: terrain stays separate from finite source targeting.
const WORLD_PHYSICAL_LAYER: int = 1
const PLAYER_BODY_LAYER: int = 16
const FINITE_SOURCE_LAYER: int = 8
const PLAYER_PHYSICAL_MASK: int = WORLD_PHYSICAL_LAYER | FINITE_SOURCE_LAYER
const SOURCE_TARGET_MASK: int = FINITE_SOURCE_LAYER

const PLAYER_RADIUS: float = 0.35
const PLAYER_HEIGHT: float = 1.8
const PLAYER_EYE_HEIGHT: float = 1.62
const CELL_SHRINK_EPSILON: float = 0.01


static func cell_aabb(cell: Vector3i) -> AABB:
	return AABB(Vector3(cell), Vector3.ONE)


static func player_body_aabb(feet_position: Vector3) -> AABB:
	return AABB(
		feet_position + Vector3(-PLAYER_RADIUS, 0.0, -PLAYER_RADIUS),
		Vector3(PLAYER_RADIUS * 2.0, PLAYER_HEIGHT, PLAYER_RADIUS * 2.0)
	)


static func can_place(
	current_voxel_id: int,
	air_voxel_id: int,
	placement_cell: Vector3i,
	player_aabb: AABB
) -> bool:
	if current_voxel_id != air_voxel_id:
		return false
	var occupied_cell: AABB = cell_aabb(placement_cell).grow(-CELL_SHRINK_EPSILON)
	return not occupied_cell.intersects(player_aabb)


static func cell_is_within_range(
	camera_position: Vector3,
	cell: Vector3i,
	maximum_range: float
) -> bool:
	var cell_center: Vector3 = Vector3(cell) + Vector3.ONE * 0.5
	var half_diagonal: float = sqrt(3.0) * 0.5
	return camera_position.distance_to(cell_center) <= maximum_range + half_diagonal
