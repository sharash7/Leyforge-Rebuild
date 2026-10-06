class_name LeyforgeVoxelNetwork
extends Node

const SYNC_RADIUS: float = 96.0
const PACKETS_PER_FRAME: int = 8
const MAX_RECEIVE: int = 1024
var game: LeyforgeWave1Playground
var session: LfeNetworkSession
var replica: LfeVoxelReplica = LfeVoxelReplica.new()
var revisions: Dictionary = {}
var queued: Dictionary = {}
var known: Dictionary = {}
var transactions: Dictionary = {}
var forced: Dictionary = {}
var initial_ack: Dictionary = {}
var request_times: Dictionary = {}
var action_sequences: Dictionary = {}
var action_rates: Dictionary = {}
var pending_resync: Dictionary = {}
var resync_clock: float = 0.0
var incoming: Array[Dictionary] = []
var dirty_cells: Dictionary = {}
var transfer_sequence: int = 0
var sync_sequence: int = 0
var flush_clock: float = 0.0
var interest_clock: float = 0.0
var action_clock: float = 0.0
var action_sequence: int = 0
var action_target: Dictionary = {}
var client_ready: bool = false
var started_sync: int = 0
var region_wait_started: int = 0
var acknowledged_sync: int = 0
var feedback: Dictionary = {}
var metrics: Dictionary = {"snapshots":0,"snapshot_bytes":0,"largest_part":0,"delta_batches":0,"largest_batch":0,"resyncs":0,"rejected":0,"commits":0,"region_wait_frames":0}
var events: Array = []

func configure(owner: LeyforgeWave1Playground, network: LfeNetworkSession) -> void:
	game = owner
	session = network
	process_physics_priority = 20
	if game.block_catalog == null:
		game.block_catalog = LfeBlockCatalog.new()
		game.block_catalog.load_default()
	replica.catalog = game.block_catalog
	session.packet_received.connect(_packet)
	session.peer_left.connect(_leave)
	session.state_changed.connect(_state)
	if session.mode == "HOST":
		for bucket: Vector3i in game.world_save.overrides.bucket_keys(): revisions[bucket] = 0

static func is_voxel_packet(bytes: PackedByteArray) -> bool:
	if bytes.size() > LfeMovementProtocol.MAX_BYTES: return false
	var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	return value is Dictionary and value.get("kind") is String and String(value["kind"]).begins_with("voxel_")

func _packet(peer: int, bytes: PackedByteArray) -> void:
	if not is_voxel_packet(bytes): return
	var packet: Dictionary = LfeVoxelProtocol.decode(bytes,game.block_catalog)
	if packet.is_empty():
		metrics["rejected"] += 1
		if session.mode == "JOIN" and not client_ready: session.disconnect_session()
		return
	if session.mode == "JOIN" and peer == 1: session.note_host_traffic()
	if incoming.size() >= MAX_RECEIVE:
		session.disconnect_session() if session.mode == "JOIN" else session.disconnect_player(session.peer_to_player.get(peer,""))
		return
	incoming.append({"peer":peer,"packet":packet})

func _leave(peer: int, id: String) -> void:
	incoming = incoming.filter(func(entry: Dictionary) -> bool: return entry["peer"] != peer)
	known.erase(peer)
	transactions.erase(peer)
	forced.erase(peer)
	initial_ack.erase(peer)
	request_times.erase(peer)
	action_sequences.erase(peer)
	action_rates.erase(peer)
	game.cancel_actor_harvest(id)

func _state(state: String, _reason: String) -> void:
	if session.mode == "JOIN" and state == "DISCONNECTED":
		client_ready = false
		# The generator may still hold the old store on a worker thread.
		if replica.catalog != null: replica.store.load_entries([],replica.catalog)
		replica = LfeVoxelReplica.new()
		game.client_voxel_overrides = null
		incoming.clear()
		dirty_cells.clear()
		pending_resync.clear()

func relevant_bucket(bucket: Vector3i, position: Vector3) -> bool:
	var box: AABB = LfeVoxelOverrideStore.bucket_aabb(bucket)
	var closest: Vector3 = position.clamp(box.position,box.end)
	return position.distance_squared_to(closest) <= SYNC_RADIUS * SYNC_RADIUS

