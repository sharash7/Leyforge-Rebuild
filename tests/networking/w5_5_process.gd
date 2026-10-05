extends "res://tests/networking/w5_4_process.gd"

var resource_trace: Array = []
var last_request: Dictionary = {}
var transaction_trace: Array = []
var queued: Dictionary = {}
var lose_next_result: bool = false

func _loss_packet(peer: int, bytes: PackedByteArray) -> void:
	var p: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if lose_next_result and p is Dictionary and p.get("kind") == "resource_result":
		lose_next_result = false
		return
	game.resource_network._packet(peer,bytes)


func _tx(op: String, args: Dictionary) -> Dictionary:
	var net: LeyforgeResourceNetwork = game.resource_network
	var deadline: int = Time.get_ticks_msec()+6000
	while not net.pending.is_empty() and Time.get_ticks_msec() < deadline: await physics_frame
	var before: int = net.results.size()
	var result: LfeCommandResult = game.command(game.local_player_id,op,args)
	if not result.success: return {"success":false,"reason":result.reason_code}
	if not net.pending.is_empty(): last_request = net.pending.values()[0]["packet"].duplicate(true)
	while net.results.size() == before and Time.get_ticks_msec() < deadline: await physics_frame
	if net.results.size() == before: return {"success":false,"reason":"timeout"}
	var response: Dictionary = net.results.back()
	transaction_trace.append(response)
	# Result/state channels are independent. Await matching owner facts before the next UI action.
	await create_timer(0.25).timeout
	return response

func _move(content: String, count: int, endpoint: String, destination_slot: int, source: String = "inventory") -> Dictionary:
	var inv: LfeInventory = game.resource_network.replica.endpoint(source)
	if inv == null: return {"success":false,"reason":"missing endpoint"}
	for slot: int in inv.capacity():
		var stack: Dictionary = inv.stack_at(slot)
		if stack.get("content") == content:
			return await _tx("transfer",{"source":source,"destination":endpoint,"source_slot":slot,"destination_slot":destination_slot,"quantity":count,"expected":stack})
	return {"success":false,"reason":"missing "+content}

func _craft(recipe: String, inputs: Array) -> bool:
	for item: Dictionary in inputs:
		var moved: Dictionary = await _move(item["content"],int(item["quantity"]),"grid",int(item["slot"]))
		if not moved.get("success",false): failures.append("craft staging "+str(moved)); return false
	var result: Dictionary = await _tx("craft",{"recipe":recipe})
	if not result.get("success",false): failures.append("craft "+recipe+" "+str(result)); return false
	return true

