class_name LeyforgePlayerSurvival
extends Node

var game: LeyforgeWave1Playground
var session: LfeNetworkSession
var replica: LfeSurvivalReplica = LfeSurvivalReplica.new()
var shelter: Dictionary = {}
var rests: Dictionary = {}
var revisions: Dictionary = {}
var mutations: Dictionary = {}
var initialized: Dictionary = {}
var resync_times: Dictionary = {}
var clock: float = 0.0
var waiting_since: float = -1.0
var last_request: float = -1.0
var events: Array = []
var metrics: Dictionary = {"periodic_packets":0,"reliable_packets":0,"bytes":0,"max_periodic_bytes":0,"bootstrap_bytes":0,"rejected":0,"resyncs":0,"recoveries":0}

func configure(g: LeyforgeWave1Playground) -> void:
	game = g; process_physics_priority = 25

func bind(s: LfeNetworkSession) -> void:
	session = s
	s.packet_received.connect(_packet)
	s.peer_left.connect(_leave)
	s.state_changed.connect(func(state: String, _reason: String):
		if s.mode == "JOIN" and state == "DISCONNECTED": replica.clear())

func _leave(peer: int, actor: String) -> void:
	rests.erase(actor); shelter.erase(actor); initialized.erase(peer); resync_times.erase(peer)
	game.cancel_actor_harvest(actor)

func mutation_revision(actor: String) -> int:
	return int(mutations.get(actor,1))

func owner_view() -> Dictionary:
	if game.authority == null: return replica.snapshot()
	return view(game.local_player_id)

func view(actor: String, reliable: bool = true) -> Dictionary:
	return LfeSurvivalProtocol.view(game.authority.character(actor).survival,int(revisions.get(actor,1)),mutation_revision(actor),bool(shelter.get(actor,{}).get("covered",false)),resting(actor),reliable)

func resting(actor: String) -> bool:
	return game._resting if actor == game.local_player_id else rests.has(actor)

func cancel_rest(actor: String) -> void:
	var was: bool = resting(actor)
	rests.erase(actor)
	if actor == game.local_player_id: game._resting = false
	if was: changed(actor)

func begin_rest(actor: String, id: String) -> LfeCommandResult:
	var body: Variant = body_for(actor)
	if body == null or not game._runtime_is_ready or not game.authority.character(actor).survival.alive(): return LfeCommandResult.rejected("not_ready")
	if actor != game.local_player_id and not body.ready_for_movement: return LfeCommandResult.rejected("not_ready")
	var object: Dictionary = _rest_object(id)
	if object.is_empty(): return LfeCommandResult.rejected("invalid_target")
	if not _rest_near(actor,object): return LfeCommandResult.rejected("out_of_range")
	var covered: bool = game.detect_shelter_at(body.global_position)
	shelter[actor] = {"covered":covered,"timer":0.5}
	if not covered: return LfeCommandResult.rejected("blocked")
	rests[actor] = id
	if actor == game.local_player_id: game._resting = true
	game.cancel_actor_harvest(actor)
	changed(actor)
	return LfeCommandResult.accepted({"resting":true})

func _rest_object(id: String) -> Dictionary:
	for object: Dictionary in game.creation.objects():
		if object["instance"] == id and game.block_catalog.content_definition(StringName(object["content"])).get("function") == "rest" and game.block_catalog.canonical_id_for_voxel_id(game._voxel_id_at(Vector3i(object["cell"][0],object["cell"][1],object["cell"][2]))) == StringName(object["content"]): return object
	return {}

func _rest_near(actor: String, object: Dictionary) -> bool:
	return not object.is_empty() and game.authority.near(actor,object["cell"].map(func(v: Variant)->float:return float(v)+0.5),3)

func body_for(actor: String) -> CharacterBody3D:
	return game.player if actor == game.local_player_id else game.movement.bodies.get(actor) if game.movement != null else null

# World advancement is a separate, single call. Only live bodies receive biology.
func advance(seconds: float) -> bool:
	if not LfeWorldSave._finite_in_range(seconds,60) or seconds < 0 or game.authority == null: return false
	game._sync_active_transform()
	if not game.authority.advance_world(seconds): return false
	var actors: Array[String] = [game.local_player_id]
	if game.movement != null and session != null and session.mode == "HOST":
		for actor: String in game.movement.bodies:
			if session.player_to_peer.has(actor): actors.append(actor)
	for actor: String in actors:
		var body: Variant = body_for(actor)
		var record: LfePlayerCharacter = game.authority.character(actor)
		if not record.survival.alive(): recover(actor); continue
		if actor != game.local_player_id and not body.ready_for_movement: continue
		var cache: Dictionary = shelter.get(actor,{"timer":0.0,"covered":false})
		cache["timer"] -= seconds
		if float(cache["timer"]) <= 0:
			cache["covered"] = game.detect_shelter_at(body.global_position); cache["timer"] = 0.5
		shelter[actor] = cache
		if actor == game.local_player_id: game._sheltered = cache["covered"]
		var moving: bool = body.activity_moving or Vector2(body.velocity.x,body.velocity.z).length_squared() > 0.04
		if resting(actor) and (moving or not cache["covered"] or (rests.has(actor) and not _rest_near(actor,_rest_object(rests[actor])))): cancel_rest(actor)
		record.survival.advance(seconds,cache["covered"],resting(actor),body.activity_sprinting)
		# Small continuous debt attrition travels with the 10 Hz biology view;
		# the critical zero-health transition receives an immediate reliable fact.
		if not record.survival.alive(): changed(actor); recover(actor)
	return true

