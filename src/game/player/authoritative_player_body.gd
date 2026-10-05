class_name LeyforgeAuthoritativePlayerBody
extends CharacterBody3D

var record: LfePlayerCharacter
var viewer: VoxelViewer
var avatar: LeyforgeRemoteAvatar
var ready_for_movement: bool = false
var pitch: float = 0.0
var accepted_sequence: int = 0
var processed_sequence: int = 0
var input_age: float = 1.0
var intent: Dictionary = {}
var jump_pending: bool = false
var gravity: float = 9.8

func build(character: LfePlayerCharacter) -> void:
	record = character
	collision_layer = LfeVoxelInteractionRules.PLAYER_BODY_LAYER
	collision_mask = LfeVoxelInteractionRules.PLAYER_PHYSICAL_MASK
	floor_snap_length = 0.25
	floor_max_angle = deg_to_rad(50.0)
	safe_margin = 0.03
	gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity",9.8))
	var shape: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = LfeVoxelInteractionRules.PLAYER_RADIUS
	capsule.height = LfeVoxelInteractionRules.PLAYER_HEIGHT
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	viewer = VoxelViewer.new()
	viewer.name = "AuthoritativeTerrainInterest"
	viewer.view_distance = 80
	viewer.view_distance_vertical_ratio = 0.5
	viewer.requires_collisions = true
	viewer.position.y = 1.62
	add_child(viewer)
	avatar = LeyforgeRemoteAvatar.new()
	avatar.set_process(false)
	add_child(avatar)
	avatar.build(character.player_id)
	position = LfeMovementProtocol.vec3(record.transform["position"])
	rotation.y = wrapf(float(record.transform["yaw"]),-PI,PI)
	pitch = float(record.transform["pitch"])

func accept_input(packet: Dictionary) -> bool:
	if not LfeMovementProtocol.valid_input(packet) or not LfeMovementProtocol.fresh(packet["sequence"],accepted_sequence): return false
	accepted_sequence = int(packet["sequence"])
	intent = packet
	# Latch an edge across two 30 Hz packets, then consume exactly once in physics.
	jump_pending = jump_pending or bool(packet["jump_pressed"])
	input_age = 0.0
	return true

func simulate(delta: float) -> void:
	if not ready_for_movement: return
	input_age += delta
	var movement: Vector2 = Vector2.ZERO
	var sprint: bool = false
	var jump: bool = false
	if not intent.is_empty():
		rotation.y = float(intent["yaw"])
		pitch = clampf(float(intent["pitch"]),-LfeMovementProtocol.MAX_PITCH,LfeMovementProtocol.MAX_PITCH)
		processed_sequence = accepted_sequence
		if input_age <= LfeMovementProtocol.INPUT_HOLD_SECONDS:
			movement = Vector2(float(intent["move_x"]),float(intent["move_z"]))
			sprint = bool(intent["sprint_requested"]) and record.survival.alive() and float(record.survival.snapshot()["stamina"]) >= 1 and float(record.survival.snapshot()["fatigue"]) < 100
			jump = jump_pending
	jump_pending = false
	LeyforgeMovementRules.step(self,movement,jump,sprint,gravity,delta)
	sync_record()

func sync_record() -> void:
	record.transform = {"position":LfeMovementProtocol.array3(global_position),"yaw":rotation.y,"pitch":pitch,"selected_block":record.transform.get("selected_block","")}

func state() -> Dictionary:
	return {"player_id":record.player_id,"position":LfeMovementProtocol.array3(global_position),"velocity":LfeMovementProtocol.array3(velocity),"yaw":wrapf(rotation.y,-PI,PI),"pitch":pitch,"grounded":is_on_floor(),"ack":processed_sequence}