class_name LfeBlockyLibraryFactory
extends RefCounted


static func create(catalog: LfeBlockCatalog) -> VoxelBlockyLibrary:
	var library: VoxelBlockyLibrary = VoxelBlockyLibrary.new()
	for voxel_id: int in range(catalog.block_count()):
		var definition: Dictionary = catalog.definition_for_voxel_id(voxel_id)
		var canonical_id: String = String(definition.get("id", ""))
		if bool(definition.get("solid", false)):
			var cube: VoxelBlockyModelCube = VoxelBlockyModelCube.new()
			cube.resource_name = canonical_id
			cube.color = catalog.color_for_voxel_id(voxel_id)
			var collision_boxes: Array[AABB] = [AABB(Vector3.ZERO, Vector3.ONE)]
			cube.collision_aabbs = collision_boxes
			library.add_model(cube)
		else:
			var empty: VoxelBlockyModelEmpty = VoxelBlockyModelEmpty.new()
			empty.resource_name = canonical_id
			library.add_model(empty)
	return library


static func create_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	return material
