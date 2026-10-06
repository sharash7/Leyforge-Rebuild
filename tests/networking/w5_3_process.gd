extends SceneTree

var game: LeyforgeWave1Playground
var directory: String
var label: String
var started: int
var ready_at: int = 0
var commands: Array = []
var trace: Array = []
var failures: Array = []
var stop_requested: bool = false
var jumping: bool = false
var jump_clock: float = 0.0
var prediction: Dictionary = {}
var relocate_wait: bool = false
var report_clock: float = 0.0

func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--proof-dir="): directory = arg.trim_prefix("--proof-dir=")
		if arg.begins_with("--proof-name="): label = arg.trim_prefix("--proof-name=")
	if not directory.is_absolute_path() or label.is_empty(): quit(1); return
	started = Time.get_ticks_msec()
	game = load("res://scenes/main/wave_1_playground.tscn").instantiate()
	root.add_child(game)
	while Time.get_ticks_msec() - started < (600000 if OS.get_cmdline_user_args().has("--w55-proof") or OS.get_cmdline_user_args().has("--w56-proof") else 180000) and not stop_requested:
		await physics_frame
		if game.network_session == null: continue
		var path: String = directory.path_join(label+".command.json")
		if FileAccess.file_exists(path):
			var parser: JSON = JSON.new()
			var command_source: String = FileAccess.get_file_as_string(path)
			# Windows sharing/scan races can temporarily return no readable bytes.
			# Retain the command and retry; the enclosing wait still fails boundedly.
			if not command_source.is_empty() and parser.parse(command_source) == OK and parser.data is Dictionary:
				DirAccess.remove_absolute(path)
				_command(parser.data)
		if FileAccess.file_exists(directory.path_join(label+".stop")): stop_requested = true
		if game.is_runtime_ready() and ready_at == 0:
			ready_at = Time.get_ticks_msec()
			if game.session_options.mode == "JOIN":
				if game.authority != null or game.world_save != null or game.active_character != null or (game.player.resource_state != null and game.player.resource_state != game.resource_network.replica.personal): failures.append("JOIN gained authority")
				if game.request_save(): failures.append("JOIN gained save permission")
				if game.player.resource_state == null and (game.player.try_break_target() or game.player.try_place_target()): failures.append("JOIN interaction before resource readiness")
		if jumping and game.player != null and game.player.is_runtime_ready():
			jump_clock += 1.0 / 60.0
			Input.action_release("jump")
			if jump_clock >= 0.85:
				jump_clock = 0
				Input.action_press("jump")
		if relocate_wait and game.movement_area_ready(game.player.global_position):
			game.player.set_runtime_ready(true)
			relocate_wait = false
		if not prediction.is_empty() and not prediction.has("displacement") and Time.get_ticks_msec() >= int(prediction["until"]):
			prediction["displacement"] = game.player.global_position.distance_to(LfeMovementProtocol.vec3(prediction["start"]))
			prediction["ack_after"] = game.movement.latest_self.get("ack",0)
			prediction["sequence_after"] = game.movement.sequence
			prediction["predicted_after"] = LfeMovementProtocol.array3(game.player.global_position)
			game.movement.send_enabled = true
		report_clock += 1.0 / 60.0
		if report_clock >= 0.1:
			report_clock = 0.0
			_write_report()
		if game.session_options.mode == "JOIN" and game.network_session.state == "DISCONNECTED":
			_write_report()
			break
	_write_report()
	if game.network_session != null: game.network_session.disconnect_session()
	await create_timer(0.2).timeout
	quit(0 if failures.is_empty() else 1)