func committed(cell: Vector3i, voxel: int) -> void:
	if session.mode != "HOST": return
	var bucket: Vector3i = LfeVoxelOverrideStore.bucket_for(cell)
	var previous: int = int(revisions.get(bucket,0))
	if previous >= LfeMovementProtocol.MAX_SEQUENCE:
		session.disconnect_session()
		return
	revisions[bucket] = previous + 1
	if not queued.has(bucket): queued[bucket] = {"from":previous,"edits":{}}
	queued[bucket]["edits"][cell] = {"position":LfeVoxelProtocol.array3(cell),"block":String(game.block_catalog.canonical_id_for_voxel_id(voxel))}
	metrics["commits"] += 1
	_log("commit",{"bucket":LfeVoxelProtocol.array3(bucket),"revision":previous+1,"cell":LfeVoxelProtocol.array3(cell)})

func _physics_process(delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if session.mode == "HOST" and session.state == "HOSTING":
		for received: Dictionary in incoming: _host_packet(received["peer"],received["packet"],now)
		incoming.clear()
		game.advance_remote_harvests(delta,now)
		interest_clock += delta
		if interest_clock >= 0.1:
			interest_clock = 0
			_refresh_interest()
		flush_clock += delta
		if flush_clock >= 1.0 / LfeVoxelProtocol.FLUSH_HZ:
			flush_clock = fmod(flush_clock,1.0 / LfeVoxelProtocol.FLUSH_HZ)
			_flush()
		_pump()
	elif session.mode == "JOIN" and session.state == "CONNECTED":
		if game._generator == null: return # Bootstrap and voxel channels may cross.
		replica.generator = game._generator
		for received: Dictionary in incoming: _client_packet(received["packet"],now)
		incoming.clear()
		for bucket: Vector3i in replica.expire(now): _request_resync(bucket,now)
		resync_clock += delta
		if resync_clock >= 0.25 and not pending_resync.is_empty():
			resync_clock = 0
			_send_resync(pending_resync.keys()[0],now)
		_apply_loaded_cells()
		if game.player != null:
			game.player.voxel_region_ready = local_region_ready(game.player.global_position)
			if client_ready and not game.player.voxel_region_ready:
				metrics["region_wait_frames"] += 1
				if region_wait_started == 0: region_wait_started = Time.get_ticks_msec()
				if Time.get_ticks_msec()-region_wait_started > 10000: session.disconnect_session(); return
			else: region_wait_started = 0
		if replica.ready() and pending_resync.is_empty() and acknowledged_sync != replica.sync_id:
			acknowledged_sync = replica.sync_id
			_send(1,{"kind":"voxel_sync_ack","sync_id":replica.sync_id})
			client_ready = true
			replica.synchronized = true
			if game.player != null: game.player.show_status("World synchronized",1500)
			_log("world_synchronized",{"sync_id":replica.sync_id,"overrides":replica.store.count()})
			print("W5_4_WORLD_SYNCHRONIZED overrides=%d" % replica.store.count())
		if not client_ready and started_sync > 0 and Time.get_ticks_msec()-started_sync > 60000:
			session.disconnect_session()
		if game.player != null and game.player.is_runtime_ready(): _client_action(delta)

func _host_packet(peer: int, packet: Dictionary, now: float) -> void:
	var actor: String = session.peer_to_player.get(peer,"")
	if actor.is_empty() or peer == 1 or not game.movement.bodies.has(actor):
		metrics["rejected"] += 1
		return
	var kind: String = packet["kind"]
	if kind == "voxel_sync_ack":
		if int(packet["sync_id"]) == int(initial_ack.get(peer,-1)): initial_ack[peer] = 0
	elif kind == "voxel_resync_request":
		var bucket: Vector3i = LfeVoxelProtocol.cell(packet["bucket"])
		if not relevant_bucket(bucket,game.movement.bodies[actor].global_position) or now-float(request_times.get(peer,-1.0)) < 0.2:
			metrics["rejected"] += 1
			return
		request_times[peer] = now
		if not forced.has(peer): forced[peer] = {}
		if forced[peer].size() < 64: forced[peer][bucket] = true
		metrics["resyncs"] += 1
	elif kind == "voxel_harvest_state":
		var rate: Dictionary = action_rates.get(peer,{"tokens":8.0,"time":now})
		rate["tokens"] = minf(8.0,float(rate["tokens"])+(now-float(rate["time"]))*30.0)
		rate["time"] = now
		action_rates[peer] = rate
		if float(rate["tokens"]) < 1.0:
			metrics["rejected"] += 1
			return
		rate["tokens"] -= 1.0
		var last: int = int(action_sequences.get(peer,0))
		if not LfeMovementProtocol.fresh(packet["action_sequence"],last):
			metrics["rejected"] += 1
			return
		action_sequences[peer] = int(packet["action_sequence"])
		var reason: String = "not_ready"
		if initial_ack.get(peer,-1) == 0:
			reason = game.actor_harvest_state(actor,packet,now)
		_send_feedback(peer,actor,reason,int(packet["action_sequence"]))
	else: metrics["rejected"] += 1

func _send_feedback(peer: int, actor: String, reason: String, sequence: int) -> void:
	_send(peer,{"kind":"voxel_harvest_result","action_sequence":sequence,"reason":reason,"progress":1.0 if reason == "completed" else game.actor_harvest_progress(actor)})

func harvest_finished(actor: String, reason: String) -> void:
	var peer: int = int(session.player_to_peer.get(actor,0))
	if peer > 1: _send_feedback(peer,actor,reason,int(action_sequences.get(peer,1)))
	_log("harvest_"+reason,{"actor":actor})

func _refresh_interest() -> void:
	for peer: int in session.peer_to_player:
		if peer == 1 or transactions.has(peer): continue
		var actor: String = session.peer_to_player[peer]
		if not game.movement.bodies.has(actor) or not game.movement.bodies[actor].ready_for_movement: continue
		var position: Vector3 = game.movement.bodies[actor].global_position
		var first: bool = not known.has(peer)
		if first: known[peer] = {}
		var buckets: Array = []
		# Revision keys retain empty buckets after a base restoration.
		for bucket: Vector3i in revisions:
			if relevant_bucket(bucket,position) and int(known[peer].get(bucket,-1)) != int(revisions[bucket]): buckets.append(bucket)
		for bucket: Vector3i in forced.get(peer,{}):
			if relevant_bucket(bucket,position) and bucket not in buckets: buckets.append(bucket)
		forced.erase(peer)
		if known[peer].size() >= LfeVoxelProtocol.MAX_BUCKETS:
			for bucket: Vector3i in known[peer].keys():
				if not relevant_bucket(bucket,position): known[peer].erase(bucket)
		if buckets.size() > LfeVoxelProtocol.MAX_BUCKETS:
			session.disconnect_player(actor)
			continue
		buckets.sort_custom(func(a: Vector3i,b: Vector3i)->bool: return Vector3(LfeVoxelOverrideStore.bucket_origin(a)).distance_squared_to(position) < Vector3(LfeVoxelOverrideStore.bucket_origin(b)).distance_squared_to(position))
		if first or not buckets.is_empty():
			sync_sequence += 1
			transactions[peer] = {"id":sync_sequence,"buckets":buckets,"index":0,"packets":[],"packet":0,"begun":false,"entries":0,"required":buckets.duplicate(),"start":Time.get_ticks_msec()}
			if first or initial_ack.get(peer,0) != 0: initial_ack[peer] = sync_sequence

func _pump() -> void:
	for peer: int in transactions.keys():
		if not session.peer_to_player.has(peer): transactions.erase(peer); continue
		var tx: Dictionary = transactions[peer]
		if Time.get_ticks_msec()-int(tx["start"]) > 60000:
			session.disconnect_player(session.peer_to_player[peer])
			transactions.erase(peer)
			continue
		var budget: int = PACKETS_PER_FRAME
		if not tx["begun"]:
			_send(peer,{"kind":"voxel_sync_begin","sync_id":tx["id"],"count":tx["buckets"].size()})
			tx["begun"] = true
			budget -= 1
		while budget > 0:
			if tx["index"] >= tx["buckets"].size():
				if _catchup_transaction(peer,tx): continue
				_send(peer,{"kind":"voxel_sync_complete","sync_id":tx["id"]})
				transactions.erase(peer)
				break
			var bucket: Vector3i = tx["buckets"][tx["index"]]
			if tx["packets"].is_empty():
				var values: Array = game.world_save.overrides.bucket_snapshot(bucket)
				tx["entries"] += values.size()
				if tx["entries"] > LfeVoxelProtocol.MAX_SYNC_ENTRIES:
					session.disconnect_player(session.peer_to_player[peer])
					transactions.erase(peer)
					break
				transfer_sequence += 1
				tx["revision"] = int(revisions.get(bucket,0))
				tx["packets"] = LfeVoxelProtocol.snapshot_packets(bucket,tx["revision"],values,transfer_sequence,tx["id"])
				tx["packet"] = 0
				metrics["snapshots"] += 1
			_send(peer,tx["packets"][tx["packet"]])
			tx["packet"] += 1
			budget -= 1
			if tx["packet"] == tx["packets"].size():
				known[peer][bucket] = tx["revision"]
				tx["index"] += 1
				tx["packets"] = []

func _flush() -> void:
	for bucket: Vector3i in queued:
		var batch: Dictionary = queued[bucket]
		var edits: Array = batch["edits"].values()
		var revision: int = int(revisions[bucket])
		for peer: int in known:
			var actor: String = session.peer_to_player.get(peer,"")
			if not game.movement.bodies.has(actor) or transactions.has(peer) or not relevant_bucket(bucket,game.movement.bodies[actor].global_position): continue
			if int(known[peer].get(bucket,-1)) != int(batch["from"]) or edits.size() > LfeVoxelProtocol.PART_ENTRIES or revision-int(batch["from"]) > LfeVoxelProtocol.MAX_ENTRIES:
				if not forced.has(peer): forced[peer] = {}
				forced[peer][bucket] = true
				continue
			var packet: Dictionary = {"kind":"voxel_delta_batch","bucket":LfeVoxelProtocol.array3(bucket),"from_revision":batch["from"],"to_revision":revision,"edits":edits}
			if _send(peer,packet):
				known[peer][bucket] = revision
				metrics["delta_batches"] += 1
				metrics["largest_batch"] = maxi(int(metrics["largest_batch"]),edits.size())
			else:
				if not forced.has(peer): forced[peer] = {}
				forced[peer][bucket] = true
	queued.clear()

func _client_packet(packet: Dictionary, now: float) -> void:
	if packet["kind"] == "voxel_harvest_result":
		feedback = packet
		if game.player != null: game.player.show_status("Gathering: %s (%.0f%%)" % [packet["reason"],float(packet["progress"])*100],1500)
		_log("action_result",packet)
		return
	if packet["kind"] == "voxel_sync_begin":
		if started_sync == 0: started_sync = Time.get_ticks_msec()
		print("W5_4_SYNCHRONIZING_WORLD buckets=%d" % int(packet["count"]))
		if game.player != null: game.player.show_status("Synchronizing world...",5000)
	var result: Dictionary = replica.receive(packet,now)
	if result.has("resync"):
		_log("resync_needed",{"bucket":LfeVoxelProtocol.array3(result["resync"])})
		_request_resync(result["resync"],now)
	if not result.get("ok",false):
		metrics["rejected"] += 1
		if result.get("fatal",false): session.disconnect_session()
		return
	for cell: Vector3i in result.get("cells",[]): dirty_cells[cell] = true
	if result.get("snapshot",false): pending_resync.erase(result["bucket"])
	if result.has("bucket"):
		_log("applied",{"bucket":LfeVoxelProtocol.array3(result["bucket"]),"revision":replica.revisions[result["bucket"]],"hash":replica.hash_for(result["bucket"]),"kind":packet["kind"],"position":LfeMovementProtocol.array3(game.player.global_position)})

func _request_resync(bucket: Vector3i, _now: float) -> void:
	if pending_resync.size() < 64: pending_resync[bucket] = true

func _send_resync(bucket: Vector3i, _now: float) -> void:
	_send(1,{"kind":"voxel_resync_request","bucket":LfeVoxelProtocol.array3(bucket),"revision":int(replica.revisions.get(bucket,0))})
	metrics["resyncs"] += 1
	# Round-robin bounded retries until a clean replacement succeeds.
	pending_resync.erase(bucket)
	pending_resync[bucket] = true

func _apply_loaded_cells() -> void:
	if game.terrain == null: return
	var tool: VoxelTool = game.terrain.get_voxel_tool()
	tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	var cells: Array = dirty_cells.keys()
	for cell: Vector3i in cells:
		if tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(cell)):
			tool.set_voxel(cell,replica.store.voxel_id_at(cell,game._generator.sample_voxel_id(cell)))
			dirty_cells.erase(cell)

