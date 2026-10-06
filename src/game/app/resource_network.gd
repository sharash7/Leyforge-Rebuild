class_name LeyforgeResourceNetwork
extends Node

var game: LeyforgeWave1Playground
var session: LfeNetworkSession
var replica: LfeResourceReplica
var transactions: LfeResourceTransactions
var known: Dictionary = {}
var initial_sent: Dictionary = {}
var queues: Dictionary = {}
var pending: Dictionary = {}
var sequence: int = 0
var position_sequence: int = 0
var clock: float = 0.0
var resync_clock: float = 0.0
var resync: Dictionary = {}
var open_wait: Dictionary = {}
var object_wait: Dictionary = {}

func wait_for_object(cell: Vector3i) -> void:
	if object_wait.is_empty() or object_wait["cell"] != cell:
		object_wait = {"cell":cell,"deadline":Time.get_ticks_msec()/1000.0+5.0}
	game.player.show_status("Synchronizing object…",1500)

func _context_ready(target: String) -> bool:
	if target.is_empty(): return replica.grid != null and replica.states.get("grid/"+game.local_player_id,{}).get("context") == ""
	if replica.states.has("storage/"+target): return replica.storage_inventory(target) != null
	var object: Dictionary = replica.states.get("object/"+target,{})
	if object.is_empty(): return false
	match game.block_catalog.content_definition(StringName(object["content"])).get("function",""):
		"workbench": return replica.grid != null and replica.grid.size == 3 and replica.states.get("grid/"+game.local_player_id,{}).get("context") == target
		"storage": return replica.storage(target) != null
		"kiln": return replica.station(target) != null
	return false
var results: Array = []
var metrics: Dictionary = {"state_bytes":0,"request_bytes":0,"result_bytes":0,"resyncs":0,"latency_msec":0,"results":0,"rejected":0,"largest_part":0}

func configure(g: LeyforgeWave1Playground, s: LfeNetworkSession) -> void:
	game = g; session = s
	process_physics_priority = 30
	if s.mode == "HOST":
		transactions = LfeResourceTransactions.new()
		transactions.configure(g.authority,g.block_catalog,g.resource_world_command)
		transactions.survival_revision = g.survival_system.mutation_revision
		transactions.survival_commit = g.survival_system.changed
	else:
		replica = LfeResourceReplica.new()
		replica.configure(g.block_catalog,g.local_player_id)
	session.packet_received.connect(_packet)
	session.peer_left.connect(_leave)
	session.state_changed.connect(_state)

func _state(state: String, _reason: String) -> void:
	if session.mode == "JOIN" and state == "DISCONNECTED":
		pending.clear(); open_wait.clear(); object_wait.clear(); resync.clear()
		replica.ready = false; replica.states.clear(); replica.revisions.clear(); replica.transfers.clear()
		if game.player != null: game.player.resource_state = null
		if game.inventory_panel != null: game.inventory_panel.hide()

func _leave(peer: int, actor: String) -> void:
	known.erase(peer); queues.erase(peer); initial_sent.erase(peer)
	if transactions != null: transactions.leave(peer,actor)
	game.cancel_actor_harvest(actor)

