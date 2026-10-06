extends "res://tests/networking/w5_5_process.gd"

var survival_trace: Array = []
var falling_trace: Array = []
var suppress_periodic: bool = false
var retained_input: Dictionary = {}

func _survival_loss(peer: int, bytes: PackedByteArray) -> void:
	var p: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if suppress_periodic and p is Dictionary and p.get("kind") == "survival_snapshot": return
	game.survival_system._packet(peer,bytes)

func _command(c: Dictionary) -> void:
	var op: String = c.get("op","")
	if not op.begins_with("survival_"):
		super._command(c); return
	var result: Dictionary = {"op":op}
	var system: LeyforgePlayerSurvival = game.survival_system
	match op:
		"survival_runway":
			var y: int = c["y"]
			var tool: VoxelTool = game.terrain.get_voxel_tool(); tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
			for z: int in range(-80,8):
				for x: int in range(1,3):
					for h: int in range(y-1,y+4):
						var cell: Vector3i = Vector3i(x,h,z)
						var block: StringName = &"leyforge:stone" if h == y-1 else &"leyforge:air"
						if game._commit_voxel(cell,game.block_catalog.get_voxel_id(block),tool) != OK: failures.append("runway fixture commit")
		"survival_set":
			if game.authority == null: failures.append("test fixture must be HOST"); return
			var actor: String = c.get("player_id",game.local_player_id)
			var record: LfePlayerCharacter = game.authority.character(actor)
			var state: Dictionary = record.survival.snapshot()
			state.merge(c.get("values",{}),true)
			if not record.survival.restore(state): failures.append("invalid test biology fixture")
			if c.has("profile") and not record.survival.configure_profile(c["profile"]): failures.append("invalid focused profile")
			system.changed(actor)
		"survival_corrupt":
			var actor: String = c["player_id"]
			var peer: int = game.network_session.player_to_peer[actor]
			var good: Dictionary = system.view(actor)
			for value: Variant in [-1,101,"bad",true]:
				var invalid: Dictionary = good.duplicate(true); invalid["health"] = value
				game.network_session.send_packet(peer,JSON.stringify(invalid).to_utf8_buffer(),MultiplayerPeer.TRANSFER_MODE_RELIABLE,9)
			var extra: Dictionary = good.duplicate(true); extra["damage"] = 0
			game.network_session.send_packet(peer,JSON.stringify(extra).to_utf8_buffer(),MultiplayerPeer.TRANSFER_MODE_RELIABLE,9)
			game.network_session.send_packet(peer,(" ".repeat(1025)+JSON.stringify(good)).to_utf8_buffer(),MultiplayerPeer.TRANSFER_MODE_RELIABLE,9)
		"survival_old_snapshot":
			var peer: int = game.network_session.player_to_peer[c["player_id"]]
			game.movement._send(peer,c["packet"])
		"survival_consume":
			for slot: int in 9:
				if game.personal_resources.inventory.stack_at(slot).get("content") == c["content"]:
					await _tx("select",{"slot":slot})
					result["result"] = await _tx("consume",{})
					result["request"] = last_request.duplicate(true)
					break
		"survival_items":
			var actor: String = c["player_id"]
			var inv: LfeInventory = game.authority.character(actor).resources.inventory
			LfeItemTransactions.add(inv,&"leyforge:provisions",4)
			LfeItemTransactions.add(inv,&"leyforge:drinking_water",3)
			LfeItemTransactions.add(inv,&"leyforge:wooden_pickaxe",1)
			LfeItemTransactions.add(inv,&"leyforge:oak_planks",2)
			game.resource_network._refresh()
		"survival_inventory":
			if c.get("open",true) != game.player.inventory_open: game.toggle_inventory()
		"survival_rest": result["result"] = await _tx("rest",{"target":c["target"]})
		"survival_shelter":
			var actor: String = c["player_id"]
			var body: Variant = system.body_for(actor)
			var feet: Vector3 = body.global_position
			var center: Vector3i = Vector3i((feet+Vector3.UP).floor())
			var tool: VoxelTool = game.terrain.get_voxel_tool(); tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
			for offset: Vector3i in [Vector3i(0,2,0),Vector3i.LEFT*2,Vector3i.RIGHT*2,Vector3i.FORWARD*2]:
				game._commit_voxel(center+offset,game.block_catalog.get_voxel_id(&"leyforge:stone"),tool)
			var cell: Vector3i = Vector3i(feet.floor())+Vector3i.BACK
			game._commit_voxel(cell,game.block_catalog.get_voxel_id(&"leyforge:rest_mat"),tool)
			if not game.creation.add_object(&"leyforge:rest_mat",cell,0): failures.append("rest fixture placement")
			result["target"] = game.creation.object_at(cell)
			result["cell"] = LfeVoxelProtocol.array3(cell)
			game.creation_presenter.sync()
		"survival_rest_invalidate":
			var cell: Vector3i = LfeVoxelProtocol.cell(c["cell"])
			var tool: VoxelTool = game.terrain.get_voxel_tool(); tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
			game._commit_voxel(cell,game.block_catalog.get_voxel_id(&"leyforge:air"),tool)
			game.creation.remove_object(cell)
		"survival_fall":
			var body: LeyforgeAuthoritativePlayerBody = game.movement.bodies[c["player_id"]]
			body.global_position.y += 30.0; body.velocity = Vector3.ZERO; body.sync_record()
			falling_trace.clear()
			result["position"] = LfeMovementProtocol.array3(body.global_position)
		"survival_damage":
			if game.authority == null: failures.append("damage fixture must be trusted host"); return
			var actor: String = c["player_id"]
			result["before"] = game.authority.character(actor).snapshot()
			result["success"] = system.damage(actor,float(c["amount"]))
		"survival_hold_tick":
			game.set_physics_process(not c["hold"])
		"survival_step":
			result["success"] = game.advance_creation(float(c["seconds"]))
		"survival_loss":
			suppress_periodic = c["active"]
			if suppress_periodic:
				game.network_session.packet_received.disconnect(system._packet)
				game.network_session.packet_received.connect(_survival_loss)
			else:
				game.network_session.packet_received.disconnect(_survival_loss)
				game.network_session.packet_received.connect(system._packet)
		"survival_spoof":
			var bytes: PackedByteArray = JSON.stringify(c["packet"]).to_utf8_buffer()
			game.network_session.send_packet(1,bytes,MultiplayerPeer.TRANSFER_MODE_RELIABLE,9)
		"survival_resync":
			system.replica.clear()
		"survival_input_capture":
			retained_input = LfeMovementProtocol.input(game.movement.sequence+1,game.player.consume_movement_intent(),game.movement.input_epoch)
			result["packet"] = retained_input
		"survival_snapshot_capture":
			var peer: int = game.network_session.player_to_peer[c["player_id"]]
			result["packet"] = {"kind":"movement_snapshot","epoch":game.movement.epochs[peer],"tick":game.movement.tick,"states":game.movement._states(game.movement.relevant[peer])}
		"survival_stale_input":
			retained_input["sequence"] = game.movement.sequence+1
			game.movement._send(1,retained_input)
		"survival_sprint_spam":
			for i: int in 30:
				game.movement.sequence += 1
				game.movement._send(1,LfeMovementProtocol.input(game.movement.sequence,{"move":Vector2(0,-1),"jump":false,"sprint":true,"yaw":0.0,"pitch":0.0},game.movement.input_epoch))
		"survival_tick_invariant":
			var before: Dictionary = game.creation.snapshot()
			var biology: Dictionary = {}
			for actor: String in game.authority.characters: biology[actor] = game.authority.character(actor).survival.snapshot()
			var remotes: Array = game.movement.bodies.keys()
			var measures: Array = []
			for count: int in [1,2,3]:
				game.creation.restore(before,game.world_resources.snapshot())
				for actor: String in biology: game.authority.character(actor).survival.restore(biology[actor])
				for i: int in remotes.size(): game.movement.bodies[remotes[i]].ready_for_movement = i < count-1
				for step: int in 20: game.advance_creation(0.1)
				var after: Dictionary = game.creation.snapshot()
				measures.append({"players":count,"elapsed":float(after["elapsed"])-float(before["elapsed"]),"objects":after["objects"],"biology":game.authority.players_snapshot()})
			game.creation.restore(before,game.world_resources.snapshot())
			for actor: String in biology: game.authority.character(actor).survival.restore(biology[actor])
			for actor: String in remotes: game.movement.bodies[actor].ready_for_movement = true
			result["measurements"] = measures
	commands.append(result)