func _command(c: Dictionary) -> void:
	var op: String = c.get("op","")
	if op not in ["resource","progression","resource_drop","retry","resource_fixture","resource_resync","source_look","source_place","equip","resource_capture","resource_move","tool_progression","gather_one","resource_queue","resource_release","resource_pause_pickup","lost_result"]:
		super._command(c); return
	var result: Dictionary = {"op":op}
	match op:
		"resource_pause_pickup":
			game.resource_presenter.set_physics_process(not c["active"])
		"lost_result":
			var net: LeyforgeResourceNetwork = game.resource_network
			net.session.packet_received.disconnect(net._packet)
			net.session.packet_received.connect(_loss_packet)
			lose_next_result = true
			result["result"] = await _tx(c["operation"],c["args"])
			net.session.packet_received.disconnect(_loss_packet)
			net.session.packet_received.connect(net._packet)
			result["request"] = last_request
		"resource_queue":
			var operation: String = c["operation"]
			var args: Dictionary = c.get("args",{}).duplicate(true)
			if operation == "transfer":
				var inventory: LfeInventory = game.resource_network.replica.endpoint(args["source"])
				for slot: int in inventory.capacity():
					if inventory.stack_at(slot).get("content") == c["content"]:
						args["source_slot"] = slot; args["expected"] = inventory.stack_at(slot); break
			if operation == "place":
				for slot: int in 9:
					if game.personal_resources.inventory.stack_at(slot).get("content") == c["content"]:
						await _tx("select",{"slot":slot})
						args["slot"] = slot; args["expected"] = game.personal_resources.inventory.stack_at(slot); break
			queued = game.resource_network.prepare(operation,args)
			result["request"] = queued
			if queued.is_empty(): failures.append("cannot prepare race request")
		"resource_release":
			var net: LeyforgeResourceNetwork = game.resource_network
			var before: int = net.results.size()
			net._send(1,queued)
			net.pending[queued["transaction_id"]] = {"packet":queued,"started":Time.get_ticks_msec(),"sent":Time.get_ticks_msec()}
			last_request = queued.duplicate(true)
			var until: int = Time.get_ticks_msec()+6000
			while net.results.size() == before and Time.get_ticks_msec() < until: await physics_frame
			result["result"] = net.results.back() if net.results.size() > before else {"success":false,"reason":"timeout"}
			await create_timer(0.3).timeout
		"gather_one":
			var cell: Vector3i = LfeVoxelProtocol.cell(c["cell"])
			var direction: Vector3 = Vector3(cell)+Vector3.ONE*0.5-game.player.get_camera().global_position
			game.player.set_movement_look(atan2(-direction.x,-direction.z),atan2(direction.y,Vector2(direction.x,direction.z).length()))
			await create_timer(0.3).timeout
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Input.action_press("break_block")
			var until: int = Time.get_ticks_msec()+7000
			var tool: VoxelTool = game.terrain.get_voxel_tool(); tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
			while tool.get_voxel(cell) != 0 and Time.get_ticks_msec() < until: await physics_frame
			Input.action_release("break_block")
			result["removed"] = tool.get_voxel(cell) == 0
			if not result["removed"]: failures.append("held gather target timeout "+str(cell))
		"resource":
			if game.session_options.mode == "JOIN": result["result"] = await _tx(c["operation"],c.get("args",{}))
			else: result["result"] = {"success":game.command(game.local_player_id,c["operation"],c.get("args",{})).success}
		"resource_drop":
			for slot: int in 9:
				if game.personal_resources.inventory.stack_at(slot).get("content") == c["content"]:
					result["select"] = await _tx("select",{"slot":slot})
					result["result"] = await _tx("drop_selected",{"whole_stack":c.get("whole_stack",false)})
					break
		"retry":
			if last_request.is_empty(): failures.append("no transaction for retry")
			else:
				for i: int in 8: game.resource_network._send(1,last_request)
				var modified: Dictionary = last_request.duplicate(true)
				if modified["args"].has("quantity"): modified["args"]["quantity"] = int(modified["args"]["quantity"])+1
				else: modified["args"]["invalid"] = true
				game.network_session.send_packet(1,JSON.stringify(modified).to_utf8_buffer(),MultiplayerPeer.TRANSFER_MODE_RELIABLE,7)
				result["transaction_id"] = last_request["transaction_id"]
		"progression":
			var response: Dictionary = await _tx("open_context",{"target":""})
			if not response.get("success",false): failures.append("personal context")
			# Three gathered logs yield twelve canonical planks.
			for i: int in 3:
				await _craft("leyforge:saw_planks",[{"content":"leyforge:oak_heartwood","quantity":1,"slot":0}])
			await _craft("leyforge:split_oak_sticks",[{"content":"leyforge:oak_planks","quantity":1,"slot":0}])
			await _craft("leyforge:build_workbench",[{"content":"leyforge:oak_planks","quantity":1,"slot":0},{"content":"leyforge:oak_planks","quantity":1,"slot":1},{"content":"leyforge:oak_planks","quantity":1,"slot":2},{"content":"leyforge:oak_planks","quantity":1,"slot":3}])
			await _tx("close_grid",{})
			result["inventory"] = game.personal_resources.snapshot()
		"resource_move":
			result["result"] = await _move(c["content"],int(c["quantity"]),c["destination"],int(c.get("destination_slot",-1)),c.get("source","inventory"))
		"tool_progression":
			await _tx("open_context",{"target":c["id"]})
			var heads: String = c.get("heads","leyforge:oak_planks")
			await _craft(c.get("recipe","leyforge:craft_wooden_pickaxe"),[{"content":heads,"quantity":1,"slot":0},{"content":heads,"quantity":1,"slot":1},{"content":heads,"quantity":1,"slot":2},{"content":"leyforge:oak_stick","quantity":1,"slot":4},{"content":"leyforge:oak_stick","quantity":1,"slot":7}])
			await _tx("close_grid",{})
		"equip":
			result["result"] = await _move(c["content"],1,"equipment",0)
		"resource_fixture":
			# Isolated adversarial shared-endpoint fixtures are distinct from real gathering/crafting proof.
			var cell: Vector3i = LfeVoxelProtocol.cell(c["cell"])
			var tool: VoxelTool = game.terrain.get_voxel_tool(); tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
			if c["kind"] == "storage":
				var id: String = game.world_resources.snapshot()["storage"][0]["instance"]
				result["id"] = id; result["position"] = game.world_resources.snapshot()["storage"][0]["position"]
			elif c["kind"] == "kiln":
				game._commit_voxel(cell,game.block_catalog.get_voxel_id(&"leyforge:kiln"),tool)
				game.creation.add_object(&"leyforge:kiln",cell,0)
				result["id"] = game.creation.object_at(cell)
				var station: LfeWorkstation = game.creation.station(result["id"])
				LfeItemTransactions.add(station.input,&"leyforge:oak_heartwood",2)
				LfeItemTransactions.add(station.fuel,&"leyforge:oak_heartwood",1)
			game.resource_network._refresh()
		"resource_resync":
			var key: String = "player/"+game.local_player_id
			game.resource_network.replica.revisions[key] = int(game.resource_network.replica.revisions[key])+1
			game.resource_network.resync[key] = true
			result["before"] = game.resource_network.replica.personal.snapshot()
		"source_look":
			var s: Dictionary = game.creation.source(c["id"])
			var p: Array = s["position"]
			var target: Vector3 = Vector3(float(p[0]),floorf(float(p[1]))+0.4,float(p[2]))
			var direction: Vector3 = target-game.player.get_camera().global_position
			game.player.set_movement_look(atan2(-direction.x,-direction.z),atan2(direction.y,Vector2(direction.x,direction.z).length()))
		"source_place":
			var cell: Vector3i = LfeVoxelProtocol.cell(c["cell"])
			for slot: int in 9:
				if game.personal_resources.inventory.stack_at(slot).get("content") == c["content"]:
					await _tx("select",{"slot":slot})
					result["result"] = await _tx("place_cell",{"cell":cell})
					break
		"resource_capture":
			await process_frame; await RenderingServer.frame_post_draw
			result["screenshot"] = directory.path_join(label+"-resources-"+str(commands.size())+".png")
			root.get_texture().get_image().save_png(result["screenshot"])
	commands.append(result)

