extends "res://tests/networking/w5_3_process.gd"
var arena_y: int = 0
var observations: Array = []
var cells_to_watch: Array = []
var capture_count: int = 0

func _command(command: Dictionary) -> void:
	var operation: String = command.get("op","")
	if operation not in ["arena","generated_jitter_target","edit","actor_position","look","harvest_input","harvest_packet","gap","corrupt","watch","host_harvest","host_pick_place","voxel_pause","far_edit","traffic","relocate_remote","screenshot_voxel"]:
		super._command(command)
		return
	var result: Dictionary = {"op":operation,"msec":Time.get_ticks_msec()}
	var tool: VoxelTool = game.terrain.get_voxel_tool()
	tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	match operation:
		"arena":
			arena_y = floori(game.player.global_position.y)
			# An isolated collision fixture uses the production commit seam.
			# Floor is stone, corridor is air, and one actual dirt cell obstructs it.
			for x: int in range(-3,5):
				for z: int in range(-4,7):
					for y: int in range(arena_y-1,arena_y+4):
						var cell: Vector3i = Vector3i(x,y,z)
						var block: StringName = &"leyforge:stone" if y == arena_y-1 else &"leyforge:air"
						if game._commit_voxel(cell,game.block_catalog.get_voxel_id(block),tool) != OK: failures.append("arena commit failed")
			var target: Vector3i = Vector3i(0,arena_y,0)
			game._commit_voxel(target,game.block_catalog.get_voxel_id(&"leyforge:dirt"),tool)
			game._commit_voxel(Vector3i(2,arena_y,0),game.block_catalog.get_voxel_id(&"leyforge:oak_heartwood"),tool)
			game._commit_voxel(Vector3i(3,arena_y,0),game.block_catalog.get_voxel_id(&"leyforge:stone"),tool)
			game._commit_voxel(Vector3i(-2,arena_y,0),game.block_catalog.get_voxel_id(&"leyforge:grass"),tool)
			result["y"] = arena_y
			result["cell"] = LfeVoxelProtocol.array3(target)
			game.player.global_position = Vector3(3.5,arena_y+0.05,4.5)
			game.player.velocity = Vector3.ZERO
			game.player.set_movement_look(0,0)
		"generated_jitter_target":
			# Find an untouched generated step outside the edited corridor.
			var found: bool = false
			for z: int in range(-25,25):
				for y: int in range(40,10,-1):
					var cell: Vector3i = Vector3i(7,y,z)
					var base: int = game._generator.sample_voxel_id(cell)
					if not game.block_catalog.is_breakable_voxel(base) or int(game.block_catalog.definition_for_voxel_id(base).get("harvest",{}).get("capability",1)) != 0: continue
					if not game.world_save.overrides.canonical_id_at(cell).is_empty() or tool.get_voxel(cell) != base: continue
					var air: int = game.block_catalog.get_voxel_id(&"leyforge:air")
					if tool.get_voxel(cell+Vector3i.UP) != air or tool.get_voxel(cell+Vector3i.UP*2) != air: continue
					var target_body: AABB = LfeVoxelInteractionRules.player_body_aabb(Vector3(cell)+Vector3(0.5,0.05,0.5)).grow(0.05)
					var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
					var box: BoxShape3D = BoxShape3D.new()
					box.size = target_body.size
					query.shape = box
					query.transform.origin = target_body.get_center()
					query.collision_mask = LfeVoxelInteractionRules.FINITE_SOURCE_LAYER
					if not game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
					var client_foot: Vector3 = Vector3(7.5,float(y)+0.05,float(z)-0.5)
					var host_foot: Vector3 = client_foot + Vector3(0,0,-1)
					if not game.network_spawn_safe(client_foot,command["player_id"]) or not game.network_spawn_safe(host_foot,game.local_player_id): continue
					if not tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(cell)): continue
					result["cell"] = LfeVoxelProtocol.array3(cell)
					result["base_block"] = String(game.block_catalog.canonical_id_for_voxel_id(base))
					result["current_block"] = String(game.block_catalog.canonical_id_for_voxel_id(tool.get_voxel(cell)))
					result["client_foot"] = LfeMovementProtocol.array3(client_foot)
					result["host_foot"] = LfeMovementProtocol.array3(host_foot)
					found = true
					break
				if found: break
			if not found: failures.append("no supported untouched generated jitter target")
		"edit":
			var cell: Vector3i = LfeVoxelProtocol.cell(command["cell"])
			var block: int = game.block_catalog.get_voxel_id(StringName(command["block"]))
			result["before"] = tool.get_voxel(cell)
			result["error"] = game._commit_voxel(cell,block,tool)
			result["after"] = tool.get_voxel(cell)
			result["bucket"] = LfeVoxelProtocol.array3(LfeVoxelOverrideStore.bucket_for(cell))
		"actor_position":
			if command["player_id"] == game.local_player_id:
				game.player.global_position = LfeMovementProtocol.vec3(command["position"])
				game.player.velocity = Vector3.ZERO
			else:
				var body: LeyforgeAuthoritativePlayerBody = game.movement.bodies[command["player_id"]]
				body.global_position = LfeMovementProtocol.vec3(command["position"])
				body.velocity = Vector3.ZERO
				body.sync_record()
		"look":
			var cell: Vector3i = LfeVoxelProtocol.cell(command["cell"])
			var direction: Vector3 = Vector3(cell)+Vector3.ONE*0.5-game.player.get_camera().global_position
			game.player.set_movement_look(atan2(-direction.x,-direction.z),atan2(direction.y,Vector2(direction.x,direction.z).length()))
			result["cell"] = command["cell"]
		"harvest_input":
			if command["active"]:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				Input.action_press("break_block")
			else: Input.action_release("break_block")
		"harvest_packet":
			game.voxel_network.action_sequence += 1
			var packet: Dictionary = {"kind":"voxel_harvest_state","action_sequence":game.voxel_network.action_sequence,"active":command.get("active",true),"target_cell":command["cell"],"expected_block":command.get("block","leyforge:dirt")}
			if command.get("spoof",false): packet["player_id"] = command.get("player_id","")
			if command.get("unsupported",false): packet["kind"] = "voxel_place"
			var bytes: PackedByteArray = JSON.stringify(packet).to_utf8_buffer()
			if command.get("oversized",false): bytes = (" ".repeat(1201)+JSON.stringify(packet)).to_utf8_buffer()
			game.network_session.send_packet(1,bytes,MultiplayerPeer.TRANSFER_MODE_RELIABLE,5)
			if command.get("repeat",false): game.network_session.send_packet(1,bytes,MultiplayerPeer.TRANSFER_MODE_RELIABLE,5)
		"gap":
			var bucket: Vector3i = LfeVoxelOverrideStore.bucket_for(LfeVoxelProtocol.cell(command["cell"]))
			game.voxel_network.replica.revisions[bucket] = int(game.voxel_network.replica.revisions.get(bucket,0)) + 4
			result["revision"] = game.voxel_network.replica.revisions[bucket]
		"corrupt":
			var bucket: Vector3i = LfeVoxelOverrideStore.bucket_for(LfeVoxelProtocol.cell(command["cell"]))
			var revision: int = int(game.voxel_network.revisions.get(bucket,0))
			var peer: int = game.network_session.player_to_peer[command["player_id"]]
			var values: Array = game.world_save.overrides.bucket_snapshot(bucket)
			game.voxel_network.transfer_sequence += 1
			# A real wire transfer with a corrupt hash must not reach the live store.
			var packets: Array[Dictionary] = LfeVoxelProtocol.snapshot_packets(bucket,revision,values,game.voxel_network.transfer_sequence,int(command["sync_id"]))
			packets[0]["hash"] = "0".repeat(64)
			for packet: Dictionary in packets: game.voxel_network._send(peer,packet)
		"watch":
			cells_to_watch = command["cells"]
		"host_harvest":
			var cell: Vector3i = LfeVoxelProtocol.cell(command["cell"])
			var direction: Vector3 = Vector3(cell)+Vector3.ONE*0.5-game.player.get_camera().global_position
			game.player.set_movement_look(atan2(-direction.x,-direction.z),atan2(direction.y,Vector2(direction.x,direction.z).length()))
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Input.action_press("break_block")
			result["drops_before"] = game.world_resources.drops().size()
		"host_pick_place":
			var cell: Vector3i = LfeVoxelProtocol.cell(command["cell"])
			game.player.global_position = Vector3(cell)+Vector3(1.5,0.05,0.5)
			game.player.velocity = Vector3.ZERO
			var found: bool = false
			for drop: Dictionary in game.world_resources.drops():
				if drop["stack"]["content"] == "leyforge:dirt" and game.command(game.local_player_id,"pickup",{"target":drop["instance"]}).success:
					found = true
					break
			if not found: failures.append("HOST cannot collect legitimate dirt output")
			for slot: int in 27:
				if game.personal_resources.inventory.stack_at(slot).get("content","") == "leyforge:dirt":
					if not game.command(game.local_player_id,"select",{"slot":slot}).success or not game.place_cell(cell): failures.append("HOST legitimate placement failed")
					result["placed"] = true
					break
		"voxel_pause":
			if command["enable"]:
				game.network_session.packet_received.disconnect(game.voxel_network._packet)
			else:
				game.network_session.packet_received.connect(game.voxel_network._packet)
				game.voxel_network._request_resync(LfeVoxelOverrideStore.bucket_for(LfeVoxelProtocol.cell(command["cell"])),Time.get_ticks_msec()/1000.0)
		"relocate_remote":
			var body: LeyforgeAuthoritativePlayerBody = game.movement.bodies[command["player_id"]]
			var found: bool = false
			for y: int in range(40,10,-1):
				var candidate: Vector3 = Vector3(float(command["x"])+0.5,float(y)+1.05,float(command["z"])+0.5)
				if game.network_position_safe(candidate):
					body.global_position = candidate
					body.velocity = Vector3.ZERO
					body.ready_for_movement = false
					body.sync_record()
					found = true
					break
			if not found: failures.append("remote interest relocation unavailable")
		"far_edit":
			var x: int = int(command["x"])
			var z: int = int(command.get("z",0))
			var y: int = game.TerrainRules.height_at(game.active_seed,x,z)
			var cell: Vector3i = Vector3i(x,y,z)
			var deadline: int = Time.get_ticks_msec()+8000
			while not tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(cell)) and Time.get_ticks_msec() < deadline: await physics_frame
			result["cell"] = LfeVoxelProtocol.array3(cell)
			result["error"] = game._commit_voxel(cell,game.block_catalog.get_voxel_id(&"leyforge:air"),tool)
			if result["error"] != OK: failures.append("far edit unavailable")
		"traffic":
			var cell: Vector3i = LfeVoxelProtocol.cell(command["cell"])
			for index: int in 40:
				game._commit_voxel(cell,game.block_catalog.get_voxel_id(&"leyforge:air" if index%2 == 0 else &"leyforge:grass"),tool)
				await create_timer(0.05).timeout
			result["edits"] = 40
		"screenshot_voxel":
			await process_frame
			await RenderingServer.frame_post_draw
			result["screenshot"] = directory.path_join(label+"-voxel-"+str(capture_count)+".png")
			capture_count += 1
			if root.get_texture().get_image().save_png(result["screenshot"]) != OK: failures.append("voxel screenshot")
	commands.append(result)