func _packet(peer: int, bytes: PackedByteArray) -> void:
	# Family dispatch lives at the protocol seam, never in UI.
	var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not value is Dictionary or not value.get("kind") is String or not value["kind"].begins_with("resource_"): return
	var p: Dictionary = LfeResourceProtocol.decode(bytes,game.block_catalog)
	if p.is_empty(): metrics["rejected"] += 1; return
	var now: float = Time.get_ticks_msec()/1000.0
	if session.mode == "HOST":
		var actor: String = session.peer_to_player.get(peer,"")
		if actor.is_empty(): return
		game._sync_active_transform()
		if p["kind"] == "resource_request":
			var response: Dictionary = transactions.execute(peer,actor,p,now)
			if not response.is_empty():
				_send(peer,response)
				if p["operation"] in ["consume","rest"]: game.survival_system.publish(actor,true)
		elif p["kind"] == "resource_resync":
			var rate: Dictionary = transactions.rates.get(peer,{"tokens":16.0,"time":now})
			if now-float(rate.get("resync_time",-1.0)) < 0.2: return
			rate["resync_time"] = now; transactions.rates[peer] = rate
			var all: Dictionary = transactions.observe()
			if transactions.allowed(actor,p["stream"],all) and known.has(peer):
				known[peer].erase(p["stream"]); metrics["resyncs"] += 1
	else:
		if p["kind"] == "resource_result":
			if not pending.has(p["transaction_id"]): return
			var req: Dictionary = pending[p["transaction_id"]]
			metrics["latency_msec"] += Time.get_ticks_msec()-int(req["started"])
			metrics["results"] += 1
			pending.erase(p["transaction_id"])
			results.append(p.duplicate(true))
			if results.size() > 256: results.pop_front()
			if game.player != null:
				var feedback: String = "Hydration disabled in this profile; water retained" if p["reason"] == "thirst_disabled" else "No survival effect; item retained" if p["reason"] == "no_effect" else p["reason"] if not p["success"] else "Resting in shelter; move to stop" if req["packet"]["operation"] == "rest" else "Transaction committed"
				game.player.show_status(feedback,2500)
			if p["success"] and req["packet"]["operation"] == "open_context": open_wait = {"target":req["packet"]["args"]["target"],"deadline":now+5.0}
			if p["success"] and req["packet"]["operation"] == "close_grid" and game.inventory_panel != null: game.inventory_panel.close(true)
		elif p["kind"] in ["resource_part","resource_forget","resource_position","resource_ready"]:
			var applied: Dictionary = replica.receive(p,now)
			if applied.get("fatal",false): session.disconnect_session(); return
			if applied.has("resync"): resync[applied["resync"]] = true
			if not applied.get("ok",false): metrics["rejected"] += 1

func _physics_process(delta: float) -> void:
	if session.mode == "HOST" and session.state == "HOSTING":
		clock += delta
		if clock >= 0.1: clock = 0; _refresh()
		for peer: int in queues:
			var q: Array = queues[peer]
			for i: int in mini(q.size(),8): _send(peer,q.pop_front())
	elif session.mode == "JOIN" and session.state == "CONNECTED":
		var now: float = Time.get_ticks_msec()/1000.0
		for key: String in replica.expire(now): resync[key] = true
		resync_clock += delta
		if resync_clock >= 0.25 and not resync.is_empty():
			resync_clock = 0
			var key: String = resync.keys()[0]
			_send(1,{"kind":"resource_resync","stream":key})
			resync.erase(key); metrics["resyncs"] += 1
		for id: String in pending:
			if Time.get_ticks_msec()-int(pending[id]["sent"]) > 500:
				_send(1,pending[id]["packet"]); pending[id]["sent"] = Time.get_ticks_msec()
			if Time.get_ticks_msec()-int(pending[id]["started"]) > 10000: session.disconnect_session(); return
		if game.player != null and replica.ready and game.inventory_panel == null: game.build_client_resources()
		if game.creation_presenter != null: game.creation_presenter.sync()
		if not object_wait.is_empty():
			var cell: Vector3i = object_wait["cell"]
			if now > float(object_wait["deadline"]): object_wait.clear(); game.player.show_status("Object synchronization timed out; try again")
			elif game.player.inventory_open or not game.player.has_voxel_target() or game.player.get_target_cell() != cell: object_wait.clear()
			elif not replica.object_at(cell).is_empty(): object_wait.clear(); game.targeted_interaction()
		if not open_wait.is_empty() and game.inventory_panel != null:
			var target: String = open_wait["target"]
			if now > float(open_wait["deadline"]): open_wait.clear(); game.player.show_status("Context synchronization timed out")
			elif _context_ready(target):
				open_wait.clear(); game.inventory_panel.open_context(target,false,true)

