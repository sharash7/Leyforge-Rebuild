extends RefCounted
## Slab clip then integer-grid DDA. Ties advance X, then Y, then Z.
const Source = preload("res://src/lfe/content/voxel_asset.gd")
const EPS = 0.0000001

static func ray(origin: Vector3, direction: Vector3, occupied: Dictionary) -> Dictionary:
	if direction.length_squared()<EPS: return {"hit":false}
	var entry: float = -INF; var exit: float = INF; var normal: Vector3i = Vector3i.ZERO
	for axis: int in 3:
		if abs(direction[axis])<EPS:
			if origin[axis]<0 or origin[axis]>1: return {"hit":false}
			continue
		var near_t: float = (0.0-origin[axis])/direction[axis]; var far_t: float = (1.0-origin[axis])/direction[axis]
		if near_t>far_t: var swap: float = near_t; near_t=far_t; far_t=swap
		if near_t>entry+EPS:
			entry=near_t; normal=Vector3i.ZERO; normal[axis]=-1 if direction[axis]>0 else 1
		exit=minf(exit,far_t)
	if exit<maxf(entry,0): return {"hit":false}
	var t: float = maxf(entry,0); var start: Vector3 = (origin+direction*(t+EPS))*16
	var cell: Vector3i = Vector3i(floor(start.x),floor(start.y),floor(start.z))
	# Origin on the closed outer face must step inward, never wrap/clamp edit targets.
	var step: Vector3i = Vector3i(sign(direction.x),sign(direction.y),sign(direction.z))
	var next: Vector3 = Vector3(INF,INF,INF); var delta: Vector3 = Vector3(INF,INF,INF)
	for axis: int in 3:
		if step[axis]==0: continue
		delta[axis]=abs(1.0/(16.0*direction[axis]))
		var boundary: float = float(cell[axis]+(1 if step[axis]>0 else 0))/16.0
		next[axis]=(boundary-origin[axis])/direction[axis]
	for iteration: int in 52:
		var position: Array = [cell.x,cell.y,cell.z]
		if not Source.inside(position) or t>exit+EPS: break
		if occupied.has(Source.key(position)):
			if iteration==0 and entry<0:
				var face: int=0
				if next.y<next.x-EPS:face=1
				if next.z<next[face]-EPS:face=2
				normal=Vector3i.ZERO;normal[face]=step[face]
			return {"hit":true,"cell":position,"normal":[normal.x,normal.y,normal.z],"t":t}
		var axis: int = 0
		if next.y<next.x-EPS: axis=1
		if next.z<next[axis]-EPS: axis=2
		t=next[axis]; next[axis]+=delta[axis]; cell[axis]+=step[axis]; normal=Vector3i.ZERO; normal[axis]=-step[axis]
	return {"hit":false}

static func plane(origin: Vector3, direction: Vector3, axis: int, index: int) -> Dictionary:
	if axis<0 or axis>2 or index<0 or index>=16 or abs(direction[axis])<EPS: return {"valid":false,"cell":[]}
	var t: float = (float(index)/16.0-origin[axis])/direction[axis]
	if t<0: return {"valid":false,"cell":[]}
	var point: Vector3 = (origin+direction*t)*16.0
	var cell: Array = [int(floor(point.x+EPS)),int(floor(point.y+EPS)),int(floor(point.z+EPS))]; cell[axis]=index
	return {"valid":Source.inside(cell),"cell":cell}

static func target(origin: Vector3, direction: Vector3, occupied: Dictionary, tool: String, axis: int, index: int) -> Dictionary:
	var hit: Dictionary = ray(origin,direction,occupied)
	if hit.hit:
		var cell: Array = hit.cell.duplicate()
		if tool=="Place":
			for n: int in 3: cell[n]+=hit.normal[n]
		return {"valid":Source.inside(cell) and (tool!="Place" or not occupied.has(Source.key(cell))),"cell":cell,"hit":hit}
	var result: Dictionary = plane(origin,direction,axis,index)
	result.valid=result.valid and tool in ["Place","Select"]
	return result

static func segment(a: Array, b: Array) -> Array:
	# Supercover segment between cell centres, with the same X/Y/Z tie order.
	var current: Vector3i = Vector3i(a[0],a[1],a[2]); var end: Vector3i = Vector3i(b[0],b[1],b[2]); var result: Array = [a.duplicate()]
	var direction: Vector3 = Vector3(end-current); var step: Vector3i = Vector3i(sign(direction.x),sign(direction.y),sign(direction.z))
	var delta: Vector3 = Vector3(INF,INF,INF); var next: Vector3 = Vector3(INF,INF,INF)
	for axis: int in 3:
		if step[axis]!=0: delta[axis]=abs(1.0/direction[axis]); next[axis]=delta[axis]/2
	while current!=end and result.size()<49:
		var axis: int = 0
		if next.y<next.x-EPS: axis=1
		if next.z<next[axis]-EPS: axis=2
		current[axis]+=step[axis]; next[axis]+=delta[axis]; result.append([current.x,current.y,current.z])
	return result

static func box(a: Array, b: Array) -> Array:
	if not Source.inside(a) or not Source.inside(b): return []
	var result: Array = []
	for x: int in range(mini(a[0],b[0]),maxi(a[0],b[0])+1):
		for y: int in range(mini(a[1],b[1]),maxi(a[1],b[1])+1):
			for z: int in range(mini(a[2],b[2]),maxi(a[2],b[2])+1): result.append([x,y,z])
	return result