func _extend_report(report: Dictionary) -> void:
	if game.voxel_network != null:
		report["voxel_ready"] = game.voxel_network.client_ready
		report["sync_id"] = game.voxel_network.replica.sync_id
		report["voxel_metrics"] = game.voxel_network.metrics
		report["voxel_events"] = game.voxel_network.events
		report["feedback"] = game.voxel_network.feedback
		report["arena_y"] = arena_y
		report["pending_cells"] = game.voxel_network.dirty_cells.size()
		report["smooth_corrections"] = game.movement.smooth_corrections
		report["correction_distance"] = game.movement.correction_distance
		report["harvests"] = game._actor_harvests.size()
		var store: LfeVoxelOverrideStore = game.world_save.overrides if game.world_save != null else game.voxel_network.replica.store
		report["overrides"] = store.serialized_entries()
		report["bucket_hashes"] = {}
		var revisions: Dictionary = game.voxel_network.revisions if game.world_save != null else game.voxel_network.replica.revisions
		for bucket: Vector3i in revisions:
			report["bucket_hashes"][str(bucket)] = LfeVoxelProtocol.snapshot_hash(bucket,revisions[bucket],store.bucket_snapshot(bucket))
		report["known"] = {}
		if game.world_save != null:
			report["drops"] = game.world_resources.drops()
			for peer: int in game.voxel_network.known: report["known"][str(peer)] = game.voxel_network.known[peer].size()
		report["cells"] = []
		if game.terrain != null:
			var tool: VoxelTool = game.terrain.get_voxel_tool()
			tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
			for value: Array in cells_to_watch:
				var cell: Vector3i = LfeVoxelProtocol.cell(value)
				var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(cell)+Vector3(0.5,0.5,-0.1),Vector3(cell)+Vector3(0.5,0.5,0.9),LfeVoxelInteractionRules.WORLD_PHYSICAL_LAYER))
				report["cells"].append({"cell":value,"voxel":tool.get_voxel(cell),"canonical":String(game.block_catalog.canonical_id_for_voxel_id(tool.get_voxel(cell))),"collision":not hit.is_empty(),"override":store.canonical_id_at(cell)})
		if game.player != null: report["target"] = LfeVoxelProtocol.array3(game.player.get_target_cell()) if game.player.has_voxel_target() else []
	observations.append({"msec":Time.get_ticks_msec(),"cells":report.get("cells",[]),"feedback":report.get("feedback",{}),"error":report.get("error",0),"corrections":report.get("corrections",0),"smooth_corrections":report.get("smooth_corrections",0),"voxel_metrics":report.get("voxel_metrics",{}),"position":report.get("position",[])})
	if observations.size() > 1800: observations.pop_front()
	var trace_path: String = directory.path_join(label+"-voxel-trace.json")
	var trace_file: FileAccess = FileAccess.open(trace_path+".pending",FileAccess.WRITE)
	trace_file.store_string(JSON.stringify(observations,"\t"))
	trace_file.flush()
	trace_file = null
	DirAccess.rename_absolute(trace_path+".pending",trace_path)
