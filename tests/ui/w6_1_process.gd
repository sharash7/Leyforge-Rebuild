extends "res://tests/networking/w5_9_process.gd"

var _held_results: Array = []

func _button(button: Control, right: bool = false, shift: bool = false) -> void:
	if button==null:failures.append("missing graphical button");return
	var parent: Node=button.get_parent()
	while parent!=null:
		if parent is ScrollContainer:parent.ensure_control_visible(button)
		parent=parent.get_parent()
	await create_timer(0.15).timeout
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var point: Vector2=root.get_final_transform()*button.get_global_rect().get_center()
	var motion: InputEventMouseMotion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	Input.parse_input_event(motion);await process_frame
	var hovered: Control=root.gui_get_hovered_control()
	pointer_fact={"button":str(button.get_path()),"rect":str(button.get_global_rect()),"transform":str(root.get_final_transform()),"point":[point.x,point.y],"hovered":str(hovered.get_path()) if hovered!=null else "","paired_click":true}
	# Several rendered fixtures share a desktop cursor. A timer between a GUI
	# press/release allowed foreign desktop motion to cancel the held button.
	# Queue one ordinary click pair together, exactly as the Forge UI harness.
	var event: InputEventMouseButton=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT;event.position=point;event.global_position=point;event.shift_pressed=shift;event.pressed=true
	Input.parse_input_event(event);event=event.duplicate();event.pressed=false;Input.parse_input_event(event)
	if game.resource_network!=null and not game.resource_network.pending.is_empty():last_request=game.resource_network.pending.values()[0]["packet"].duplicate(true)
	await _observe_input_request();await _settle_ui()

func _hold_results(peer: int, bytes: PackedByteArray) -> void:
	var packet: Dictionary = LfeResourceProtocol.decode(bytes,game.block_catalog)
	if packet.get("kind")=="resource_result":_held_results.append([peer,bytes]);return
	game.resource_network._packet(peer,bytes)

