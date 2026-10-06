extends "res://tests/networking/w5_6_process.gd"
var drop_trace: Array = []
var _drop_sampler: Node
var pointer_fact: Dictionary = {}
class DropSampler extends Node:
	var driver: Variant
	func _process(_delta: float) -> void: driver._record_drop_frame()

func _record_drop_frame() -> void:
	if game==null or game.resource_presenter==null: return
	if game.resource_presenter._nodes.is_empty() and drop_trace.is_empty(): return
	var positions: Dictionary = {}
	for id: String in game.resource_presenter._nodes:
		positions[id]={"visual":LfeMovementProtocol.array3(game.resource_presenter._nodes[id].position),"target":LfeMovementProtocol.array3(game.resource_presenter._drop_targets[id])}
	drop_trace.append({"msec":Time.get_ticks_msec(),"utc_msec":Time.get_unix_time_from_system()*1000.0,"positions":positions,"drops":game.world_resources.drops()})
	if drop_trace.size()>1024:drop_trace.pop_front()


func _observe_input_request() -> void:
	# Buffered normal input is dispatched on the next frame. Observe its real
	# pending packet before ENet polls the response; never fabricate a request.
	for frame: int in 3:
		await process_frame
		if game.resource_network!=null and not game.resource_network.pending.is_empty():
			last_request=game.resource_network.pending.values()[0]["packet"].duplicate(true)

func _key(code: int) -> void:
	var event: InputEventKey = InputEventKey.new(); event.keycode=code;event.physical_keycode=code;event.pressed=true
	Input.parse_input_event(event)
	if game.resource_network!=null and not game.resource_network.pending.is_empty(): last_request=game.resource_network.pending.values()[0]["packet"].duplicate(true)
	await _observe_input_request()
	await create_timer(0.1).timeout
	event=InputEventKey.new();event.keycode=code;event.physical_keycode=code;Input.parse_input_event(event)
	await _settle_ui()

func _mouse(point: Vector2, right: bool = false, shift: bool = false) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	Input.parse_input_event(motion);await process_frame
	var hovered: Control = root.gui_get_hovered_control()
	pointer_fact["hovered"]=str(hovered.get_path()) if hovered!=null else ""
	pointer_fact["point"]=[point.x,point.y]
	var event: InputEventMouseButton = InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT
	event.position=point;event.global_position=point;event.pressed=true;event.shift_pressed=shift
	Input.parse_input_event(event)
	if game.resource_network!=null and not game.resource_network.pending.is_empty(): last_request=game.resource_network.pending.values()[0]["packet"].duplicate(true)
	await _observe_input_request()
	await create_timer(0.1).timeout
	event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT
	event.position=point;event.global_position=point;event.shift_pressed=shift;Input.parse_input_event(event)
	await _settle_ui()

func _settle_ui() -> void:
	await create_timer(0.25).timeout
	var deadline: int = Time.get_ticks_msec()+6000
	while game.resource_network != null and not game.resource_network.pending.is_empty() and Time.get_ticks_msec()<deadline: await physics_frame
	await create_timer(0.3).timeout

func _button(button: Control, right: bool = false, shift: bool = false) -> void:
	if button==null: failures.append("missing graphical button");return
	var parent: Node = button.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(button)
		parent=parent.get_parent()
	await create_timer(0.15).timeout
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	pointer_fact={"button":str(button.get_path()),"rect":str(button.get_global_rect()),"transform":str(root.get_final_transform())}
	await _mouse(root.get_final_transform()*button.get_global_rect().get_center(),right,shift)

func _slot(endpoint: String, slot: int) -> Control:
	for entry: Dictionary in game.inventory_panel._buttons:
		if game.resource_endpoint_name(entry["inventory"]) == endpoint and entry["slot"]==slot: return entry["button"]
	return null

