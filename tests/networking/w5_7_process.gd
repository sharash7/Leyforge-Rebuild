extends "res://tests/networking/w5_6_repair_process.gd"

var lifecycle_trace: Array = []
var prior_generation: int = 0
var ended_captured: int = -1
var remembered_personal: Dictionary = {}
var remembered_survival: Dictionary = {}
var loaded_graph_hash: String = ""
var dropped_results: int = 0

func _discard_resource_results(peer: int, bytes: PackedByteArray) -> void:
	var packet: Dictionary = LfeResourceProtocol.decode(bytes,game.block_catalog)
	if packet.get("kind") == "resource_result": dropped_results += 1; return
	game.resource_network._packet(peer,bytes)

func _run() -> void:
	directory = OS.get_environment("LEYFORGE_REPAIR_PROOF_DIR")
	label = OS.get_environment("LEYFORGE_REPAIR_PROOF_NAME")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--proof-dir="): directory = arg.trim_prefix("--proof-dir=")
		if arg.begins_with("--proof-name="): label = arg.trim_prefix("--proof-name=")
	if not directory.is_absolute_path() or label.is_empty(): quit(1); return
	started = Time.get_ticks_msec()
	game = load("res://scenes/main/wave_1_playground.tscn").instantiate()
	root.add_child(game)
	await process_frame
	while Time.get_ticks_msec()-started < 600000 and not stop_requested:
		await physics_frame
		var path: String = directory.path_join(label+".command.json")
		if FileAccess.file_exists(path):
			var source: String = FileAccess.get_file_as_string(path)
			var parser: JSON = JSON.new()
			if not source.is_empty() and parser.parse(source) == OK and parser.data is Dictionary:
				DirAccess.remove_absolute(path)
				await _command(parser.data)
		if FileAccess.file_exists(directory.path_join(label+".stop")): stop_requested = true
		if game.network_session == null: continue
		if game.session_options.mode == "JOIN" and not game._teardown_pending and game.terrain == null and game.session_generation != ended_captured and not game.teardown_facts.is_empty():
			ended_captured = game.session_generation
			await _capture("ended-"+str(ended_captured))
		report_clock += 1.0/60
		if report_clock >= 0.1: report_clock = 0; _write_report()
	_write_report()
	game.request_client_leave() if game.session_options.mode == "JOIN" else game.network_session.disconnect_session()
	await create_timer(0.2).timeout
	quit(0 if failures.is_empty() else 1)