func _command(c: Dictionary) -> void:
	if c.get("op")=="w61_feedback":
		var panel: LeyforgeInventoryPanel = game.inventory_panel
		var net: LeyforgeResourceNetwork = game.resource_network
		var result: Dictionary = {"op":"w61_feedback","checks":[]}
		var source: int = -1
		for slot: int in 27:
			if game.personal_resources.inventory.stack_at(slot).get("content")=="leyforge:oak_heartwood":source=slot;break
		_expect(source>=0,"seeded source available",result)
		if source<0:commands.append(result);_write_report();return
		await _button(_slot("inventory",source))
		_expect(panel._picked_inventory==game.personal_resources.inventory and panel._picked_slot==source,"normal pointer selects source",result)
		_expect(_slot("inventory",source).modulate!=Color.WHITE,"source visibly highlighted",result)
		net.session.packet_received.disconnect(net._packet);net.session.packet_received.connect(_hold_results)
		await _button(_slot("grid",0),true)
		panel._refresh()
		_expect(not net.pending.is_empty() and panel._feedback.text.begins_with("Pending HOST") and panel._panel.get_global_rect().encloses(panel._feedback.get_global_rect()),"withheld result remains pending, never success",result)
		await _capture("pending-result-after-state")
		net.session.packet_received.disconnect(_hold_results);net.session.packet_received.connect(net._packet)
		for packet: Array in _held_results:net._packet(packet[0],packet[1])
		_held_results.clear();await _settle_ui();panel._refresh()
		_expect(net.pending.is_empty() and panel._feedback.text.begins_with("Accepted:"),"only authoritative result accepts transfer",result)
		_expect(panel._panel.get_global_rect().encloses(panel._feedback.get_global_rect()),"feedback stays visible after scrolling",result)
		await _button(_slot("grid",0),false,true)
		panel._refresh()
		_expect(panel._feedback.text.begins_with("Accepted:"),"quick return authoritative feedback",result)
		var rejected: LfeCommandResult = panel._ui_command("transfer",{"source":"inventory","destination":"equipment","source_slot":source,"destination_slot":1,"quantity":1,"expected":game.personal_resources.inventory.stack_at(source)})
		await _settle_ui();panel._refresh()
		_expect(not rejected.success or panel._feedback.text.begins_with("Rejected:"),"invalid equipment destination rejected",result)
		await _capture("accepted-rejected-feedback")
		commands.append(result);_write_report();return
	if c.get("op")!="w61_layout":
		await super._command(c);return
	var dimensions: Vector2i = Vector2i(int(c["width"]),int(c["height"]))
	root.size=dimensions
	# Keep the production canvas stretch for native window checks. Also exercise
	# the tighter logical viewport independently when explicitly requested.
	root.content_scale_size=dimensions if c.get("logical",false) else Vector2i(1280,720)
	await create_timer(0.3).timeout
	var panel: LeyforgeInventoryPanel = game.inventory_panel
	panel._layout();panel.manual._layout()
	await create_timer(0.3).timeout
	var viewport: Rect2 = root.get_visible_rect()
	var result: Dictionary = {"op":"w61_layout","width":dimensions.x,"height":dimensions.y,"panel":str(panel._panel.get_global_rect()),"checks":[]}
	_expect(viewport.encloses(panel._panel.get_global_rect()),"inventory inside viewport",result)
	_expect(game.personal_resources.inventory.capacity()==27 and game.personal_resources.equipment.capacity()==2,"unchanged slot counts",result)
	_expect(panel._hotbar.get_child_count()==9,"shared nine-slot hotbar",result)
	if panel._panel.visible:
		for entry: Dictionary in panel._buttons:
			var button: Button = entry["button"]
			panel._scroll.ensure_control_visible(button)
			await process_frame;await process_frame
			_expect(panel._scroll.get_global_rect().encloses(button.get_global_rect()),"slot reachable "+str(entry["slot"]),result)
			_expect(button.get_theme_font_size("font_size")>=14,"readable slot font",result)
		var close_button: Control = panel.find_child("CloseInventory",true,false)
		panel._scroll.ensure_control_visible(close_button)
		await create_timer(0.1).timeout
		_expect(panel._scroll.get_global_rect().encloses(close_button.get_global_rect()),"close reachable after scroll",result)
		var manual_button: Button=panel.find_child("OpenCraftingManual",true,false)
		var manual_events: Array=[]
		var on_down: Callable=func() -> void:manual_events.append({"event":"down","msec":Time.get_ticks_msec()})
		var on_up: Callable=func() -> void:manual_events.append({"event":"up","msec":Time.get_ticks_msec()})
		var on_pressed: Callable=func() -> void:manual_events.append({"event":"pressed","msec":Time.get_ticks_msec()})
		var on_visible: Callable=func() -> void:manual_events.append({"event":"manual visibility","visible":panel.manual.visible,"msec":Time.get_ticks_msec()})
		var on_enter: Callable=func() -> void:manual_events.append({"event":"mouse enter","msec":Time.get_ticks_msec()})
		var on_exit: Callable=func() -> void:manual_events.append({"event":"mouse exit","msec":Time.get_ticks_msec()})
		var on_input: Callable=func(event: InputEvent) -> void:
			if event is InputEventMouseButton:manual_events.append({"event":"mouse","pressed":event.pressed,"button":event.button_index,"position":str(event.position),"msec":Time.get_ticks_msec()})
		manual_button.button_down.connect(on_down);manual_button.button_up.connect(on_up);manual_button.pressed.connect(on_pressed);manual_button.gui_input.connect(on_input);panel.manual.visibility_changed.connect(on_visible);manual_button.mouse_entered.connect(on_enter);manual_button.mouse_exited.connect(on_exit)
		await _button(manual_button)
		manual_button.button_down.disconnect(on_down);manual_button.button_up.disconnect(on_up);manual_button.pressed.disconnect(on_pressed);manual_button.gui_input.disconnect(on_input);panel.manual.visibility_changed.disconnect(on_visible);manual_button.mouse_entered.disconnect(on_enter);manual_button.mouse_exited.disconnect(on_exit)
		result["manual_events"]=manual_events
		_expect(panel.manual.visible,"manual normal pointer open",result)
		result["manual_pointer"]=pointer_fact.duplicate(true)
		if not panel.manual.visible:
			# Preserve the original failing assertion and actual pointer evidence;
			# do not mask it with a secondary empty recipe-list exception.
			await _capture("manual-open-failure")
			commands.append(result);_write_report();return
		_expect(viewport.encloses(panel.manual._panel.get_global_rect()),"manual inside viewport",result)
		# Select an initially scrolled-out recipe through the real pointer path.
		var recipe_id: String = panel.manual.listed_ids.back()
		await _button(panel.manual._list.find_child(recipe_id.trim_prefix("leyforge:"),true,false))
		_expect(panel.manual.selected_recipe==recipe_id,"scrolled recipe normal pointer selection",result)
		_expect(panel.manual._recipe_scroll.get_global_rect().encloses(panel.manual._list.find_child(recipe_id.trim_prefix("leyforge:"),true,false).get_global_rect()),"selected recipe reachable",result)
		await _capture("w61-"+str(dimensions.x)+"-"+str(commands.size())+"-manual")
		await _button(panel.manual.find_child("CloseManual",true,false))
		_expect(not panel.manual.visible,"manual normal pointer close",result)
	await _capture("w61-"+str(dimensions.x)+"-"+str(commands.size()))
	result["feedback"]=panel._feedback_text
	result["context"]=panel._object
	result["grid_size"]=panel.crafting.size if panel.crafting!=null else 0
	commands.append(result);_write_report()

func _expect(value: bool, message: String, result: Dictionary) -> void:
	result["checks"].append({"label":message,"passed":value})
	if not value:failures.append(message)

func _extend_quality_report(report: Dictionary) -> void:
	super._extend_quality_report(report)
	report["inventory_exists"]=game.inventory_panel!=null