func _aim(position: Vector3) -> void:
	var direction: Vector3 = position-game.player.get_camera().global_position
	game.player.set_movement_look(atan2(-direction.x,-direction.z),atan2(direction.y,Vector2(direction.x,direction.z).length()))
	await create_timer(0.4).timeout

func _capture(name: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(label+"-"+name+".png"))

func _command(c: Dictionary) -> void:
	if not String(c.get("op","")).begins_with("repair_"): super._command(c);return
	var result: Dictionary = {"op":c["op"],"msec":Time.get_ticks_msec()}
	match c["op"]:
		"repair_fixture":
			var cell: Vector3i = LfeVoxelProtocol.cell(c["cell"])
			var content: StringName = StringName(c.get("content","leyforge:workbench"))
			var tool: VoxelTool = game.terrain.get_voxel_tool();tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
			game._commit_voxel(cell,game.block_catalog.get_voxel_id(content),tool)
			if not game.creation.add_object(content,cell,0): failures.append("isolated functional fixture placement")
			result["id"]=game.creation.object_at(cell);game.resource_network._refresh()
		"repair_crate_access":
			var point: Vector3 = LfeMovementProtocol.vec3(c["position"])
			var tool: VoxelTool = game.terrain.get_voxel_tool();tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
			# The test arena floor must not bury the untouched origin crate at its
			# lower generated terrain height. Keep its original identity/position.
			for x: int in range(floori(point.x),floori(point.x)+3):
				for z: int in range(floori(point.z)-1,floori(point.z)+2):
					for y: int in range(floori(point.y)-1,int(c["arena_y"])+4):
						game._commit_voxel(Vector3i(x,y,z),game.block_catalog.get_voxel_id(&"leyforge:stone" if y==floori(point.y)-1 else &"leyforge:air"),tool)
		"repair_runway":
			var y: int = c["y"]
			var tool: VoxelTool = game.terrain.get_voxel_tool();tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
			for z: int in range(5,31):
				for x: int in range(1,3):
					for h: int in range(y-1,y+4):
						game._commit_voxel(Vector3i(x,h,z),game.block_catalog.get_voxel_id(&"leyforge:stone" if h==y-1 else &"leyforge:air"),tool)
		"repair_items":
			var inventory: LfeInventory = game.authority.character(c["player_id"]).resources.inventory
			var donor: LfeInventory = LfeInventory.new(game.block_catalog)
			LfeItemTransactions.add(donor,&"leyforge:stone",6)
			for slot: int in range(9,15): LfeItemTransactions.transfer(donor,0,inventory,1,slot)
			LfeItemTransactions.add(donor,&"leyforge:oak_planks",2)
			for slot: int in range(15,17): LfeItemTransactions.transfer(donor,0,inventory,1,slot)
			LfeItemTransactions.add(inventory,&"leyforge:oak_heartwood",3)
			LfeItemTransactions.add(inventory,&"leyforge:drinking_water",3)
			game.resource_network._refresh()
		"repair_interact":
			var point: Vector3 = LfeMovementProtocol.vec3(c["position"]) if c.has("position") else Vector3(LfeVoxelProtocol.cell(c["cell"]))+Vector3.ONE*0.5
			await _aim(point);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
			game.player._update_targeting()
			result["has_target"]=game.player.has_voxel_target();result["target_cell"]=LfeVoxelProtocol.array3(game.player.get_target_cell())
			result["prompt"]=game.player.context_text();result["object_id"]=game.creation.object_at(game.player.get_target_cell());result["crate_id"]=game.player.target_crate()
			if c.get("key",false): await _key(KEY_E)
			else: await _mouse(Vector2(640,360),true)
			result["ui_open"]=game.player.inventory_open;result["grid_size"]=game.inventory_panel.crafting.size if game.inventory_panel.crafting!=null else 0
			result["context"]=game.inventory_panel._object;result["status"]=game.player._status_message
			await _capture("interact-"+str(commands.size()))
		"repair_key": await _key(int(c["code"]))
		"repair_button":
			var button: Control = game.inventory_panel.find_child(c["name"],true,false)
			await _button(button)
			result["manual_visible"]=game.inventory_panel.manual.visible
			result["selected_recipe"]=game.inventory_panel.manual.selected_recipe
			result["listed_ids"]=game.inventory_panel.manual.listed_ids.duplicate()
			await _capture("manual-"+str(commands.size()))
		"repair_slot":
			await _button(_slot(c["endpoint"],int(c["slot"])),c.get("right",false),c.get("shift",false))
			result["preview"]=game.inventory_panel._preview_recipe
			result["pointer"]=pointer_fact.duplicate()
			result["endpoint"]=c["endpoint"];result["slot"]=c["slot"]
			result["picked_endpoint"]=game.resource_endpoint_name(game.inventory_panel._picked_inventory) if game.inventory_panel._picked_inventory!=null else ""
			result["picked_slot"]=game.inventory_panel._picked_slot
			await _capture("slot-"+str(commands.size()))
		"repair_select":
			for slot: int in 9:
				if game.personal_resources.inventory.stack_at(slot).get("content")==c["content"]: await _key(KEY_1+slot);break
		"repair_place":
			await _aim(Vector3(LfeVoxelProtocol.cell(c["cell"]))+Vector3.ONE*0.5);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
			await _mouse(Vector2(640,360),true)
		"repair_drops":
			var donor: LfePlayerResourceState = LfePlayerResourceState.new(game.block_catalog)
			LfeItemTransactions.add(donor.inventory,&"leyforge:oak_stick",2)
			var point: Vector3 = LfeMovementProtocol.vec3(c["position"])
			result["ids"]=[game.world_resources.drop_from_inventory(donor,0,1,point),game.world_resources.drop_from_inventory(donor,0,1,point+Vector3.RIGHT*0.9)]
			for id: String in result["ids"]: game.world_resources.ground_drop(id,game.drop_rest_position)
			game.resource_network._refresh()
		"repair_drop_jump":
			var id: String = c["id"];game.world_resources._drops[id]["position"]=c["position"];game.world_resources.ground_drop(id,game.drop_rest_position);game.resource_network._refresh()
		"repair_drop_stop":
			game.resource_presenter.set_physics_process(not c["hold"])
		"repair_missing":
			var key: String = "object/"+c["id"]
			var state: Dictionary = game.resource_network.replica.states[key].duplicate(true)
			game.resource_network.replica.states.erase(key)
			await _aim(Vector3(LfeVoxelProtocol.cell(c["cell"]))+Vector3.ONE*0.5);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
			await _mouse(Vector2(640,360),true)
			result["status"]=game.player._status_message;result["ui_open"]=game.player.inventory_open
			game.resource_network.replica.states[key]=state
			await _settle_ui()
			result["recovered_ui"]=game.player.inventory_open
	commands.append(result)

func _extend_report(report: Dictionary) -> void:
	super._extend_report(report)
	if game.inventory_panel != null:
		report["ui_open"]=game.player.inventory_open;report["ui_context"]=game.inventory_panel._object;report["manual_visible"]=game.inventory_panel.manual.visible
	if game.resource_presenter != null:
		var positions: Dictionary = {}
		for id: String in game.resource_presenter._nodes:
			positions[id]={"visual":LfeMovementProtocol.array3(game.resource_presenter._nodes[id].position),"target":LfeMovementProtocol.array3(game.resource_presenter._drop_targets[id])}
		report["drop_presentations"]=positions
		if _drop_sampler==null:
			_drop_sampler=DropSampler.new();_drop_sampler.driver=self;root.add_child(_drop_sampler)
		var file: FileAccess = FileAccess.open(directory.path_join(label+"-drop-trace.json"),FileAccess.WRITE);file.store_string(JSON.stringify(drop_trace,"\t"));file=null
