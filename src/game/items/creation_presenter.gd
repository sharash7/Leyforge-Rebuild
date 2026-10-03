class_name LeyforgeCreationPresenter
extends Node3D

var _world: LeyforgeWave1Playground
var _nodes: Dictionary = {}

func configure(world: LeyforgeWave1Playground) -> void:
	_world = world
	sync()

func sync() -> void:
	if _world == null:
		return
	var seen: Dictionary = {}
	for entry: Dictionary in _world.creation.sources():
		if int(entry["remaining"]) <= 0:
			continue
		var spec: Dictionary = _world.creation.source_definition(entry["source"])
		seen[entry["instance"]] = true
		if not _nodes.has(entry["instance"]):
			var p: Array = entry["position"]
			var node: Node3D = _marker(Vector3(float(p[0]),float(p[1]),float(p[2])),spec["display_name"] + " [E]",Color.from_string(spec["color"],Color.WHITE),true)
			_nodes[entry["instance"]] = node
	for entry: Dictionary in _world.creation.objects():
		seen[entry["instance"]] = true
		if not _nodes.has(entry["instance"]):
			var p: Array = entry["cell"]
			var definition: Dictionary = _world.block_catalog.content_definition(StringName(entry["content"]))
			var node: Node3D = _marker(Vector3(float(p[0])+0.5,float(p[1])+0.9,float(p[2])+0.5),definition["display_name"] + " [E]",Color.WHITE,false)
			node.rotation.y = int(entry["orientation"]) * PI / 2.0
			if definition.get("function") == "light":
				var light: OmniLight3D = OmniLight3D.new()
				light.omni_range = 7.0
				light.light_color = Color(1,0.76,0.4)
				light.light_energy = 1.8
				node.add_child(light)
			_nodes[entry["instance"]] = node
	for id: String in _nodes.keys():
		if not seen.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)

func _marker(position: Vector3, title: String, color: Color, source: bool) -> Node3D:
	var node: Node3D = Node3D.new()
	node.position = position
	if source:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var cube: BoxMesh = BoxMesh.new()
		cube.size = Vector3(0.75,0.65,0.75)
		mesh.mesh = cube
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		mesh.material_override = material
		node.add_child(mesh)
	var label: Label3D = Label3D.new()
	label.text = title
	label.position.y = 0.7
	label.font_size = 24
	label.pixel_size = 0.007
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.add_child(label)
	add_child(node)
	return node
