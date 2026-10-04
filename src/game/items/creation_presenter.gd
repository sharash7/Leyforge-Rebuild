class_name LeyforgeCreationPresenter
extends Node3D

var _world: LeyforgeWave1Playground
var _nodes: Dictionary = {}

func configure(world: LeyforgeWave1Playground) -> void:
	_world=world
	sync()

func sync() -> void:
	if _world==null:
		return
	var seen: Dictionary = {}
	for entry: Dictionary in _world.creation.sources():
		var p: Array = entry["position"]
		var position: Vector3 = Vector3(float(p[0]),float(p[1]),float(p[2]))
		if int(entry["remaining"])<=0 or not _world.region_relevant(position):
			continue
		var id: String = entry["instance"]
		seen[id]=true
		if not _nodes.has(id):
			_nodes[id]=_source(entry)
	for entry: Dictionary in _world.creation.objects():
		var p: Array = entry["cell"]
		var position: Vector3 = Vector3(float(p[0])+0.5,float(p[1])+0.5,float(p[2])+0.5)
		if not _world.region_relevant(position):
			continue
		var id: String = entry["instance"]
		seen[id]=true
		if not _nodes.has(id):
			var node: Node3D = Node3D.new()
			node.position=position
			node.rotation.y=int(entry["orientation"])*PI/2.0
			if _world.block_catalog.content_definition(StringName(entry["content"])).get("function")=="light":
				var light: OmniLight3D = OmniLight3D.new()
				light.omni_range=7
				light.light_color=Color(1,0.76,0.4)
				light.light_energy=1.8
				node.add_child(light)
			add_child(node)
			_nodes[id]=node
	for id: String in _nodes.keys():
		if not seen.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)

func _source(entry: Dictionary) -> Node3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name="Source_"+entry["instance"]
	body.collision_layer=8
	body.collision_mask=0
	body.set_meta("source",entry["instance"])
	var p: Array = entry["position"]
	# Source coordinates stay unchanged in old saves. Geometry rests on the cell floor.
	body.position=Vector3(float(p[0]),floorf(float(p[1])),float(p[2]))
	var spec: Dictionary = _world.creation.source_definition(entry["source"])
	var color: Color = Color.from_string(spec["color"],Color.WHITE)
	var size: Vector3 = Vector3(0.65,0.55,0.65)
	var center: Vector3 = Vector3(0,0.275,0)
	if entry["source"]=="fallen_oak":
		var visual: Dictionary = {"log_color":_world.block_catalog.content_definition(StringName(spec["content"]))["color"],"leaf_color":_world.block_catalog.definition_for_id(&"leyforge:oak_leaves")["color"]}
		var variant: int = String(entry["instance"]).substr(0,8).hex_to_int()%3
		var height: int = 2+variant
		var bark: Color = Color.from_string(visual["log_color"],color)
		var leaves: Color = Color.from_string(visual["leaf_color"],Color.FOREST_GREEN)
		body.set_meta("tree_variant",variant)
		body.set_meta("trunk_height",height)
		size=Vector3(1,height,1);center=Vector3(0,height/2.0,0)
		for level: int in height:
			_box(body,Vector3(0,level+0.5,0),Vector3.ONE,bark.lightened(level*0.025))
		# Visual-only foliage owns no second timber identity or resource output.
		for level: int in 2:
			for x: int in range(-1,2):
				for z: int in range(-1,2):
					if level==0 and x==0 and z==0:continue
					if variant==1 and abs(x)+abs(z)==2 and level==1:continue
					_box(body,Vector3(x,height-0.5+level,z),Vector3.ONE,leaves.lightened((x+z+2)*0.025))
		_box(body,Vector3(0,height+1.5,0),Vector3.ONE,leaves.lightened(0.12))
	elif entry["source"]=="dense_stone":
		size=Vector3(1.35,0.8,1.05);center=Vector3(0,0.4,0)
		_box(body,Vector3(-0.32,0.3,0),Vector3(0.7,0.6,0.85),color)
		_box(body,Vector3(0.34,0.4,0.12),Vector3(0.65,0.8,0.8),color.lightened(0.1))
	else:
		_box(body,center,size,color)
		_box(body,Vector3(0,0.57,0),Vector3(0.7,0.06,0.7),color.darkened(0.25))
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size=size
	collision.shape=shape
	collision.position=center
	body.add_child(collision)
	body.set_meta("highlight_center",center)
	body.set_meta("highlight_size",size)
	add_child(body)
	return body

func _box(parent: Node3D, position: Vector3, size: Vector3, color: Color) -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var cube: BoxMesh = BoxMesh.new()
	cube.size=size
	mesh.mesh=cube
	mesh.position=position
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color=color
	mesh.material_override=material
	parent.add_child(mesh)
