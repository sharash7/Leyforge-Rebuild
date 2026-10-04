class_name LfeStarterTreeRules
extends RefCounted

# Frozen worldgen-v2 decoration rules. Each cell owns at most one tree.
const SPACING: int = 10
const RADIUS: int = 2
const MAX_TOP: int = LfeWave1TerrainRules.MAX_HEIGHT + 8

static func candidate(seed: int, cell: Vector2i) -> Dictionary:
	var h: int = LfeWave1TerrainRules._mix(LfeWave1TerrainRules._mix(seed ^ 0x51A73,cell.x),cell.y)
	if h%4==0:return {}
	var x: int = cell.x*SPACING+2+(h>>3)%6
	var z: int = cell.y*SPACING+2+(h>>9)%6
	var ground: int = LfeWave1TerrainRules.height_at(seed,x,z)
	if LfeWave1TerrainRules.surface_material_at(seed,x,z,ground)!=LfeWave1TerrainRules.MaterialLayer.GRASS:return {}
	# Keep the low canopy clear of neighbouring sloped terrain.
	for dx: int in range(-RADIUS,RADIUS+1):
		for dz: int in range(-RADIUS,RADIUS+1):
			var adjacent: int = LfeWave1TerrainRules.height_at(seed,x+dx,z+dz)
			if adjacent>ground+1 or (abs(dx)<=1 and abs(dz)<=1 and adjacent>ground):return {}
	return {"base":Vector3i(x,ground+1,z),"height":4+(h>>15)%3,"radius":1+(h>>19)%2,"variant":h%3}

static func candidates(seed: int, minimum: Vector2i, maximum: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var lo: Vector2i = Vector2i(floori(float(minimum.x-RADIUS)/SPACING),floori(float(minimum.y-RADIUS)/SPACING))
	var hi: Vector2i = Vector2i(floori(float(maximum.x+RADIUS)/SPACING),floori(float(maximum.y+RADIUS)/SPACING))
	for z: int in range(lo.y,hi.y+1):
		for x: int in range(lo.x,hi.x+1):
			var tree: Dictionary = candidate(seed,Vector2i(x,z))
			if tree.is_empty():continue
			var base: Vector3i = tree["base"];var radius: int = tree["radius"]
			if base.x+radius<minimum.x or base.x-radius>maximum.x or base.z+radius<minimum.y or base.z-radius>maximum.y:continue
			result.append(tree)
	return result

# Values are projections: 1 = canonical Heartwood, 2 = canonical Oak Leaves.
static func cells(tree: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var base: Vector3i = tree["base"];var height: int = tree["height"];var radius: int = tree["radius"]
	for y: int in height:result[base+Vector3i(0,y,0)]=1
	for y: int in range(height-2,height+1):
		var width: int = radius if y<height else 1
		for z: int in range(-width,width+1):
			for x: int in range(-width,width+1):
				if x==0 and z==0 and y<height:continue
				if abs(x)==width and abs(z)==width and (tree["variant"]==1 or width==2):continue
				result[base+Vector3i(x,y,z)]=2
	result[base+Vector3i(0,height+1,0)]=2
	return result

static func material_at(seed: int, position: Vector3i) -> int:
	if position.y<=LfeWave1TerrainRules.MIN_HEIGHT or position.y>MAX_TOP:return 0
	for tree: Dictionary in candidates(seed,Vector2i(position.x,position.z),Vector2i(position.x,position.z)):
		var value: int = int(cells(tree).get(position,0))
		if value!=0:return value
	return 0
