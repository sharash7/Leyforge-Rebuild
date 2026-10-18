extends "res://tests/networking/w5_8_game_process.gd"

var metrics_samples: Array = []
var _metrics_node: Node
var metric_clock: float = 0.0
var frame_count: int = 0
var frame_usec_total: float = 0.0
var frame_usec_max: float = 0.0
var captured_desktop_motion_events: int = 0
var settled_physics_frames: int = 0
var previous_position: Vector3 = Vector3.INF
var previous_camera: Vector3 = Vector3.INF
var harvest_probe_source: String = ""
var harvest_probe_actor: String = ""
var harvest_probe_trace: Array = []
var early_source_look: Dictionary = {}
var early_aim_observation: Dictionary = {}

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
		_observe_settling()
		if not early_source_look.is_empty() and game.player!=null:
			var destination: Vector3=LfeMovementProtocol.vec3(early_source_look["position"])
			if absf(game.player.global_position.x-destination.x)<0.12 and absf(game.player.global_position.z-destination.z)<0.12:
				await super._command({"op":"source_look","id":early_source_look["source"]})
				early_aim_observation=_harvest_probe()
				early_source_look.clear()
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
	report["settled_physics_frames"]=settled_physics_frames
	report["harvest_probe"]=_harvest_probe()
	report["early_aim_observation"]=early_aim_observation
	if game.world_save!=null:
		report["graph_valid"]=not game.world_save._validate_snapshot(game.authority.players_snapshot(),game.world_resources.snapshot(),game.creation.snapshot(),game.world_save.owner_player_id).is_empty()
	if game.network_session!=null: report["upnp_enabled"]=game.session_options.enable_upnp

func _command(c: Dictionary) -> void:
	if not String(c.get("op","")).begins_with("w59_"):
		await super._command(c);_write_report();return
	var result: Dictionary={"op":c["op"],"msec":Time.get_ticks_msec()}
	match c["op"]:
		"w59_harvest_probe":
			if not harvest_probe_source.is_empty():
				harvest_probe_trace.append(_harvest_probe());_flush_harvest_probe()
			harvest_probe_source=c.get("source","")
			harvest_probe_actor=c.get("actor",game.local_player_id)
		"w59_early_source_look":
			# Diagnostic negative control: expose the old horizontal-only race.
			early_source_look=c.duplicate(true);early_aim_observation={}
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

func _observe_settling() -> void:
	if game.player == null: settled_physics_frames=0; return
	var position: Vector3=game.player.global_position
	var camera: Vector3=game.player.get_camera().global_position
	if game.is_runtime_ready() and game.player.is_on_floor() and absf(game.player.velocity.y)<0.02 and position.distance_to(previous_position)<0.002 and camera.distance_to(previous_camera)<0.002:
		settled_physics_frames+=1
	else: settled_physics_frames=0
	previous_position=position;previous_camera=camera
	if not harvest_probe_source.is_empty():
		harvest_probe_trace.append(_harvest_probe())
		if harvest_probe_trace.size()>1800: harvest_probe_trace.pop_front()
		if Engine.get_physics_frames()%30==0:
			_flush_harvest_probe()

func _flush_harvest_probe() -> void:
	var file: FileAccess=FileAccess.open(directory.path_join(label+"-harvest-probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(harvest_probe_trace));file.close()

func _harvest_probe() -> Dictionary:
	if game.player == null: return {}
	var camera: Camera3D=game.player.get_camera()
	var probe: Dictionary={"msec":Time.get_ticks_msec(),"position":LfeMovementProtocol.array3(game.player.global_position),"velocity":LfeMovementProtocol.array3(game.player.velocity),"grounded":game.player.is_on_floor(),"camera":LfeMovementProtocol.array3(camera.global_position),"direction":LfeMovementProtocol.array3(-camera.global_basis.z),"yaw":game.player.rotation.y,"pitch":game.player.movement_pitch(),"settled_frames":settled_physics_frames,"target_source":game.player.target_source(),"held":Input.is_action_pressed("break_block"),"captured":Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"inventory_open":game.player.inventory_open,"region_ready":game.player.voxel_region_ready}
	if game.voxel_network != null: probe["action_target"]=game.voxel_network.action_target.duplicate(true)
	if not harvest_probe_source.is_empty():
		probe["source"]=game.creation.source(harvest_probe_source)
		probe["visible"]=game.creation_presenter!=null and game.creation_presenter._nodes.has(harvest_probe_source)
		if game.authority!=null and game.movement.bodies.has(harvest_probe_actor):
			var body: LeyforgeAuthoritativePlayerBody=game.movement.bodies[harvest_probe_actor]
			probe["remote"]={"position":LfeMovementProtocol.array3(body.global_position),"velocity":LfeMovementProtocol.array3(body.velocity),"grounded":body.is_on_floor(),"pitch":body.pitch,"yaw":body.rotation.y,"ready":body.ready_for_movement}
			probe["host_source_reason"]=game._actor_source_reason(harvest_probe_actor,harvest_probe_source)
			probe["host_harvest"]=game._actor_harvests.get(harvest_probe_actor,{}).duplicate(true)
	return probe
