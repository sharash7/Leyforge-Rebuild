class_name LeyforgePlayerMovement
extends Node

const ENTER_RADIUS: float = 96.0
const LEAVE_RADIUS: float = 128.0
const CORRECTION_EPSILON: float = 0.08
const SNAP_DISTANCE: float = 3.0
const SMOOTH_CORRECTION: float = 0.35
const MAX_RELIABLE_QUEUE: int = 32
var game: LeyforgeWave1Playground
var session: LfeNetworkSession
var bodies: Dictionary = {}
var avatars: Dictionary = {}
var relevant: Dictionary = {}
var epochs: Dictionary = {}
var pending_admissions: Array[String] = []
var reliable_queue: Array[Dictionary] = []
var pending_snapshot: Dictionary = {}
var tick: int = 0
var sequence: int = 0
var sent_yaw: float = 0.0
var sent_pitch: float = 0.0
var last_snapshot_tick: int = -1
var input_epoch: int = 1
var client_epoch: int = 0
var bootstrap_received: bool = false
var send_enabled: bool = true
var input_clock: float = 0.0
var snapshot_clock: float = 0.0
var latest_self: Dictionary = {}
var maximum_error: float = 0.0
var corrections: int = 0
var smooth_corrections: int = 0
var correction_distance: float = 0.0
var rejected_packets: int = 0
var presence_events: Array[Dictionary] = []
var host_visible: Dictionary = {}

func configure(owner: LeyforgeWave1Playground, network: LfeNetworkSession) -> void:
	game = owner
	session = network
	# Local body updates at priority 0; remote simulation and snapshots follow it.
	process_physics_priority = 10
	session.packet_received.connect(_packet)
	session.peer_admitted.connect(func(_peer: int, id: String): pending_admissions.append(id))
	session.peer_left.connect(_leave)
	session.state_changed.connect(_session_state)

func _session_state(state: String, _reason: String) -> void:
	if session.mode == "JOIN" and state == "DISCONNECTED":
		if game.player != null:
			game.player.set_runtime_ready(false)
			game.player.set_physics_process(false)
		for avatar: Node in avatars.values(): avatar.queue_free()
		avatars.clear()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _packet(peer: int, bytes: PackedByteArray) -> void:
	var family: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if family is Dictionary and family.get("kind") is String and (family["kind"].begins_with("resource_") or family["kind"].begins_with("survival_")): return
	if LeyforgeVoxelNetwork.is_voxel_packet(bytes): return
	var packet: Dictionary = LfeMovementProtocol.decode(bytes)
	if packet.is_empty():
		rejected_packets += 1
		return
	if session.mode == "JOIN" and peer == 1: session.note_host_traffic()
	if session.mode == "HOST":
		# Actor resolution happens ONLY through the authenticated transport binding.
		var id: String = session.peer_to_player.get(peer,"")
		if peer == 1 or id.is_empty() or packet["kind"] != "movement_input" or not bodies.has(id):
			rejected_packets += 1
			return
		if game != null and game.voxel_network != null and game.voxel_network.initial_ack.get(peer,-1) != 0:
			rejected_packets += 1
			return
		var body: LeyforgeAuthoritativePlayerBody = bodies[id]
		var first_input: bool = body.accepted_sequence == 0
		if not body.accept_input(packet):
			rejected_packets += 1
		elif first_input:
			print("W5_3_FIRST_INPUT peer=%d player=%s" % [peer,id.left(8)])
	elif peer == 1 and session.state == "CONNECTED":
		if packet["kind"] == "movement_input":
			rejected_packets += 1
		elif packet["kind"] == "movement_snapshot":
			if int(packet["tick"]) > last_snapshot_tick and (pending_snapshot.is_empty() or int(packet["tick"]) > int(pending_snapshot["tick"])):
				pending_snapshot = packet
		elif reliable_queue.size() < MAX_RELIABLE_QUEUE:
			reliable_queue.append(packet)
		else:
			# Fail closed if bootstrap/presence processing cannot keep up.
			session.disconnect_session()

