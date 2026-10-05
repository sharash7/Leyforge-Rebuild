class_name LeyforgeMovementRules
extends RefCounted

# Canonical Leyforge tuning for local, predicted and authoritative remote bodies.
const WALK_SPEED: float = 5.0
const SPRINT_SPEED: float = 8.5
const GROUND_ACCELERATION: float = 24.0
const AIR_ACCELERATION: float = 8.0
const DECELERATION: float = 30.0
const JUMP_VELOCITY: float = 6.25

static func step(body: CharacterBody3D, movement: Vector2, jump: bool, sprint: bool, gravity: float, delta: float) -> float:
	if not body.is_on_floor():
		body.velocity.y -= gravity * delta
	elif jump:
		body.velocity.y = JUMP_VELOCITY
	var direction: Vector3 = (body.transform.basis * Vector3(movement.x, 0.0, movement.y)).normalized()
	var speed: float = SPRINT_SPEED if sprint else WALK_SPEED
	var acceleration: float = GROUND_ACCELERATION if body.is_on_floor() else AIR_ACCELERATION
	if direction != Vector3.ZERO:
		body.velocity.x = move_toward(body.velocity.x, direction.x * speed, acceleration * delta)
		body.velocity.z = move_toward(body.velocity.z, direction.z * speed, acceleration * delta)
	else:
		body.velocity.x = move_toward(body.velocity.x, 0.0, DECELERATION * delta)
		body.velocity.z = move_toward(body.velocity.z, 0.0, DECELERATION * delta)
	var fall_speed: float = -body.velocity.y
	var airborne: bool = not body.is_on_floor()
	body.move_and_slide()
	return fall_speed if airborne and body.is_on_floor() else 0.0