func _command(command: Dictionary) -> void:
	var operation: String = command.get("op","")
	var result: Dictionary = {"op":operation,"msec":Time.get_ticks_msec()}
	match operation:
		"move":
			_release()
			var direction: String = command.get("direction","move_forward")
			if direction != "stop": Input.action_press(direction)
			if command.get("sprint",false): Input.action_press("sprint")
			jumping = bool(command.get("jump",false))
			if jumping: Input.action_press("jump")
		"prediction":
			game.movement.send_enabled = false
			prediction = {"start":LfeMovementProtocol.array3(game.player.global_position),"until":Time.get_ticks_msec()+150,"ack_before":game.movement.latest_self.get("ack",0),"sequence_before":game.movement.sequence}
			Input.action_press("move_forward")
		"drift":
			result["before"] = LfeMovementProtocol.array3(game.player.global_position)
			game.player.global_position += Vector3(7,0,0)
			result["injected"] = LfeMovementProtocol.array3(game.player.global_position)
			result["authoritative"] = game.movement.latest_self.duplicate(true)
		"input_loss":
			_release()
			game.movement.send_enabled = false
		"held_jump":
			_release()
			game.movement.send_enabled = false
			game.movement.sequence += 1
			game.movement._send(1,LfeMovementProtocol.input(game.movement.sequence,{"move":Vector2.ZERO,"jump":true,"sprint":false,"yaw":game.player.rotation.y,"pitch":game.player.movement_pitch()}))
		"resume": game.movement.send_enabled = true
		"stale":
			game.movement.send_enabled = false
			game.movement.sequence += 1
			var intent: Dictionary = {"move":Vector2.ZERO,"jump":false,"sprint":false,"yaw":0.0,"pitch":0.0}
			var packet: Dictionary = LfeMovementProtocol.input(game.movement.sequence,intent)
			game.movement._send(1,packet)
			packet["move_x"] = 1.0
			game.movement._send(1,packet)
			packet["sequence"] -= 1
			game.movement._send(1,packet)
			result["sequence"] = game.movement.sequence
		"invalid":
			var packet: Dictionary = LfeMovementProtocol.input(game.movement.sequence+1,game.player.consume_movement_intent())
			packet["player_id"] = command.get("player_id","")
			game.network_session.send_packet(1,JSON.stringify(packet).to_utf8_buffer(),MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED,1)
		"inventory":
			if command.get("open",true) and not game.player.inventory_open: game.toggle_inventory()
			elif not command.get("open",true): game.close_inventory()
		"host_distance":
			var body: LeyforgeAuthoritativePlayerBody = game.movement.bodies[command["player_id"]]
			var base: Vector3 = body.global_position + Vector3(float(command["distance"]),0,0)
			var found: bool = false
			for radius: int in range(5):
				for z: int in range(-radius,radius+1):
					for y: int in range(40,10,-1):
						var candidate: Vector3 = Vector3(floorf(base.x)+0.5,float(y)+1.05,floorf(base.z)+float(z)+0.5)
						if game._position_is_safe(candidate):
							game.player.global_position = candidate
							game.player.velocity = Vector3.ZERO
							game.player.set_runtime_ready(false)
							game.player.set_movement_look(0,0)
							relocate_wait = true
							found = true
							break
					if found: break
				if found: break
			if not found: failures.append("no safe controlled host interest relocation")
			result["position"] = LfeMovementProtocol.array3(game.player.global_position)
		"save":
			result["saved"] = game.request_save()
			if not result["saved"]: failures.append("host save failed")
		"snapshot_loss":
			if command.get("enable",true):
				game.movement.snapshot_clock = -1000.0
			else:
				game.movement.snapshot_clock = 0.0
		"screenshot":
			var saved_yaw: float = game.player.rotation.y
			var saved_pitch: float = game.player.movement_pitch()
			var target: Vector3
			if game.session_options.mode == "HOST":
				target = game.movement.bodies[command["player_id"]].global_position
			else:
				target = game.movement.avatars[command["player_id"]].global_position
			var direction: Vector3 = target + Vector3.UP*1.3 - game.player.get_camera().global_position
			game.player.set_movement_look(atan2(-direction.x,-direction.z),atan2(direction.y,Vector2(direction.x,direction.z).length()))
			await process_frame
			await RenderingServer.frame_post_draw
			result["screenshot"] = directory.path_join(label+"-world-"+str(commands.size())+".png")
			if root.get_texture().get_image().save_png(result["screenshot"]) != OK: failures.append("rendered capture failed")
			game.player.set_movement_look(saved_yaw,saved_pitch)
		"jump_once":
			Input.action_press("jump")
			await physics_frame
			Input.action_release("jump")
	commands.append(result)

func _release() -> void:
	jumping = false
	for action: String in ["move_forward","move_back","move_left","move_right","sprint","jump"]: Input.action_release(action)