func landing(actor: String, speed: float) -> bool:
	var amount: float = LeyforgeMovementRules.fall_damage(speed)
	if amount <= 0 or game.authority == null: return false
	var success: bool = damage(actor,amount)
	events.append({"event":"fall","actor":actor,"speed":speed,"damage":amount,"applied":success})
	if events.size() > 64: events.pop_front()
	return success

func damage(actor: String, amount: float) -> bool:
	if not game.authority.execute(actor,"damage",{"amount":amount}).success: return false
	changed(actor)
	if not game.authority.character(actor).survival.alive():
		game.cancel_actor_harvest(actor); cancel_rest(actor)
		if actor == game.local_player_id: game.set_primary_action(false)
	return true

func recover(actor: String) -> bool:
	var body: Variant = body_for(actor)
	game.cancel_actor_harvest(actor); cancel_rest(actor)
	if body == null: return false
	var spawn: Vector3 = game.find_network_spawn(actor)
	if not spawn.is_finite():
		body.velocity = Vector3.ZERO
		return false
	if not game.authority.execute(actor,"recover",{"spawn":spawn}).success: return false
	body.global_position = spawn; body.velocity = Vector3.ZERO
	body.activity_sprinting = false; body.activity_moving = false
	if actor == game.local_player_id:
		game.set_primary_action(false)
		game.player.clear_movement_intent()
		game.player.show_status("Recovered at safe spawn; inventory retained",5000)
	else:
		# Before movement bootstrap there is no old client prediction to fence;
		# initial input epoch remains 1 and bootstrap carries the recovered facts.
		var peer: int = session.player_to_peer.get(actor,0)
		body.reset_input(game.movement.epochs.has(peer))
		body.ready_for_movement = false
		body.sync_record()
		game.movement.reset_actor(actor)
	shelter.erase(actor)
	changed(actor); metrics["recoveries"] += 1
	return true

func changed(actor: String) -> void:
	mutations[actor] = mutation_revision(actor)+1
	publish(actor,true)

func publish(actor: String, reliable: bool) -> void:
	revisions[actor] = int(revisions.get(actor,0))+1
	if session == null or session.mode != "HOST" or not session.player_to_peer.has(actor): return
	var peer: int = session.player_to_peer[actor]
	if peer == session.local_peer_id: return
	_send(peer,view(actor,reliable))

func _send(peer: int, p: Dictionary) -> void:
	var bytes: PackedByteArray = LfeSurvivalProtocol.encode(p)
	if bytes.is_empty(): return
	var reliable: bool = p["kind"] != "survival_snapshot"
	if session.send_packet(peer,bytes,MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED,LfeSurvivalProtocol.CONTROL_CHANNEL if reliable else LfeSurvivalProtocol.SNAPSHOT_CHANNEL) != OK: return
	metrics["bytes"] += bytes.size()
	metrics["reliable_packets" if reliable else "periodic_packets"] += 1
	if not reliable: metrics["max_periodic_bytes"] = maxi(metrics["max_periodic_bytes"],bytes.size())
	elif p["kind"] == "survival_state" and int(metrics["bootstrap_bytes"]) == 0: metrics["bootstrap_bytes"] = bytes.size()

func _packet(peer: int, bytes: PackedByteArray) -> void:
	var family: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not family is Dictionary or not family.get("kind") is String or not family["kind"].begins_with("survival_"): return
	var p: Dictionary = LfeSurvivalProtocol.decode(bytes)
	if p.is_empty(): metrics["rejected"] += 1; return
	if session.mode == "JOIN" and peer == 1: session.note_host_traffic()
	var now: float = Time.get_ticks_msec()/1000.0
	if session.mode == "HOST":
		if p["kind"] != "survival_resync": metrics["rejected"] += 1; return
		var actor: String = session.peer_to_player.get(peer,"")
		if actor.is_empty() or now-float(resync_times.get(peer,-1.0)) < 0.2: return
		resync_times[peer] = now; metrics["resyncs"] += 1; publish(actor,true)
	elif peer == 1 and p["kind"] != "survival_resync":
		var first: bool = not replica.ready()
		if replica.receive(p,now):
			waiting_since = -1.0
			if first: print("W5_6_SURVIVAL_READY revision=%d profile=%s" % [int(p["revision"]),p["profile"]])
		else: metrics["rejected"] += 1

func _physics_process(delta: float) -> void:
	if session == null: return
	if session.mode == "HOST" and session.state == "HOSTING":
		clock += delta
		if clock < 1.0/LfeSurvivalProtocol.HZ: return
		clock = fmod(clock,1.0/LfeSurvivalProtocol.HZ)
		for peer: int in session.peer_to_player:
			if peer == session.local_peer_id: continue
			var actor: String = session.peer_to_player[peer]
			if not game.movement.bodies.has(actor) or not game.movement.bodies[actor].ready_for_movement: continue
			var first: bool = not initialized.has(peer)
			publish(actor,first); initialized[peer] = true
	elif session.mode == "JOIN" and session.state == "CONNECTED":
		var now: float = Time.get_ticks_msec()/1000.0
		if not replica.ready() or now-replica.received_at > 3.0:
			if waiting_since < 0: waiting_since = now
			if now-last_request > 0.5: _send(1,{"kind":"survival_resync"}); last_request = now
			if now-waiting_since > 10.0: session.disconnect_session()