# Stop local controls near incomplete state; gravity, look and other peers continue.
# Farther transfers do not interrupt movement. A stalled local wait closes in 10 s.
func local_region_ready(position: Vector3) -> bool:
	var buckets: Array = pending_resync.keys()
	for transfer: Dictionary in replica.transfers.values(): buckets.append(LfeVoxelProtocol.cell(transfer["bucket"]))
	for bucket: Vector3i in buckets:
		var box: AABB = LfeVoxelOverrideStore.bucket_aabb(bucket)
		if position.distance_squared_to(position.clamp(box.position,box.end)) <= 64.0: return false
	for cell: Vector3i in dirty_cells:
		if Vector3(cell).distance_squared_to(position) <= 64.0: return false
	return true

func spawn_applied() -> bool:
	if not client_ready or game.player == null: return false
	for cell: Vector3i in dirty_cells:
		if Vector3(cell).distance_to(game.player.global_position) < 8: return false
	return true

func _client_action(delta: float) -> void:
	action_clock += delta
	var player: LeyforgeFirstPersonPlayer = game.player
	var held: bool = not player.inventory_open and Input.is_action_pressed("break_block") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and player.voxel_region_ready
	player._update_targeting()
	var target: Dictionary = {}
	if held and not player.target_source().is_empty():
		target = {"source":player.target_source()}
	elif held and player.has_voxel_target():
		var cell: Vector3i = player.get_target_cell()
		var tool: VoxelTool = game.terrain.get_voxel_tool()
		tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
		target = {"cell":cell,"block":String(game.block_catalog.canonical_id_for_voxel_id(tool.get_voxel(cell)))}
	if target != action_target:
		if not action_target.is_empty(): _action_send(false,action_target)
		action_target = target
		if not target.is_empty(): _action_send(true,target)
		action_clock = 0
	elif not target.is_empty() and action_clock >= 1.0 / LfeVoxelProtocol.HOLD_HZ:
		_action_send(true,target)
		action_clock = 0