func _write_report() -> void:
	var session: LfeNetworkSession = game.network_session
	if session == null: return
	var report: Dictionary = {"pid":OS.get_process_id(),"name":label,"state":session.state,"reason":session.reason_code,"ready":game.is_runtime_ready(),"player_id":game.local_player_id,"commands":commands,"failures":failures,"passed":failures.is_empty(),"bindings":session.peer_to_player.duplicate(),"world":session.world_manifest.duplicate(true)}
	if game.movement == null and session.mode == "JOIN":
		# W5.7 destroys the old gameplay nodes; retain the real ended-state
		# assertions without dereferencing the now-absent movement presentation.
		report["no_authority"] = game.authority == null and game.world_save == null
		report["no_world_save"] = not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://worlds"))
		report["teardown"] = game.teardown_facts.duplicate(true)
		report["avatars"] = []
		var ended_file: FileAccess = FileAccess.open(directory.path_join(label+".json"),FileAccess.WRITE)
		ended_file.store_string(JSON.stringify(report,"\t")); ended_file = null
		return
	if game.movement != null:
		report["rejected_packets"] = game.movement.rejected_packets
		report["presence"] = game.movement.presence_events.duplicate(true)
	if game.player != null:
		report["position"] = LfeMovementProtocol.array3(game.player.global_position)
		report["velocity"] = LfeMovementProtocol.array3(game.player.velocity)
		report["grounded"] = game.player.is_on_floor()
		report["inventory_open"] = game.player.inventory_open
		report["viewer_position"] = LfeMovementProtocol.array3(game.player.get_viewer().global_position)
	if session.mode == "HOST":
		report["roster"] = game.authority.players_snapshot()
		report["bodies"] = {}
		report["relevant"] = game.movement.relevant.duplicate(true)
		for id: String in game.movement.bodies:
			var body: LeyforgeAuthoritativePlayerBody = game.movement.bodies[id]
			report["bodies"][id] = {"spawn_transform":body.spawn_transform,"state":body.state(),"viewer":LfeMovementProtocol.array3(body.viewer.global_position),"viewer_exists":is_instance_valid(body.viewer),"ready":body.ready_for_movement,"loaded":game.terrain.get_voxel_tool().is_area_editable(AABB(body.global_position-Vector3(1,2,1),Vector3(2,4,2))),"visible":body.avatar.visible,"input_age":body.input_age,"accepted":body.accepted_sequence}
		report["tick"] = game.movement.tick
		report["paused"] = paused
	else:
		report["no_authority"] = game.authority == null and game.world_save == null and game.active_character == null and (game.player == null or game.player.resource_state == null or game.player.resource_state == game.resource_network.replica.personal)
		report["no_world_save"] = not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://worlds"))
		report["sequence"] = game.movement.sequence
		report["server_tick"] = game.movement.last_snapshot_tick
		report["self"] = game.movement.latest_self
		report["avatars"] = game.movement.avatars.keys()
		report["maximum_error"] = game.movement.maximum_error
		report["corrections"] = game.movement.corrections
		report["prediction"] = prediction
		if game.player != null and not game.movement.latest_self.is_empty():
			report["error"] = game.player.global_position.distance_to(LfeMovementProtocol.vec3(game.movement.latest_self["position"]))
	_extend_report(report)
	trace.append({"msec":Time.get_ticks_msec(),"state":report["state"],"position":report.get("position",[]),"sequence":report.get("sequence",0),"tick":report.get("tick",report.get("server_tick",0)),"error":report.get("error",0),"bodies":report.get("bodies",{})})
	if trace.size() > 1800: trace.pop_front()
	var target: String = directory.path_join(label+".json")
	var file: FileAccess = FileAccess.open(target+".pending",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.flush()
	file = null
	DirAccess.rename_absolute(target+".pending",target)
	var trace_path: String = directory.path_join(label+"-trace.json")
	var trace_file: FileAccess = FileAccess.open(trace_path+".pending",FileAccess.WRITE)
	trace_file.store_string(JSON.stringify(trace,"\t"))
	trace_file.flush()
	trace_file = null
	DirAccess.rename_absolute(trace_path+".pending",trace_path)
func _extend_report(_report: Dictionary) -> void:
	pass
