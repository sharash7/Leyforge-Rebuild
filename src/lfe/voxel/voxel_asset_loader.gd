extends RefCounted
## Runtime data-only reader: validates against reproducible source before resources.
const Source = preload("res://src/lfe/content/voxel_asset.gd")
const Compiler = preload("res://src/lfe/voxel/voxel_asset_compiler.gd")
const MAX_BUNDLE_BYTES = 33554432

static func load_bundle(root: String, relative: String, path: String) -> Dictionary:
	var source: Dictionary = Source.read_source(root, relative)
	if not source.success: return source
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return Source.fail("bundle: missing")
	var length: int=file.get_length()
	if length > MAX_BUNDLE_BYTES: return Source.fail("bundle: exceeds 32 MiB")
	var raw: PackedByteArray=file.get_buffer(length);file.close()
	var parsed: Dictionary = Source.parse(raw, MAX_BUNDLE_BYTES)
	if not parsed.success: return parsed
	if not parsed.value is Dictionary or parsed.value.get("artifact_version") != 1 or parsed.value.get("compiler_version") != Compiler.VERSION: return Source.fail("bundle: unsupported artifact/compiler version")
	var checked: Dictionary=shape_check(parsed.value)
	if not checked.success:return checked
	if parsed.value.get("source_hash")!=source.source_hash or parsed.value.get("dependencies")!=source.dependencies:return Source.fail("bundle: stale source/dependency hashes")
	var expected: Dictionary = Compiler.compile(source.data, source, source.source_hash)
	if not expected.success or Source.bytes(parsed.value) != Source.bytes(expected.bundle): return Source.fail("bundle: stale source/dependencies or malformed geometry/collision")
	if FileAccess.get_sha256(root.path_join(relative))!=source.source_hash:return Source.fail("source changed during bundle validation")
	for dependency: String in source.dependencies:
		if FileAccess.get_sha256(root.path_join(dependency))!=source.dependencies[dependency]:return Source.fail("dependency changed during bundle validation")
	return {"success":true,"reason":"","bundle":expected.bundle}

static func shape_check(bundle: Dictionary) -> Dictionary:
	for field: String in ["vertices","normals","colors","indices","collision_boxes"]:
		if not bundle.get(field) is Array:return Source.fail("bundle: "+field+" must be an array")
	var count: int=bundle.vertices.size()
	if count==0 or count>4096*6*4 or count%4!=0 or bundle.normals.size()!=count or bundle.colors.size()!=count or bundle.indices.size()>4096*6*6 or bundle.indices.size()!=count/4*6 or bundle.collision_boxes.is_empty() or bundle.collision_boxes.size()>4096:return Source.fail("bundle: decoded mesh/collision counts exceed bounded contract")
	for index: int in count:
		var corner: Variant=bundle.vertices[index];var normal: Variant=bundle.normals[index]
		if not corner is Array or corner.size()!=3 or not normal is Array or normal.size()!=3:return Source.fail("bundle: three-component corner/normal required")
		var length: int=0
		for axis: int in 3:
			if not Source.integer(corner[axis]) or corner[axis]<0 or corner[axis]>16 or not Source.integer(normal[axis]) or normal[axis]<-1 or normal[axis]>1:return Source.fail("bundle: invalid integer corner/normal")
			length+=abs(normal[axis])
		if length!=1:return Source.fail("bundle: flat unit axis normal required")
		if not bundle.colors[index] is String or not Source.matches("^#[0-9A-F]{6}FF$",bundle.colors[index]):return Source.fail("bundle: invalid opaque vertex colour")
	for index: Variant in bundle.indices:
		if not Source.integer(index) or index<0 or index>=count:return Source.fail("bundle: index outside vertex array")
	for box: Variant in bundle.collision_boxes:
		if not box is Dictionary or box.size()!=2 or not box.get("min") is Array or box.min.size()!=3 or not box.get("size") is Array or box.size.size()!=3:return Source.fail("bundle: invalid collision box shape")
		for axis: int in 3:
			if not Source.integer(box.min[axis]) or not Source.integer(box.size[axis]) or box.min[axis]<0 or box.size[axis]<1 or box.min[axis]+box.size[axis]>16:return Source.fail("bundle: collision box outside editing bounds")
	return {"success":true,"reason":""}

static func mesh(bundle: Dictionary) -> ArrayMesh:
	var vertices: PackedVector3Array = []; var normals: PackedVector3Array = []; var colors: PackedColorArray = []
	for index: int in bundle.vertices.size():
		var p: Array = bundle.vertices[index]; var n: Array = bundle.normals[index]
		vertices.append(Vector3(p[0],p[1],p[2])/float(bundle.voxels_per_metre)); normals.append(Vector3(n[0],n[1],n[2])); colors.append(Color(bundle.colors[index]))
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_COLOR]=colors; arrays[Mesh.ARRAY_INDEX]=PackedInt32Array(bundle.indices)
	var result: ArrayMesh = ArrayMesh.new()
	if not vertices.is_empty(): result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

static func material() -> StandardMaterial3D:
	var value: StandardMaterial3D = StandardMaterial3D.new(); value.vertex_color_use_as_albedo=true; value.vertex_color_is_srgb=true; value.roughness=0.9
	return value

static func body(bundle: Dictionary) -> StaticBody3D:
	var value: StaticBody3D = StaticBody3D.new()
	for box: Dictionary in bundle.collision_boxes:
		var minimum: Vector3 = Vector3(box.min[0],box.min[1],box.min[2])/float(bundle.voxels_per_metre)
		var extent: Vector3 = Vector3(box.size[0],box.size[1],box.size[2])/float(bundle.voxels_per_metre)
		var shape: CollisionShape3D = CollisionShape3D.new(); shape.shape=BoxShape3D.new(); shape.shape.size=extent; shape.position=minimum+extent/2; value.add_child(shape)
	return value
