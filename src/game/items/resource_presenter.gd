class_name LeyforgeResourcePresenter
extends Node3D

var _world: LeyforgeWave1Playground
var _nodes: Dictionary = {}
var _cooldowns: Dictionary = {}


func configure(world: LeyforgeWave1Playground) -> void:
	_world = world
	sync()


func delay_pickup(id: String) -> void:
	_cooldowns[id] = Time.get_ticks_msec() + 1200


func sync() -> void:
	if _world == null:
		return
	var seen: Dictionary = {}
	for entry: Dictionary in _world.resources.drops():
		var id: String = entry["instance"]
		seen[id] = true
		if not _nodes.has(id):
			_nodes[id] = _make_drop(entry)
		var label: Label3D = _nodes[id].get_node("Quantity")
		label.text = "%s ×%d" % [_world.block_catalog.content_definition(StringName(entry["stack"]["content"]))["display_name"], int(entry["stack"]["quantity"])]
	for id: String in _nodes.keys():
		if not seen.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)
			_cooldowns.erase(id)


func _physics_process(_delta: float) -> void:
	if _world == null or not _world.is_runtime_ready() or not _world.player.is_runtime_ready():
		return
	for entry: Dictionary in _world.resources.drops():
		var id: String = entry["instance"]
		if Time.get_ticks_msec() < int(_cooldowns.get(id, 0)):
			continue
		var coordinates: Array = entry["position"]
		var position: Vector3 = Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
		if (_world.player.global_position + Vector3.UP * 0.8).distance_to(position) <= 1.65:
			var accepted: int = _world.resources.pickup(id)
			if accepted > 0:
				_world.player.show_status("Picked up %d %s" % [accepted, _world.block_catalog.content_definition(StringName(entry["stack"]["content"]))["display_name"]])
	sync()


func _make_drop(entry: Dictionary) -> Node3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Drop_" + String(entry["instance"])
	# Presence is anchored and independent of streamed terrain collision. A small
	# persistent cube can be approached from either side; no unloaded-floor fall.
	body.collision_layer = 2
	body.collision_mask = 0
	var coordinates: Array = entry["position"]
	body.position = Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3.ONE * 0.25
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var cube: BoxMesh = BoxMesh.new()
	cube.size = shape.size
	mesh.mesh = cube
	var material: StandardMaterial3D = StandardMaterial3D.new()
	var definition: Dictionary = _world.block_catalog.content_definition(StringName(entry["stack"]["content"]))
	material.albedo_color = Color.from_string(definition.get("color", "#FFCC88"), Color.WHITE)
	mesh.material_override = material
	body.add_child(mesh)
	var label: Label3D = Label3D.new()
	label.name = "Quantity"
	label.position.y = 0.4
	label.font_size = 32
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	body.add_child(label)
	add_child(body)
	return body


func build_crate(entry: Dictionary) -> void:
	var crate: StaticBody3D = StaticBody3D.new()
	crate.name = "StorageCrate"
	crate.collision_layer = 2
	crate.collision_mask = 0
	var coordinates: Array = entry["position"]
	crate.position = Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(0.8, 0.8, 0.8)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	crate.add_child(collision)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var cube: BoxMesh = BoxMesh.new()
	cube.size = shape.size
	mesh.mesh = cube
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color.from_string(_world.resources.storage_definition()["color"], Color.SADDLE_BROWN)
	mesh.material_override = material
	crate.add_child(mesh)
	var label: Label3D = Label3D.new()
	label.text = "Storage crate [E]"
	label.position.y = 0.7
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	crate.add_child(label)
	add_child(crate)