func _command(c: Dictionary) -> void:
	if not String(c.get("op","")).begins_with("w57_"):
		await super._command(c)
		if c.get("op") == "retry": game.resource_network.sequence = maxi(game.resource_network.sequence,int(last_request.get("sequence",0)))
		return
	var result: Dictionary = {"op":c["op"],"msec":Time.get_ticks_msec()}
	match c["op"]:
		"w57_commit_without_result":
			var net: LeyforgeResourceNetwork = game.resource_network
			net.session.packet_received.disconnect(net._packet)
			net.session.packet_received.connect(_discard_resource_results)
			var slot: int = game.personal_resources.selected_slot()
			var packet: Dictionary = net.prepare("drop",{"slot":slot,"quantity":1,"expected":game.personal_resources.inventory.stack_at(slot)})
			last_request = packet.duplicate(true)
			result["sent"] = not packet.is_empty() and net._send(1,packet)
			net.pending[packet["transaction_id"]] = {"packet":packet,"started":Time.get_ticks_msec(),"sent":Time.get_ticks_msec()}
		"w57_save_measure":
			var begun: int = Time.get_ticks_usec()
			result["saved"] = game.request_save()
			result["save_msec"] = (Time.get_ticks_usec()-begun)/1000.0
		"w57_leave":
			remembered_personal = game.personal_resources.snapshot()
			remembered_survival = game.survival_system.replica.snapshot()
			prior_generation = game.session_generation
			game.request_client_leave()
		"w57_reconnect":
			# Physical pointer dispatch to the actual visible owner control.
			await _button(game.session_view.reconnect_button)
		"w57_f10":
			var key: InputEventKey = InputEventKey.new(); key.keycode=KEY_F10; key.pressed=true
			Input.parse_input_event(key)
			await create_timer(0.05).timeout
		"w57_window_close":
			# The verifier also uses OS CloseMainWindow for graphical WM_CLOSE proof.
			root.close_requested.emit()
		"w57_stage_full":
			var actor: String = c["player_id"]
			var record: LfePlayerCharacter = game.authority.character(actor)
			var grid: LfeCraftingGrid = game.authority.open_grid(actor)
			LfeItemTransactions.add(grid.inventory,&"leyforge:oak_stick",1)
			var slots: Array = record.resources.inventory.snapshot()
			for i: int in slots.size(): slots[i] = LfeItemStack.make(&"leyforge:stone",game.block_catalog.stack_limit(&"leyforge:stone"))
			record.resources.inventory.restore(slots)
			game.resource_network._refresh()
			result["grid"] = grid.inventory.snapshot()
		"w57_resolve_capacity":
			var slots: Array = game.authority.character(c["player_id"]).resources.inventory.snapshot()
			slots[0] = null
			game.authority.character(c["player_id"]).resources.inventory.restore(slots)
			game.resource_network._refresh()
		"w57_shutdown_blocked": result["accepted"] = game.request_save_and_quit()
		"w57_record_fixture":
			var record: LfePlayerCharacter = game.authority.character(c["player_id"])
			var tool: Dictionary = LfeItemInstance.create(&"leyforge:wooden_pickaxe",game.block_catalog)
			tool["durability"] = 7
			var slots: Array = record.resources.equipment.snapshot(); slots[0]=tool
			if not record.resources.equipment.restore(slots): failures.append("invalid worn tool fixture")
			var state: Dictionary = record.survival.snapshot(); state["thirst"]=37.0;state["fatigue"]=11.0;state["exposure"]=9.0;state["stamina"]=47.0
			record.survival.restore(state);game.survival_system.changed(c["player_id"])
			game.resource_network._refresh()
		"w57_stale_callback":
			var before: Dictionary = game.movement.latest_self.duplicate(true)
			game._teardown_joined_world(prior_generation)
			await game._finish_startup(prior_generation)
			result["unchanged"] = game.is_runtime_ready() and game.movement.latest_self == before
		"w57_ui":
			if c.get("manual",false):
				await _key(KEY_I)
				# Result and initial context facts use different reliable channels.
				# Wait for the actual authorized panel and its layout before clicking.
				var deadline: int = Time.get_ticks_msec()+6000
				while (not game.inventory_panel._panel.visible or not game.resource_network.open_wait.is_empty()) and Time.get_ticks_msec()<deadline: await physics_frame
				await process_frame
				await RenderingServer.frame_post_draw
				await _button(game.inventory_panel.find_child("OpenCraftingManual",true,false))
				result["pointer"] = pointer_fact.duplicate()
				await _capture("manual-before-loss-"+str(commands.size()))
			else: await _key(KEY_I)
			result["ui_open"] = game.player.inventory_open
			result["manual_visible"] = game.inventory_panel.manual.visible
		"w57_context":
			var response: Dictionary = await _tx("open_context",{"target":c["id"]})
			result["accepted"] = response.get("success",false)
			await _settle_ui()
			result["opened"] = game.player.inventory_open
		"w57_pending":
			var packet: Dictionary = game.resource_network.prepare("select",{"slot":1})
			game.resource_network.pending[packet["transaction_id"]] = {"packet":packet,"started":Time.get_ticks_msec(),"sent":Time.get_ticks_msec()}
			result["pending"] = game.resource_network.pending.size()
		"w57_capture": await _capture(c.get("name","lifecycle"))
		"w57_silence": game.network_session.set_process(not c["hold"])
	commands.append(result)
	_write_report()

