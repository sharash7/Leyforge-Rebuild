extends SceneTree

const A: String = "11111111111111111111111111111111"
const B: String = "22222222222222222222222222222222"
const C: String = "33333333333333333333333333333333"
var checks: int = 0
var failures: Array[String] = []
var output: String

func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not output.is_absolute_path(): quit(1); return
	var input: Dictionary = LfeMovementProtocol.input(1,{"move":Vector2(0,-1),"jump":true,"sprint":true,"yaw":0.0,"pitch":0.0})
	check(LfeMovementProtocol.valid(input),"canonical exact input")
	var encoded: PackedByteArray = LfeMovementProtocol.encode(input)
	check(encoded.size() < 256,"measured input bytes <256")
	check(LfeMovementProtocol.decode(encoded) == JSON.parse_string(JSON.stringify(input)),"JSON round trip")
	for key: String in input:
		var bad: Dictionary = input.duplicate()
		bad.erase(key)
		check(not LfeMovementProtocol.valid(bad),"missing input field: "+key)
	for key: String in ["player_id","position","client_position","velocity","grounded","health","inventory","world"]:
		var bad: Dictionary = input.duplicate()
		bad[key] = A
		check(not LfeMovementProtocol.valid(bad),"foreign authoritative field rejected: "+key)
	for value: Variant in [null,[],{},{"kind":"unknown"},true]:
		check(not LfeMovementProtocol.valid(value),"wrong shape/kind")
	for key: String in ["move_x","move_z","yaw","pitch"]:
		for value: Variant in [NAN,INF,-INF,"1",true,null]:
			var bad: Dictionary = input.duplicate()
			bad[key] = value
			check(not LfeMovementProtocol.valid(bad),"finite/type validation: "+key)
	for value: Variant in [0,-1,1.5,NAN,INF,true,"1",2147483648]:
		var bad: Dictionary = input.duplicate()
		bad["sequence"] = value
		check(not LfeMovementProtocol.valid(bad),"sequence validation")
	for key: String in ["jump_pressed","sprint_requested"]:
		for value: Variant in [1,0,"true",null]:
			var bad: Dictionary = input.duplicate()
			bad[key] = value
			check(not LfeMovementProtocol.valid(bad),"edge boolean")
	var bad_vector: Dictionary = input.duplicate()
	bad_vector["move_x"] = 1.0
	check(not LfeMovementProtocol.valid(bad_vector),"diagonal over magnitude rejected")
	bad_vector["move_z"] = 0.0
	bad_vector["move_x"] = 1.0001
	check(not LfeMovementProtocol.valid(bad_vector),"component bounds")
	bad_vector = input.duplicate()
	bad_vector["pitch"] = LfeMovementProtocol.MAX_PITCH + 0.001
	check(not LfeMovementProtocol.valid(bad_vector),"controller pitch bound")
	bad_vector["pitch"] = 0.0
	bad_vector["yaw"] = 1000000
	check(not LfeMovementProtocol.valid(bad_vector),"bounded normalized yaw")
	check(LfeMovementProtocol.fresh(2,1),"next sequence accepted")
	for pair: Array in [[1,1],[0,1],[2.5,1],[1026,1],[-1,1]]:
		check(not LfeMovementProtocol.fresh(pair[0],pair[1]),"duplicate/stale/extreme sequence")
	check(LfeMovementProtocol.decode("broken".to_utf8_buffer()).is_empty(),"malformed")
	check(LfeMovementProtocol.decode(PackedByteArray([255,254])).is_empty(),"invalid UTF8")
	check(LfeMovementProtocol.decode("x".repeat(LfeMovementProtocol.MAX_BYTES+1).to_utf8_buffer()).is_empty(),"byte bound")
	var state: Dictionary = {"player_id":A,"position":[1,24,1],"velocity":[0,0,0],"yaw":0.0,"pitch":0.0,"grounded":true,"ack":1}
	check(LfeMovementProtocol.valid_state(state),"canonical snapshot state")
	for key: String in state:
		var bad: Dictionary = state.duplicate(true)
		bad.erase(key)
		check(not LfeMovementProtocol.valid_state(bad),"missing state: "+key)
	for field: String in ["position","velocity"]:
		for value: Variant in [[],[0,0],[0,0,0,0],[0,NAN,0],[0,INF,0],["0",0,0],[true,0,0]]:
			var bad: Dictionary = state.duplicate(true)
			bad[field] = value
			check(not LfeMovementProtocol.valid_state(bad),"bounded vector: "+field)
	check(not LfeMovementProtocol.valid_states([state,state]),"duplicate state identities")
	check(not LfeMovementProtocol.valid_states([]),"empty snapshots")
	var many: Array = []
	for index: int in range(9):
		var item: Dictionary = state.duplicate(true)
		item["player_id"] = "%032x" % (index+1)
		many.append(item)
	check(not LfeMovementProtocol.valid_states(many),"player count bound")
	for packet: Dictionary in [
		{"kind":"movement_bootstrap","tick":1,"epoch":1,"self":A,"states":[state]},
		{"kind":"movement_snapshot","tick":2,"epoch":1,"states":[state]},
		{"kind":"presence_enter","tick":3,"epoch":2,"state":state},
		{"kind":"presence_leave","tick":4,"epoch":3,"player_id":A}
	]:
		check(LfeMovementProtocol.decode(LfeMovementProtocol.encode(packet)) == JSON.parse_string(JSON.stringify(packet)),"presence/snapshot round trip")
		for key: String in packet:
			var bad: Dictionary = packet.duplicate(true)
			bad.erase(key)
			check(not LfeMovementProtocol.valid(bad),"missing packet field")
	var at_limit: Dictionary = input.duplicate()
	for limit: float in [LeyforgeFirstPersonPlayer.MAX_LOOK_ANGLE,-LeyforgeFirstPersonPlayer.MAX_LOOK_ANGLE]:
		# Node3D Euler properties use Vector3's actual engine precision.
		at_limit["pitch"] = Vector3(limit,0,0).x
		check(LfeMovementProtocol.valid_input(at_limit),"controller pitch limit survives float32 representation")
		var at_state: Dictionary = state.duplicate(true)
		at_state["pitch"] = at_limit["pitch"]
		check(LfeMovementProtocol.valid_state(at_state),"host snapshot accepts controller pitch limit")
	var no_self: Dictionary = {"kind":"movement_bootstrap","tick":1,"epoch":1,"self":B,"states":[state]}
	check(not LfeMovementProtocol.valid(no_self),"bootstrap must include self")
	var eight: Array = many.slice(0,8)
	var largest: PackedByteArray = LfeMovementProtocol.encode({"kind":"movement_snapshot","tick":2147483647,"epoch":2147483647,"states":eight})
	check(not largest.is_empty() and largest.size() <= LfeMovementProtocol.MAX_BYTES,"eight-player snapshot measured under byte bound")
	check(LfeMovementProtocol.valid_states(eight),"eight-player bound accepted")
	var network: LfeNetworkSession = LfeNetworkSession.new()
	network.mode = "HOST"
	network.state = "HOSTING"
	network.peer_to_player = {1:A,20:B,30:C}
	var movement: LeyforgePlayerMovement = LeyforgePlayerMovement.new()
	movement.session = network
	var body_b: LeyforgeAuthoritativePlayerBody = LeyforgeAuthoritativePlayerBody.new()
	var body_c: LeyforgeAuthoritativePlayerBody = LeyforgeAuthoritativePlayerBody.new()
	movement.bodies = {B:body_b,C:body_c}
	movement._packet(20,encoded)
	check(body_b.accepted_sequence == 1 and body_c.accepted_sequence == 0,"transport peer B affects only B")
	var spoof: Dictionary = input.duplicate()
	spoof["player_id"] = C
	movement._packet(20,JSON.stringify(spoof).to_utf8_buffer())
	check(body_c.accepted_sequence == 0 and body_b.accepted_sequence == 1,"actor spoof rejected")
	movement._packet(99,encoded)
	movement._packet(1,encoded)
	check(body_c.accepted_sequence == 0 and body_b.accepted_sequence == 1,"unbound/host peer rejected")
	check(not body_b.accept_input(input),"duplicate ignored")
	input["sequence"] = 2
	check(body_b.accept_input(input),"monotonic accepted")
	input["sequence"] = 1
	check(not body_b.accept_input(input) and body_b.accepted_sequence == 2,"stale cannot rewind")
	check(network.send_packet(20,encoded,MultiplayerPeer.TRANSFER_MODE_RELIABLE,3) == ERR_INVALID_PARAMETER,"no transport fails safely")
	check((LfeVoxelInteractionRules.PLAYER_PHYSICAL_MASK & LfeVoxelInteractionRules.PLAYER_BODY_LAYER) == 0,"players never block players")
	check(LfeCompatibilityManifest.PROTOCOL == 6 and LfeWorldSave.SAVE_VERSION == 4 and LfeWorldSave.CONTENT_VERSION == 1,"version boundary")
	body_b.free()
	body_c.free()
	movement.free()
	network.free()
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"input_bytes":encoded.size(),"eight_player_snapshot_bytes":largest.size()},"\t"))
	print("W5_3_FOCUSED_%s checks=%d" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)