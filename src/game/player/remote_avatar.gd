class_name LeyforgeRemoteAvatar
extends Node3D

const BUFFER_LIMIT: int = 8
const INTERPOLATION_TICKS: float = 6.0 # 100 ms at the 60 Hz physics baseline.
var samples: Array[Dictionary] = []
var cursor: float = 0.0

func build(player_id: String) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color.from_hsv(float(player_id.left(4).hex_to_int() % 360) / 360.0,0.55,0.85)
	for part: Array in [
		[Vector3(0,1.55,0),Vector3(0.42,0.42,0.42)],
		[Vector3(0,1.02,0),Vector3(0.56,0.65,0.28)],
		[Vector3(-0.39,1.0,0),Vector3(0.20,0.65,0.24)],
		[Vector3(0.39,1.0,0),Vector3(0.20,0.65,0.24)],
		[Vector3(-0.16,0.35,0),Vector3(0.23,0.70,0.26)],
		[Vector3(0.16,0.35,0),Vector3(0.23,0.70,0.26)]
	]:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = part[1]
		mesh.mesh = box
		mesh.material_override = material
		mesh.position = part[0]
		add_child(mesh)
	var label: Label3D = Label3D.new()
	label.text = player_id.left(8)
	label.position.y = 2.1
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	label.pixel_size = 0.008
	add_child(label)

func push(state: Dictionary, tick: int) -> void:
	if not samples.is_empty() and tick <= int(samples.back()["tick"]): return
	samples.append({"tick":tick,"position":LfeMovementProtocol.vec3(state["position"]),"yaw":float(state["yaw"])})
	if samples.size() == 1:
		global_position = samples[0]["position"]
		rotation.y = samples[0]["yaw"]
		cursor = float(tick) - INTERPOLATION_TICKS
	while samples.size() > BUFFER_LIMIT: samples.pop_front()

func _process(delta: float) -> void:
	if samples.is_empty(): return
	var latest: float = float(samples.back()["tick"])
	cursor = minf(latest,maxf(cursor + delta * 60.0,latest - INTERPOLATION_TICKS))
	while samples.size() > 2 and float(samples[1]["tick"]) <= cursor: samples.pop_front()
	var a: Dictionary = samples[0]
	var b: Dictionary = samples[1] if samples.size() > 1 else a
	var weight: float = clampf((cursor - float(a["tick"])) / maxf(1,float(b["tick"]) - float(a["tick"])),0,1)
	global_position = a["position"].lerp(b["position"],weight)
	rotation.y = lerp_angle(float(a["yaw"]),float(b["yaw"]),weight)