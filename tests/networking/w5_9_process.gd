extends "res://tests/networking/w5_8_game_process.gd"

var metrics_samples: Array = []
var _metrics_node: Node
var metric_clock: float = 0.0
var frame_count: int = 0
var frame_usec_total: float = 0.0
var frame_usec_max: float = 0.0
var captured_desktop_motion_events: int = 0

class MetricsSampler extends Node:
	var driver: Variant
	func _process(delta: float) -> void: driver._sample_metrics(delta)
	func _input(event: InputEvent) -> void:
		# Several graphical processes share one desktop cursor. Capturing it in
		# another window must not rotate a fixture's explicitly set test aim.
		# Visible GUI pointer events still follow the normal dispatch path.
		if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
			driver.captured_desktop_motion_events+=1
			get_viewport().set_input_as_handled()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--proof-dir="): directory=arg.trim_prefix("--proof-dir=")
		if arg.begins_with("--proof-name="): label=arg.trim_prefix("--proof-name=")
	if not directory.is_absolute_path() or label.is_empty(): quit(1);return
	started=Time.get_ticks_msec()
	game=load("res://scenes/main/wave_1_playground.tscn").instantiate();root.add_child(game)
	_metrics_node=MetricsSampler.new();_metrics_node.driver=self;root.add_child(_metrics_node)
	while Time.get_ticks_msec()-started<2400000 and not stop_requested:
		await physics_frame
		var path: String=directory.path_join(label+".command.json")
		if FileAccess.file_exists(path):
			var parser: JSON=JSON.new()
			if parser.parse(FileAccess.get_file_as_string(path))==OK and parser.data is Dictionary:
				DirAccess.remove_absolute(path);await _command(parser.data)
		if FileAccess.file_exists(directory.path_join(label+".stop")): stop_requested=true
		if relocate_wait and game.player!=null and game.movement_area_ready(game.player.global_position):
			game.player.set_runtime_ready(true);relocate_wait=false
		report_clock+=1.0/60
		if report_clock>=0.5: report_clock=0;_write_report()
	_write_report()
	if game.network_session!=null:
		if game.session_options.mode=="JOIN": game.request_client_leave()
		else: game.network_session.disconnect_session()
	await create_timer(0.2).timeout
	quit(0 if failures.is_empty() else 1)