func _physics_process(delta: float) -> void:
	if session.mode == "HOST" and session.state == "HOSTING":
		tick += 1
		for id: String in pending_admissions: _spawn(id)
		pending_admissions.clear()
		for id: String in bodies:
			var body: LeyforgeAuthoritativePlayerBody = bodies[id]
			if not body.ready_for_movement and game.movement_area_ready(body.global_position):
				body.ready_for_movement = true
			body.simulate(delta)
			game.survival_system.landing(id,body.landing_speed)
		for peer: int in session.peer_to_player:
			if peer == 1: continue
			var id: String = session.peer_to_player[peer]
			if not bodies.has(id) or not bodies[id].ready_for_movement: continue
			_update_relevance(peer,id)
		_update_host_visibility()
		snapshot_clock += delta
		if snapshot_clock >= 1.0 / LfeMovementProtocol.SNAPSHOT_HZ:
			snapshot_clock = fmod(snapshot_clock,1.0 / LfeMovementProtocol.SNAPSHOT_HZ)
			for peer: int in relevant:
				_send(peer,{"kind":"movement_snapshot","tick":tick,"epoch":epochs[peer],"states":_states(relevant[peer])})
	elif session.mode == "JOIN" and session.state == "CONNECTED":
		_process_presence()
		if not bootstrap_received or game.player == null or not game.player.is_runtime_ready(): return
		_reconcile()
		input_clock += delta
		if send_enabled and input_clock >= 1.0 / LfeMovementProtocol.INPUT_HZ:
			input_clock = fmod(input_clock,1.0 / LfeMovementProtocol.INPUT_HZ)
			sequence += 1
			var intent: Dictionary = game.player.consume_movement_intent()
			sent_yaw = float(intent["yaw"])
			sent_pitch = float(intent["pitch"])
			_send(1,LfeMovementProtocol.input(sequence,intent,input_epoch))

func _spawn(id: String) -> void:
	if bodies.has(id) or not session.player_to_peer.has(id): return
	var record: LfePlayerCharacter = game.authority.character(id)
	var saved: Vector3 = LfeMovementProtocol.vec3(record.transform["position"])
	if not game.network_spawn_safe(saved,id,4.0):
		saved = game.find_network_spawn(id)
		if not saved.is_finite():
			session.disconnect_player(id)
			return
		record.transform["position"] = LfeMovementProtocol.array3(saved)
	var body: LeyforgeAuthoritativePlayerBody = LeyforgeAuthoritativePlayerBody.new()
	body.name = "AuthoritativePlayer_" + id.left(8)
	body.build(record)
	game.add_child(body)
	bodies[id] = body
	print("W5_3_BODY_SPAWN peer=%d player=%s position=%s" % [session.player_to_peer[id],id.left(8),saved])

func _leave(peer: int, id: String) -> void:
	pending_admissions.erase(id)
	if bodies.has(id):
		var body: LeyforgeAuthoritativePlayerBody = bodies[id]
		body.sync_record()
		body.queue_free()
		bodies.erase(id)
		host_visible.erase(id)
		print("W5_3_BODY_TEARDOWN player=%s" % id.left(8))
	relevant.erase(peer)
	epochs.erase(peer)
	# Remaining peers receive reliable removal at their next physics relevance pass.

func reset_actor(actor: String) -> void:
	var owner_peer: int = session.player_to_peer.get(actor,0)
	if not epochs.has(owner_peer): return
	# Owner reset and snapshot epoch are ordered with all presence events.
	epochs[owner_peer] += 1
	_send(owner_peer,{"kind":"movement_reset","tick":tick,"epoch":epochs[owner_peer],"input_epoch":bodies[actor].input_epoch,"state":_state(actor)})
	for peer: int in relevant:
		if peer == owner_peer or actor not in relevant[peer]: continue
		epochs[peer] += 1
		_send(peer,{"kind":"presence_leave","tick":tick,"epoch":epochs[peer],"player_id":actor})
		epochs[peer] += 1
		_send(peer,{"kind":"presence_enter","tick":tick,"epoch":epochs[peer],"state":_state(actor)})

func sync_records() -> void:
	for body: LeyforgeAuthoritativePlayerBody in bodies.values(): body.sync_record()

