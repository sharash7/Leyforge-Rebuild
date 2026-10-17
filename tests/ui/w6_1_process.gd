extends "res://tests/networking/w5_9_process.gd"

var _held_results: Array = []

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
		await _button(panel.find_child("OpenCraftingManual",true,false))
		_expect(panel.manual.visible,"manual normal pointer open",result)
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