func _sample_metrics(delta: float) -> void:
	frame_count+=1;frame_usec_total+=delta*1000000;frame_usec_max=maxf(frame_usec_max,delta*1000000)
	metric_clock+=delta
	if metric_clock<2 or game==null or game.network_session==null: return
	metric_clock=0
	var sample: Dictionary={"msec":Time.get_ticks_msec(),"frames":frame_count,"frame_interval_mean_msec":frame_usec_total/maxi(1,frame_count)/1000.0,"frame_interval_max_msec":frame_usec_max/1000.0,"process_msec":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_msec":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"static_memory_bytes":OS.get_static_memory_usage(),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"transport":game.network_session.lifecycle_metrics.duplicate(),"commands":commands.size(),"reliable_queue":game.network_session.outbound.size(),"ready":game.is_runtime_ready()}
	sample["gameplay_transport"]=game.network_session.get("gameplay_metrics").duplicate()
	if game.terrain!=null: sample["terrain"]=game.terrain.get_statistics()
	if game.movement!=null:
		sample["bodies"]=game.movement.bodies.size();sample["avatars"]=game.movement.avatars.size()
	if game.resource_network!=null:
		sample["resource_commands"]=game.resource_network.transactions.commits if game.authority!=null else int(game.resource_network.metrics.get("results",0))
	if game.voxel_network!=null:
		sample["voxel_interest_buckets"]={}
		for peer: int in game.voxel_network.known: sample["voxel_interest_buckets"][str(peer)]=game.voxel_network.known[peer].size()
	metrics_samples.append(sample)
	if metrics_samples.size()>1200: metrics_samples.pop_front()

func _extend_quality_report(report: Dictionary) -> void:
	super._extend_quality_report(report)
	report["measurements"]=metrics_samples
	report["captured_desktop_motion_events"]=captured_desktop_motion_events
	if game.world_save!=null:
		report["graph_valid"]=not game.world_save._validate_snapshot(game.authority.players_snapshot(),game.world_resources.snapshot(),game.creation.snapshot(),game.world_save.owner_player_id).is_empty()
	if game.network_session!=null: report["upnp_enabled"]=game.session_options.enable_upnp

func _command(c: Dictionary) -> void:
	if not String(c.get("op","")).begins_with("w59_"):
		await super._command(c);_write_report();return
	var result: Dictionary={"op":c["op"],"msec":Time.get_ticks_msec()}
	match c["op"]:
		"w59_boundary_arena":
			var y: int=int(c["y"])
			var tool: VoxelTool=game.terrain.get_voxel_tool();tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
			for x: int in range(13,19):
				for z: int in range(-1,5):
					for h: int in range(y-1,y+4):
						var block: StringName=&"leyforge:stone" if h==y-1 else &"leyforge:air"
						if game._commit_voxel(Vector3i(x,h,z),game.block_catalog.get_voxel_id(block),tool)!=OK: failures.append("boundary arena fixture commit")
		"w59_seed_personal":
			result["added"]=LfeItemTransactions.add(game.authority.character(c["player_id"]).resources.inventory,StringName(c["content"]),int(c["quantity"]))
			game.resource_network._refresh()
		"w59_capture": await _capture(c["file"])
		"w59_aim": await _aim(LfeMovementProtocol.vec3(c["point"]))
		"w59_seed_endpoint":
			var inventory: LfeInventory
			if c["family"]=="storage": inventory=game.creation.storage(c["id"])
			else: inventory=game.creation.station(c["id"]).get(c["family"])
			if c.get("full",false):
				var slots: Array=inventory.snapshot()
				for slot: int in slots.size():
					if slots[slot]==null: slots[slot]=LfeItemStack.make(&"leyforge:stone",game.block_catalog.stack_limit(&"leyforge:stone"))
				result["restored"]=inventory.restore(slots)
			else: result["added"]=LfeItemTransactions.add(inventory,StringName(c["content"]),int(c["quantity"]))
			game.resource_network._refresh()
		"w59_fixture":
			var cell: Vector3i=LfeVoxelProtocol.cell(c["cell"])
			if not game.creation.object_at(cell).is_empty(): game.creation.remove_object(cell)
			var tool: VoxelTool=game.terrain.get_voxel_tool();tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
			result["error"]=game._commit_voxel(cell,game.block_catalog.get_voxel_id(StringName(c["content"])),tool)
			result["added"]=game.creation.add_object(StringName(c["content"]),cell,0)
			result["id"]=game.creation.object_at(cell);game.resource_network._refresh()
		"w59_malformed":
			# Bounded injection through the real authenticated transport. Never an RPC.
			var count: int=0
			var sent: int=0
			for channel: int in [1,3,4,5,6,7,8,9,10,11]:
				for text: String in ["{}","[]",'{"kind":null}', '{"kind":"movement_input","player_id":"spoof"}'," ".repeat(9000)+"{}"]:
					if game.network_session.send_packet(1,text.to_utf8_buffer(),MultiplayerPeer.TRANSFER_MODE_RELIABLE,channel)==OK: sent+=1
					count+=1
			result["attempted"]=count;result["sent"]=sent;result["rejected_before_send"]=count-sent
		"w59_graph":
			result["valid"]=not game.world_save._validate_snapshot(game.authority.players_snapshot(),game.world_resources.snapshot(),game.creation.snapshot(),game.world_save.owner_player_id).is_empty()
		"w59_io_block":
			# Disposable profile only: a directory at the pending-file path causes
			# FileAccess.open to fail without touching a committed checkpoint.
			var path: String=game.world_save.get_world_directory().path_join(LfeWorldSave.PENDING_FILE)
			if c.get("active",true): result["error"]=DirAccess.make_dir_absolute(path)
			else: result["error"]=DirAccess.remove_absolute(path)
		"w59_motion":
			_release()
			if c.get("direction","stop")!="stop": Input.action_press(c["direction"])
			if c.get("sprint",false): Input.action_press("sprint")
			if c.get("jump",false): Input.action_press("jump")
		"w59_freeze": game.set_physics_process(not c["active"])
	commands.append(result);_write_report()