func _live_ids() -> Array[String]:
	var ids: Array[String] = [game.local_player_id]
	for id: String in bodies:
		if bodies[id].ready_for_movement: ids.append(id)
	ids.sort()
	return ids

func _state(id: String) -> Dictionary:
	if bodies.has(id): return bodies[id].state()
	var player: LeyforgeFirstPersonPlayer = game.player
	return {"player_id":id,"position":LfeMovementProtocol.array3(player.global_position),"velocity":LfeMovementProtocol.array3(player.velocity),"yaw":wrapf(player.rotation.y,-PI,PI),"pitch":player.movement_pitch(),"grounded":player.is_on_floor(),"ack":0}

func _states(ids: Array) -> Array:
	var result: Array = []
	for id: String in ids: result.append(_state(id))
	return result

func _update_relevance(peer: int, self_id: String) -> void:
	var origin: Vector3 = bodies[self_id].global_position
	var previous: Array = relevant.get(peer,[])
	var next: Array = [self_id]
	for id: String in _live_ids():
		if id == self_id: continue
		var distance: float = origin.distance_to(LfeMovementProtocol.vec3(_state(id)["position"]))
		if distance <= (LEAVE_RADIUS if id in previous else ENTER_RADIUS): next.append(id)
	next.sort()
	if not relevant.has(peer):
		relevant[peer] = next
		epochs[peer] = 1
		_send(peer,{"kind":"movement_bootstrap","tick":tick,"epoch":1,"self":self_id,"states":_states(next)})
		return
	for id: String in previous:
		if id in next: continue
		epochs[peer] += 1
		_send(peer,{"kind":"presence_leave","tick":tick,"epoch":epochs[peer],"player_id":id})
		_log_presence("leave",peer,id)
	for id: String in next:
		if id in previous: continue
		epochs[peer] += 1
		_send(peer,{"kind":"presence_enter","tick":tick,"epoch":epochs[peer],"state":_state(id)})
		_log_presence("enter",peer,id)
	relevant[peer] = next

func _log_presence(kind: String, peer: int, id: String) -> void:
	var event: Dictionary = {"kind":kind,"peer":peer,"player_id":id,"tick":tick}
	presence_events.append(event)
	if presence_events.size() > 128: presence_events.pop_front()
	print("W5_3_PRESENCE_%s peer=%d player=%s tick=%d" % [kind.to_upper(),peer,id.left(8),tick])

func _update_host_visibility() -> void:
	for id: String in bodies:
		var body: LeyforgeAuthoritativePlayerBody = bodies[id]
		var distance: float = body.global_position.distance_to(game.player.global_position)
		var visible_now: bool = body.ready_for_movement and distance <= (LEAVE_RADIUS if host_visible.get(id,false) else ENTER_RADIUS)
		if visible_now != bool(host_visible.get(id,false)):
			_log_presence("enter" if visible_now else "leave",1,id)
		host_visible[id] = visible_now
		body.avatar.visible = visible_now
		# Body + viewer remain active independently of avatar visibility.

func _send(peer: int, packet: Dictionary) -> void:
	var kind: String = packet["kind"]
	var channel: int = LfeMovementProtocol.PRESENCE_CHANNEL
	var mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	if kind == "movement_input":
		channel = LfeMovementProtocol.INPUT_CHANNEL
		mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	elif kind == "movement_snapshot":
		channel = LfeMovementProtocol.SNAPSHOT_CHANNEL
		mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	var bytes: PackedByteArray = LfeMovementProtocol.encode(packet)
	if not bytes.is_empty(): session.send_packet(peer,bytes,mode,channel)