func _extend_report(report: Dictionary) -> void:
	super._extend_report(report)
	var net: LeyforgeResourceNetwork = game.resource_network
	if net == null: return
	if game.resource_presenter != null: game.resource_presenter.sync()
	report["resource_metrics"] = net.metrics
	report["transaction_trace"] = transaction_trace
	report["resource_ready"] = game.authority != null or net.replica.ready
	report["personal"] = game.personal_resources.snapshot() if game.personal_resources != null else {}
	if game.authority != null:
		report["resource_streams"] = net.transactions.streams()
		report["resource_revisions"] = net.transactions.revisions
		report["resource_commits"] = net.transactions.commits
		var slots: Array = []
		for state: Dictionary in net.transactions.streams().values():
			if state.has("inventory"): slots.append_array(state["inventory"]); slots.append_array(state["equipment"])
			if state.has("slots"): slots.append_array(state["slots"])
			if state.has("stack"): slots.append(state["stack"])
			if state.has("station"):
				for part: String in ["input","fuel","output"]: slots.append_array(state["station"][part])
		report["instances_unique"] = LfeWorldResourceState.unique_instances(slots)
		report["sources"] = game.creation.sources()
		report["objects"] = game.creation.objects()
		report["totals"] = {}
		for id: StringName in game.block_catalog._definitions_by_id.keys()+game.block_catalog._items_by_id.keys():
			if game.block_catalog.is_inventory_content(id): report["totals"][String(id)] = game.authority.total(id)
	else:
		report["resource_streams"] = net.replica.states
		report["resource_revisions"] = net.replica.revisions
		report["no_authority"] = game.authority == null and game.world_save == null and game.active_character == null
		report["drop_nodes"] = game.resource_presenter._nodes.keys() if game.resource_presenter != null else []
		report["source_nodes"] = game.creation_presenter._nodes.keys() if game.creation_presenter != null else []
	resource_trace.append({"msec":Time.get_ticks_msec(),"personal":report["personal"],"streams":report["resource_streams"],"revisions":report["resource_revisions"]})
	if resource_trace.size() > 256: resource_trace.pop_front()
	var file: FileAccess = FileAccess.open(directory.path_join(label+"-resource-trace.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(resource_trace,"\t")); file = null