func _action_send(active: bool, target: Dictionary) -> void:
	if target.has("source"):
		game.resource_network.submit("source_hold",{"target":target["source"],"active":active})
		return
	action_sequence += 1
	_send(1,{"kind":"voxel_harvest_state","action_sequence":action_sequence,"active":active,"target_cell":LfeVoxelProtocol.array3(target["cell"]),"expected_block":target["block"]})

func _send(peer: int, packet: Dictionary) -> bool:
	var bytes: PackedByteArray = LfeVoxelProtocol.encode(packet,game.block_catalog)
	if bytes.is_empty(): return false
	var channel: int = LfeVoxelProtocol.ACTION_CHANNEL if packet["kind"] in ["voxel_harvest_state","voxel_harvest_result","voxel_resync_request","voxel_sync_ack"] else LfeVoxelProtocol.STATE_CHANNEL
	var result: Error = session.send_packet(peer,bytes,MultiplayerPeer.TRANSFER_MODE_RELIABLE,channel)
	if packet["kind"].begins_with("voxel_snapshot"):
		metrics["snapshot_bytes"] += bytes.size()
		metrics["largest_part"] = maxi(int(metrics["largest_part"]),bytes.size())
	return result == OK

func _log(kind: String, data: Dictionary) -> void:
	events.append({"kind":kind,"msec":Time.get_ticks_msec(),"utc_msec":Time.get_unix_time_from_system()*1000.0,"data":data.duplicate(true)})
	if events.size() > 256: events.pop_front()

# Edits committed during snapshot pumping must precede the completion barrier.
# Revisit already-sent stale buckets and extend the declared unique count for
# newly touched relevant buckets; never enable initial movement on stale facts.
func _catchup_transaction(peer: int, tx: Dictionary) -> bool:
	var actor: String = session.peer_to_player.get(peer,"")
	if not game.movement.bodies.has(actor): return false
	var position: Vector3 = game.movement.bodies[actor].global_position
	var previous_count: int = tx["required"].size()
	var extended: bool = false
	for bucket: Vector3i in revisions:
		if not relevant_bucket(bucket,position) or int(known[peer].get(bucket,-1)) == int(revisions[bucket]): continue
		if bucket not in tx["required"]: tx["required"].append(bucket)
		tx["buckets"].append(bucket)
		extended = true
	if tx["required"].size() > LfeVoxelProtocol.MAX_BUCKETS:
		session.disconnect_player(actor)
		return false
	if tx["required"].size() != previous_count:
		_send(peer,{"kind":"voxel_sync_count","sync_id":tx["id"],"count":tx["required"].size()})
	return extended