func _write_report() -> void:
	var net: LfeNetworkSession = game.network_session
	if net == null: return
	var report: Dictionary = {"pid":OS.get_process_id(),"name":label,"state":net.state,"reason":net.reason_code,"ready":game.is_runtime_ready(),"player_id":game.local_player_id,"commands":commands,"failures":failures,"passed":failures.is_empty(),"bindings":net.peer_to_player.duplicate(),"world":net.world_manifest.duplicate(true),"generation":game.session_generation,"msec":Time.get_ticks_msec(),"teardown":game.teardown_facts,"terrain_exists":game.terrain != null,"player_exists":game.player != null,"no_world_save":not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://worlds")),"no_authority":game.world_save==null and game.authority==null,"ended_visible":game.session_view!=null and game.session_view._ended.visible,"previous_world":game.previous_world_id,"remembered_personal":remembered_personal,"remembered_survival":remembered_survival}
	report["lifecycle_metrics"] = net.lifecycle_metrics.duplicate()
	report["dropped_results"] = dropped_results
	report["pending_count"] = game.resource_network.pending.size() if game.resource_network != null else 0
	report["held_actions"] = game._actor_harvests.duplicate(true)
	report["scene_children"] = game.get_children().map(func(node: Node) -> String: return node.get_class()+":"+node.name)
	report["world_node_count"] = game.get_children().filter(func(node: Node) -> bool: return node is Node3D).size()
	if game.player != null:
		report["position"]=LfeMovementProtocol.array3(game.player.global_position);report["velocity"]=LfeMovementProtocol.array3(game.player.velocity);report["grounded"]=game.player.is_on_floor()
	if game.movement != null:
		report["avatars"]=game.movement.avatars.keys();report["bodies"]={}
		for id: String in game.movement.bodies: report["bodies"][id]={"state":game.movement.bodies[id].state(),"viewer_exists":is_instance_valid(game.movement.bodies[id].viewer)}
	if game.resource_network != null and game.survival_system != null and game.is_runtime_ready():
		super._extend_report(report)
		report["overrides"]=(game.world_save.overrides if game.world_save!=null else game.client_voxel_overrides).serialized_entries()
		report["personal_hash"]=LfeResourceProtocol.normalized(report["personal"]).sha256_text()
	if game.authority != null:
		report["roster"]=game.authority.players_snapshot();report["grids"]={}
		for id: String in game.authority._grids: report["grids"][id]=game.authority._grids[id].inventory.snapshot()
		var saved_graph: Dictionary = {"players":game.world_save.players_state,"resources":game.world_save.world_resource_state,"creation":game.world_save.creation_state,"overrides":game.world_save.overrides.serialized_entries()}
		if loaded_graph_hash.is_empty(): loaded_graph_hash = LfeResourceProtocol.normalized(saved_graph).sha256_text()
		report["loaded_graph_hash"] = loaded_graph_hash
		report["saved_graph_hash"] = LfeResourceProtocol.normalized(saved_graph).sha256_text()
		report["durable_roster_hash"] = LfeResourceProtocol.normalized(game.world_save.players_state).sha256_text()
		report["save_status"]=game.world_save.save_status;report["load_status"]=game.world_save.load_status
		report["shutdown_fence"]=game._host_closing
	lifecycle_trace.append({"msec":Time.get_ticks_msec(),"state":net.state,"reason":net.reason_code,"generation":game.session_generation,"ready":game.is_runtime_ready(),"terrain":game.terrain!=null})
	if lifecycle_trace.size()>1800:lifecycle_trace.pop_front()
	var target: String = directory.path_join(label+".json")
	var file: FileAccess = FileAccess.open(target+".pending",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.flush();file=null
	DirAccess.rename_absolute(target+".pending",target)
	file=FileAccess.open(directory.path_join(label+"-lifecycle.json"),FileAccess.WRITE);file.store_string(JSON.stringify(lifecycle_trace,"\t"));file=null