func _refresh() -> void:
	game._sync_active_transform()
	var all: Dictionary = transactions.observe()
	position_sequence += 1
	for peer: int in session.peer_to_player:
		if peer == session.local_peer_id: continue
		var actor: String = session.peer_to_player[peer]
		if game.voxel_network.initial_ack.get(peer,-1) != 0: continue
		if not known.has(peer): known[peer] = {}; queues[peer] = []
		if queues[peer].size() > 256: continue
		var visible: Dictionary = {}
		for key: String in all:
			if not transactions.allowed(actor,key,all): continue
			if visible.size() >= LfeResourceProtocol.MAX_STREAMS: session.disconnect_player(actor); break
			visible[key] = true
			var revision: int = int(transactions.revisions[key])
			if int(known[peer].get(key,0)) != revision:
				var packets: Array[Dictionary] = LfeResourceProtocol.parts(key,revision,all[key],int(known[peer].get(key,-1)))
				if packets.is_empty() or queues[peer].size()+packets.size() > 4096: session.disconnect_player(actor); break
				queues[peer].append_array(packets)
				known[peer][key] = revision
			elif key.begins_with("drop/"):
				_send(peer,{"kind":"resource_position","stream":key,"revision":revision,"sequence":position_sequence,"position":all[key]["position"]})
		for key: String in known[peer].keys():
			if not visible.has(key):
				queues[peer].append({"kind":"resource_forget","stream":key}); known[peer].erase(key)

		if not initial_sent.has(peer) and session.peer_to_player.has(peer):
			queues[peer].append({"kind":"resource_ready","count":known[peer].size(),"hash":LfeResourceProtocol.normalized(known[peer]).sha256_text()})
			initial_sent[peer] = true

func prepare(op: String, args: Dictionary) -> Dictionary:
	if replica == null or not replica.ready or not pending.is_empty(): return {}
	var a: Dictionary = args.duplicate(true)
	if op in ["transfer","swap"] and not a.has("expected"):
		var inv: LfeInventory = replica.endpoint(a["source"])
		if inv == null: return {}
		a["expected"] = inv.stack_at(int(a["source_slot"]))
	var keys: Array[String] = []
	match op:
		"open_context":
			keys.append("player/"+game.local_player_id)
			if replica.states.has("grid/"+game.local_player_id): keys.append("grid/"+game.local_player_id)
		"select","drop","place","consume": keys.append("player/"+game.local_player_id)
		"pickup": keys.assign(["player/"+game.local_player_id,"drop/"+a["target"]])
		"craft": keys.assign(["player/"+game.local_player_id,"grid/"+game.local_player_id])
		"close_grid":
			keys.append("player/"+game.local_player_id)
			if replica.states.has("grid/"+game.local_player_id): keys.append("grid/"+game.local_player_id)
		"transfer","swap":
			for endpoint: String in [a["source"],a["destination"]]:
				var key: String = LfeResourceTransactions.stream_for(game.local_player_id,endpoint)
				if key.begins_with("storage/") and replica.states.has("object/"+key.get_slice("/",1)): key = "object/"+key.get_slice("/",1)
				keys.append(key)
		"start_process": keys.append("object/"+a["target"])
		"rest": keys.append("object/"+a["target"])
		"source_hold": keys.append("source/"+a["target"])
	var expected: Dictionary = {}
	for key: String in keys: expected[key] = int(replica.revisions.get(key,0))
	sequence += 1
	var id: String = Crypto.new().generate_random_bytes(16).hex_encode()
	var p: Dictionary = {"kind":"resource_request","sequence":sequence,"transaction_id":id,"operation":op,"args":a,"expected_revisions":expected}
	return p

func submit(op: String, args: Dictionary) -> LfeCommandResult:
	var p: Dictionary = prepare(op,args)
	if p.is_empty() or not _send(1,p): return LfeCommandResult.rejected("not_ready")
	pending[p["transaction_id"]] = {"packet":p,"started":Time.get_ticks_msec(),"sent":Time.get_ticks_msec()}
	return LfeCommandResult.accepted({"pending":true})

func _send(peer: int, p: Dictionary) -> bool:
	var bytes: PackedByteArray = LfeResourceProtocol.encode(p,game.block_catalog)
	if bytes.is_empty(): return false
	var kind: String = p["kind"]
	var channel: int = LfeResourceProtocol.POSITION_CHANNEL if kind == "resource_position" else LfeResourceProtocol.STATE_CHANNEL if kind in ["resource_part","resource_forget","resource_ready"] else LfeResourceProtocol.COMMAND_CHANNEL
	var mode: int = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED if kind == "resource_position" else MultiplayerPeer.TRANSFER_MODE_RELIABLE
	if kind == "resource_part":
		metrics["state_bytes"] += bytes.size(); metrics["largest_part"] = maxi(int(metrics["largest_part"]),bytes.size())
	if kind == "resource_request": metrics["request_bytes"] += bytes.size()
	if kind == "resource_result": metrics["result_bytes"] += bytes.size()
	return session.send_packet(peer,bytes,mode,channel) == OK
