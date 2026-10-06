class_name LeyforgeResourcePresenter
extends Node3D

var _world: LeyforgeWave1Playground
var _nodes: Dictionary = {}
var _crates: Dictionary = {}
var _cooldowns: Dictionary = {}
var _animation: float = 0.0
# JOIN visuals follow complete HOST targets; authoritative pickup uses record positions.
const DROP_SNAP_DISTANCE: float = 0.75
const DROP_FOLLOW_SPEED: float = 12.0
var _drop_targets: Dictionary = {}

func configure(world: LeyforgeWave1Playground) -> void:
	_world=world
	sync()

func delay_pickup(id: String) -> void:
	_cooldowns[id]=Time.get_ticks_msec()+1200

func sync() -> void:
	if _world==null:
		return
	var seen: Dictionary = {}
	for entry: Dictionary in _world.world_resources.drops():
		var id: String = entry["instance"]
		var position: Vector3 = _position(entry)
		if not _world.region_relevant(position):
			continue
		seen[id]=true
		if not _nodes.has(id):
			_nodes[id]=_make_drop(entry)
		_drop_targets[id]=position
		if _world.authority != null or _nodes[id].position.distance_to(position) > DROP_SNAP_DISTANCE:
			_nodes[id].position=position
		var label: Label3D = _nodes[id].get_node("Quantity")
		label.text="%s x%d" % [_world.block_catalog.content_definition(StringName(entry["stack"]["content"]))["display_name"],int(entry["stack"]["quantity"])]
		label.visible=(_world.player.global_position+Vector3.UP).distance_to(position)<3
	for id: String in _nodes.keys():
		if not seen.has(id):
			_nodes[id].hide()
			_nodes[id].queue_free()
			_nodes.erase(id)
			_drop_targets.erase(id)
	# Cooldowns survive dematerialisation, but disappear with picked-up records.
	for id: String in _cooldowns.keys():
		if _world.world_resources.drop(id).is_empty():
			_cooldowns.erase(id)
	seen.clear()
	for entry: Dictionary in _world.world_resources.snapshot()["storage"]:
		if not _world.region_relevant(_position(entry)):
			continue
		seen[entry["instance"]]=true
		if not _crates.has(entry["instance"]):
			_crates[entry["instance"]]=_make_crate(entry)
	for id: String in _crates.keys():
		if not seen.has(id):
			_crates[id].queue_free()
			_crates.erase(id)

func _process(delta: float) -> void:
	_animation+=delta
	for id: String in _nodes:
		if _world.authority == null:
			var target: Vector3 = _drop_targets[id]
			_nodes[id].position = _nodes[id].position.lerp(target,1.0-exp(-DROP_FOLLOW_SPEED*delta))
			if _nodes[id].position.distance_to(target)<0.001: _nodes[id].position=target
		var phase: float = float(String(id).substr(0,6).hex_to_int()%1000)/1000.0*TAU
		var visual: MeshInstance3D = _nodes[id].get_node("Visual")
		visual.position.y=sin(_animation*1.7+phase)*0.02
		visual.rotation.y=_animation*0.45+phase

func _physics_process(delta: float) -> void:
	if _world != null and _world._host_closing: return
	if _world==null or not _world.is_runtime_ready():
		return
	if _world.authority != null and not OS.get_cmdline_user_args().has("--wave4-playtest") and not OS.get_cmdline_user_args().has("--wave3-playtest"):
		# Rendered conservation drivers advance clustering explicitly for exact restart assertions.
		_world.world_resources.advance_drop_clusters(minf(delta,1),_world.region_relevant,_world.drop_path_clear,_world.drop_rest_position)
	if _world.player.is_runtime_ready():
		for entry: Dictionary in _world.world_resources.drops():
			var id: String = entry["instance"]
			if not _nodes.has(id) or Time.get_ticks_msec()<int(_cooldowns.get(id,0)):
				continue
			if (_world.player.global_position+Vector3.UP*0.8).distance_to(_position(entry))<=1.65:
				if _world.resource_network != null and _world.resource_network.replica != null and not _world.resource_network.pending.is_empty(): continue
				var accepted: int = int(_world.command(_world.local_player_id,"pickup",{"target":id}).data.get("quantity",0))
				if accepted>0:
					_world.player.show_status("Picked up %d" % accepted)
	sync()

func _position(entry: Dictionary) -> Vector3:
	var p: Array = entry["position"]
	return Vector3(float(p[0]),float(p[1]),float(p[2]))

func _make_drop(entry: Dictionary) -> Node3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name="Drop_"+entry["instance"]
	body.collision_layer=2
	body.collision_mask=0
	body.position=_position(entry)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size=Vector3.ONE*0.25
	collision.shape=shape
	body.add_child(collision)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name="Visual"
	var cube: BoxMesh = BoxMesh.new()
	cube.size=shape.size
	mesh.mesh=cube
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color=Color.from_string(_world.block_catalog.content_definition(StringName(entry["stack"]["content"])).get("color","#FFCC88"),Color.WHITE)
	mesh.material_override=material
	body.add_child(mesh)
	var label: Label3D = Label3D.new()
	label.name="Quantity"
	label.position.y=0.45
	label.font_size=20
	label.pixel_size=0.004
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	body.add_child(label)
	add_child(body)
	return body

func _make_crate(entry: Dictionary) -> Node3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name="StorageCrate"
	body.position=_position(entry)
	body.collision_layer=8
	body.collision_mask=0
	body.set_meta("crate",entry["instance"])
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size=Vector3.ONE*0.8
	collision.shape=shape
	body.add_child(collision)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var cube: BoxMesh = BoxMesh.new()
	cube.size=shape.size
	mesh.mesh=cube
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color=Color.from_string(_world.world_resources.storage_definition()["color"],Color.SADDLE_BROWN)
	mesh.material_override=material
	body.add_child(mesh)
	add_child(body)
	return body
