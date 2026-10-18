extends RefCounted
## Integer corners, flat normals, clockwise faces. No terrain/plugin dependency.
const Source = preload("res://src/lfe/content/voxel_asset.gd")
const VERSION = 1
const DIRECTIONS = [[-1,0,0],[1,0,0],[0,-1,0],[0,1,0],[0,0,-1],[0,0,1]]
# Outward cross product reversed by triangle indices for Godot clockwise fronts.
const CORNERS = [
	[[0,0,0],[0,0,1],[0,1,1],[0,1,0]],
	[[1,0,1],[1,0,0],[1,1,0],[1,1,1]],
	[[0,0,1],[0,0,0],[1,0,0],[1,0,1]],
	[[0,1,0],[0,1,1],[1,1,1],[1,1,0]],
	[[1,0,0],[0,0,0],[0,1,0],[1,1,0]],
	[[0,0,1],[1,0,1],[1,1,1],[0,1,1]]]

static func compile(data: Dictionary, resolved: Dictionary, source_hash: String) -> Dictionary:
	var checked: Dictionary = Source.check(data, "", true)
	if not checked.success: return checked
	if not resolved.get("success", false): return Source.fail("resolved dependencies required")
	data = checked.value
	var occupied: Dictionary = Source.occupancy(data)
	var vertices: Array = []; var normals: Array = []; var colors: Array = []; var indices: Array = []
	for cell: Array in data.cells:
		for face: int in 6:
			var direction: Array = DIRECTIONS[face]
			if occupied.has(Source.key([cell[0]+direction[0],cell[1]+direction[1],cell[2]+direction[2]])): continue
			var start: int = vertices.size()
			for corner: Array in CORNERS[face]:
				vertices.append([int(cell[0])+corner[0],int(cell[1])+corner[1],int(cell[2])+corner[2]])
				normals.append(direction.duplicate()); colors.append(resolved.colors[cell[3]])
			for index: int in [0,2,1,0,3,2]: indices.append(start+index)
	var boxes: Array = collision_boxes(data)
	var bounds_min: Array = [16,16,16]; var bounds_max: Array = [0,0,0]
	for cell: Array in data.cells:
		for axis: int in 3:
			bounds_min[axis] = mini(bounds_min[axis], int(cell[axis])); bounds_max[axis] = maxi(bounds_max[axis], int(cell[axis])+1)
	var identity: Dictionary = {"source_hash":source_hash,"dependencies":resolved.dependencies,"compiler_version":VERSION,"artifact_version":1,"options":{"collision":"occupied_boxes"}}
	var framed: String = ""
	for part: String in [source_hash, Source.bytes(resolved.dependencies), str(VERSION), "1", Source.bytes(identity.options)]: framed += str(part.to_utf8_buffer().size()) + ":" + part
	return {"success":true,"reason":"","bundle":{"artifact_version":1,"compiler_version":VERSION,"bake_key":framed.sha256_text(),"id":data.id,"asset_version":data.asset_version,"source_hash":source_hash,"dependencies":resolved.dependencies,"dimensions":data.dimensions,"voxels_per_metre":data.voxels_per_metre,"origin":data.origin,"occupied_min":bounds_min,"occupied_max":bounds_max,"vertices":vertices,"normals":normals,"colors":colors,"indices":indices,"collision_boxes":boxes}}

static func collision_boxes(data: Dictionary) -> Array:
	var remaining: Dictionary = Source.occupancy(data); var boxes: Array = []
	for cell: Array in Source.canonical(data).cells:
		if not remaining.has(Source.key(cell)): continue
		var start: Vector3i = Vector3i(cell[0],cell[1],cell[2]); var extent: Vector3i = Vector3i.ONE
		for axis: int in 3:
			while start[axis]+extent[axis] < int(data.dimensions[axis]):
				var valid: bool = true
				var slab: Vector3i = extent; slab[axis] = 1
				var offset: Vector3i = start; offset[axis] += extent[axis]
				for x: int in slab.x:
					for y: int in slab.y:
						for z: int in slab.z:
							if not remaining.has(Source.key([offset.x+x,offset.y+y,offset.z+z])): valid = false
				if not valid: break
				extent[axis] += 1
		for x: int in extent.x:
			for y: int in extent.y:
				for z: int in extent.z: remaining.erase(Source.key([start.x+x,start.y+y,start.z+z]))
		boxes.append({"min":[start.x,start.y,start.z],"size":[extent.x,extent.y,extent.z]})
	return boxes