func _extend_report(report: Dictionary) -> void:
	super._extend_report(report)
	var system: LeyforgePlayerSurvival = game.survival_system
	report["survival_ready"] = game.authority != null or system.replica.ready()
	report["survival"] = system.owner_view()
	report["survival_metrics"] = system.metrics.duplicate()
	report["survival_events"] = system.events.duplicate(true)
	report["paused"] = paused; report["time_scale"] = Engine.time_scale
	report["elapsed"] = game.creation.snapshot()["elapsed"] if game.authority != null else 0
	report["survival_hud"] = game.creation_panel._hud.text if game.creation_panel != null else ""
	if game.authority != null:
		report["characters"] = {}
		for actor: String in game.authority.characters: report["characters"][actor] = game.authority.character(actor).snapshot()
		report["rests"] = system.rests.duplicate(); report["shelter"] = system.shelter.duplicate(true)
		for actor: String in game.movement.bodies:
			var body: LeyforgeAuthoritativePlayerBody = game.movement.bodies[actor]
			falling_trace.append({"player_id":actor,"position":LfeMovementProtocol.array3(body.global_position),"velocity":LfeMovementProtocol.array3(body.velocity),"landing_speed":body.landing_speed,"health":body.record.survival.snapshot()["health"],"input_epoch":body.input_epoch,"sprinting":body.activity_sprinting})
		report["falling_trace"] = falling_trace.duplicate(true)
	else: report["input_epoch"] = game.movement.input_epoch
	survival_trace.append({"msec":Time.get_ticks_msec(),"view":report["survival"],"characters":report.get("characters",{}),"position":report.get("position",[]),"hud":report["survival_hud"]})
	if survival_trace.size() > 512: survival_trace.pop_front()
	if falling_trace.size() > 512: falling_trace.pop_front()
	var file: FileAccess = FileAccess.open(directory.path_join(label+"-survival-trace.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(survival_trace,"\t")); file = null
