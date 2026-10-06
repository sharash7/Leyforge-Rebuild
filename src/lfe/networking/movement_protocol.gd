class_name LfeMovementProtocol
extends RefCounted

# JSON is isolated here. No Variant/Object decoding is used.
const MAX_BYTES: int = 8192
const MAX_PLAYERS: int = 8
const MAX_SEQUENCE: int = 2147483647
const MAX_SEQUENCE_ADVANCE: int = 1024
const MAX_PITCH: float = deg_to_rad(89.0)
const ANGLE_EPSILON: float = 0.000001 # Node3D Euler angles round through float32 Vector3.
const INPUT_CHANNEL: int = 1
const SNAPSHOT_CHANNEL: int = 2
const PRESENCE_CHANNEL: int = 3
const INPUT_HZ: float = 30.0
const SNAPSHOT_HZ: float = 20.0
const INPUT_HOLD_SECONDS: float = 0.25
const INPUT_KEYS: Array = ["kind","sequence","input_epoch","move_x","move_z","jump_pressed","sprint_requested","yaw","pitch"]
const STATE_KEYS: Array = ["player_id","position","velocity","yaw","pitch","grounded","ack"]

static func finite(value: Variant, bound: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= bound

static func integer(value: Variant, minimum: int = 0) -> bool:
	return finite(value, MAX_SEQUENCE) and float(value) == floor(float(value)) and float(value) >= minimum

static func fresh(sequence: Variant, last: int) -> bool:
	return integer(sequence, 1) and int(sequence) > last and int(sequence) - last <= MAX_SEQUENCE_ADVANCE

static func vector(value: Variant, bound: float) -> bool:
	if not value is Array or value.size() != 3: return false
	for item: Variant in value:
		if not finite(item,bound): return false
	return true

static func valid_input(value: Variant) -> bool:
	if not LfeCompatibilityManifest.exact_keys(value,INPUT_KEYS) or value["kind"] != "movement_input": return false
	if not integer(value["input_epoch"],1) or not integer(value["sequence"],1) or not finite(value["move_x"],1.0) or not finite(value["move_z"],1.0): return false
	if Vector2(float(value["move_x"]),float(value["move_z"])).length_squared() > 1.000002: return false
	return value["jump_pressed"] is bool and value["sprint_requested"] is bool and finite(value["yaw"],PI + 0.000001) and finite(value["pitch"],MAX_PITCH + ANGLE_EPSILON)

static func valid_state(value: Variant) -> bool:
	return LfeCompatibilityManifest.exact_keys(value,STATE_KEYS) and LfeWorldResourceState._valid_identity(value["player_id"]) and vector(value["position"],1000000.0) and vector(value["velocity"],1000.0) and finite(value["yaw"],PI + 0.000001) and finite(value["pitch"],MAX_PITCH + ANGLE_EPSILON) and value["grounded"] is bool and integer(value["ack"])

static func valid_states(values: Variant) -> bool:
	if not values is Array or values.is_empty() or values.size() > MAX_PLAYERS: return false
	var ids: Dictionary = {}
	for state: Variant in values:
		if not valid_state(state) or ids.has(state["player_id"]): return false
		ids[state["player_id"]] = true
	return true

static func valid(value: Variant) -> bool:
	if not value is Dictionary or not value.get("kind") is String: return false
	match value["kind"]:
		"movement_input": return valid_input(value)
		"movement_bootstrap":
			if not LfeCompatibilityManifest.exact_keys(value,["kind","tick","epoch","self","states"]): return false
			if not integer(value["tick"]) or not integer(value["epoch"],1) or not LfeWorldResourceState._valid_identity(value["self"]) or not valid_states(value["states"]): return false
			for state: Dictionary in value["states"]:
				if state["player_id"] == value["self"]: return true
			return false
		"movement_snapshot":
			return LfeCompatibilityManifest.exact_keys(value,["kind","tick","epoch","states"]) and integer(value["tick"]) and integer(value["epoch"],1) and valid_states(value["states"])
		"movement_reset":
			return LfeCompatibilityManifest.exact_keys(value,["kind","tick","epoch","input_epoch","state"]) and integer(value["tick"]) and integer(value["epoch"],1) and integer(value["input_epoch"],2) and valid_state(value["state"])
		"presence_enter":
			return LfeCompatibilityManifest.exact_keys(value,["kind","tick","epoch","state"]) and integer(value["tick"]) and integer(value["epoch"],1) and valid_state(value["state"])
		"presence_leave":
			return LfeCompatibilityManifest.exact_keys(value,["kind","tick","epoch","player_id"]) and integer(value["tick"]) and integer(value["epoch"],1) and LfeWorldResourceState._valid_identity(value["player_id"])
	return false

static func encode(value: Dictionary) -> PackedByteArray:
	if not valid(value): return PackedByteArray()
	var bytes: PackedByteArray = JSON.stringify(value).to_utf8_buffer()
	return bytes if bytes.size() <= MAX_BYTES else PackedByteArray()

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_BYTES: return {}
	var source: String = bytes.get_string_from_utf8()
	if source.to_utf8_buffer() != bytes: return {}
	var parser: JSON = JSON.new()
	if parser.parse(source) != OK or not valid(parser.data): return {}
	return parser.data

static func input(sequence: int, intent: Dictionary, input_epoch: int = 1) -> Dictionary:
	return {"kind":"movement_input","sequence":sequence,"input_epoch":input_epoch,"move_x":intent["move"].x,"move_z":intent["move"].y,"jump_pressed":intent["jump"],"sprint_requested":intent["sprint"],"yaw":wrapf(float(intent["yaw"]),-PI,PI),"pitch":intent["pitch"]}

static func array3(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

static func vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))