func _process_presence() -> void:
	for packet: Dictionary in reliable_queue:
		match packet["kind"]:
			"movement_bootstrap":
				if bootstrap_received or packet["self"] != game.local_player_id: continue
				for state: Dictionary in packet["states"]:
					if state["player_id"] == game.local_player_id: latest_self = state
				if not game.build_client_world(latest_self): continue
				client_epoch = int(packet["epoch"])
				last_snapshot_tick = int(packet["tick"])
				bootstrap_received = true
				for state: Dictionary in packet["states"]:
					if state["player_id"] != game.local_player_id: _present(state,int(packet["tick"]))
				print("W5_3_MOVEMENT_BOOTSTRAP player=%s tick=%d" % [game.local_player_id.left(8),last_snapshot_tick])
			"movement_reset":
				if not bootstrap_received or packet["state"]["player_id"] != game.local_player_id or int(packet["epoch"]) != client_epoch+1: continue
				client_epoch = int(packet["epoch"]); input_epoch = int(packet["input_epoch"])
				last_snapshot_tick = int(packet["tick"]); pending_snapshot.clear()
				latest_self = packet["state"].duplicate(true)
				game.player.global_position = LfeMovementProtocol.vec3(latest_self["position"])
				game.player.velocity = Vector3.ZERO
				game.player.clear_movement_intent()
				game.player.show_status("Recovered at safe spawn; inventory retained",5000)
			"presence_enter":
				if not bootstrap_received or int(packet["epoch"]) != client_epoch + 1: continue
				client_epoch = int(packet["epoch"])
				_present(packet["state"],int(packet["tick"]))
				_log_presence("enter",session.local_peer_id,packet["state"]["player_id"])
			"presence_leave":
				if not bootstrap_received or int(packet["epoch"]) != client_epoch + 1 or packet["player_id"] == game.local_player_id: continue
				client_epoch = int(packet["epoch"])
				var id: String = packet["player_id"]
				if avatars.has(id):
					avatars[id].queue_free()
					avatars.erase(id)
				_log_presence("leave",session.local_peer_id,id)
	reliable_queue.clear()

func _present(state: Dictionary, server_tick: int) -> void:
	var id: String = state["player_id"]
	if id == game.local_player_id: return
	if not avatars.has(id):
		var avatar: LeyforgeRemoteAvatar = LeyforgeRemoteAvatar.new()
		game.add_child(avatar)
		avatar.build(id)
		avatars[id] = avatar
	avatars[id].push(state,server_tick)

func _reconcile() -> void:
	if pending_snapshot.is_empty(): return
	if int(pending_snapshot["epoch"]) > client_epoch: return # Reliable presence catches up across channels.
	var packet: Dictionary = pending_snapshot
	pending_snapshot = {}
	if int(packet["epoch"]) != client_epoch or int(packet["tick"]) <= last_snapshot_tick: return
	last_snapshot_tick = int(packet["tick"])
	for state: Dictionary in packet["states"]:
		var id: String = state["player_id"]
		if id != game.local_player_id:
			# An unreliable packet never creates presence.
			if avatars.has(id): avatars[id].push(state,last_snapshot_tick)
			continue
		latest_self = state
		var target: Vector3 = LfeMovementProtocol.vec3(state["position"])
		var error: float = game.player.global_position.distance_to(target)
		maximum_error = maxf(maximum_error,error)
		if error >= SNAP_DISTANCE:
			game.player.global_position = target
			game.player.velocity = LfeMovementProtocol.vec3(state["velocity"])
			corrections += 1
			print("W5_3_RECONCILE error=%.3f tick=%d ack=%d" % [error,last_snapshot_tick,int(state["ack"])])
		elif error > CORRECTION_EPSILON:
			smooth_corrections += 1
			correction_distance += error * SMOOTH_CORRECTION
			game.player.global_position = game.player.global_position.lerp(target,SMOOTH_CORRECTION)
			game.player.velocity = game.player.velocity.lerp(LfeMovementProtocol.vec3(state["velocity"]),SMOOTH_CORRECTION)
		elif game.player.velocity.length_squared() < 0.01 and LfeMovementProtocol.vec3(state["velocity"]).length_squared() < 0.01:
			game.player.global_position = target
		# Do not rewind newer look intent while moving the mouse.
		if int(state["ack"]) >= sequence and is_equal_approx(wrapf(game.player.rotation.y,-PI,PI),sent_yaw) and is_equal_approx(game.player.movement_pitch(),sent_pitch):
			game.player.set_movement_look(float(state["yaw"]),float(state["pitch"]))