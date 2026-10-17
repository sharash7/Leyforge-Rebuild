class_name LeyforgeInventoryPanel
extends CanvasLayer

var _world: LeyforgeWave1Playground
var _panel: PanelContainer
var _scroll: ScrollContainer
var _top: BoxContainer
var _title: Label
var _feedback: Label
var _feedback_text: String = ""
var _feedback_rejected: bool = false
var _body: VBoxContainer
var _hotbar: HBoxContainer
var _buttons: Array[Dictionary] = []
var _picked_inventory: LfeInventory
var _picked_slot: int = -1
var _storage_id: String = ""
var _storage_group: VBoxContainer
var _object: String = ""
var _hint: Label
var _progress: ProgressBar
var _output: Button
var _craft_title: Label
var crafting: LfeCraftingGrid
var _preview_recipe: String = ""
var manual: LeyforgeCraftingManual

func configure(world: LeyforgeWave1Playground) -> void:
	_world=world
	layer=5
	var base: Control = Control.new()
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(base)
	_hotbar=HBoxContainer.new()
	base.add_child(_hotbar)
	for slot: int in 9:
		var button: Button = Button.new()
		button.custom_minimum_size=Vector2(96,88)
		button.clip_text=true
		button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size",14)
		button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(func() -> void: _world.command(_world.local_player_id,"select",{"slot":slot}))
		_hotbar.add_child(button)
	_panel=PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color=Color(0.075,0.095,0.115,0.98)
	style.border_color=Color(0.48,0.36,0.22);style.set_border_width_all(2)
	style.content_margin_left=16;style.content_margin_right=16
	style.content_margin_top=12;style.content_margin_bottom=12
	_panel.add_theme_stylebox_override("panel",style)
	base.add_child(_panel)
	_body=VBoxContainer.new();_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_body.add_theme_constant_override("separation",6)
	_scroll=ScrollContainer.new();_scroll.name="InventoryScroll"
	var frame: VBoxContainer = VBoxContainer.new();_panel.add_child(frame)
	var heading: HBoxContainer = HBoxContainer.new();frame.add_child(heading)
	_title=_label(heading,"Inventory",20);_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var manual_button: Button = Button.new();manual_button.name="OpenCraftingManual";manual_button.text="Crafting Manual"
	manual_button.pressed.connect(func() -> void:manual.open());heading.add_child(manual_button)
	_feedback=_label(frame,"",15);_feedback.name="TransactionFeedback"
	_feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	frame.add_child(_scroll);_scroll.add_child(_body);_panel.hide()
	manual=LeyforgeCraftingManual.new();base.add_child(manual);manual.configure(world.block_catalog,world.creation.recipes)
	base.resized.connect(_layout)
	_layout()

func open(storage: bool = false) -> bool:
	var id: String = ""
	if storage and not _world.world_resources.snapshot()["storage"].is_empty():id=_world.world_resources.snapshot()["storage"][0]["instance"]
	return open_context(id)

func open_context(id: String = "", focus_crafting: bool = false, authorized: bool = false) -> bool:
	if _world.session_options.mode == "JOIN" and not authorized:
		return _world.command(_world.local_player_id,"open_context",{"target":id}).success
	if _panel.visible and not close(authorized):return false
	manual.close()
	_object=id;_storage_id="";_picked_inventory=null;_picked_slot=-1
	_buttons.clear();_progress=null;_output=null;_craft_title=null;crafting=null
	for child: Node in _body.get_children():_body.remove_child(child);child.queue_free()
	var station: LfeWorkstation = _world.creation.station(id)
	var stored: LfeInventory = _world.creation.storage(id)
	# JOIN's read replica exposes both storage types through one endpoint lookup.
	# The canonical storage family identifies the origin crate for context checks.
	if not id.is_empty():
		for entry: Dictionary in _world.world_resources.snapshot()["storage"]:
			if entry["instance"]==id:
				stored=_world.world_resources.storage_inventory(id);_storage_id=id
				break
	var workbench: bool = false
	for entry: Dictionary in _world.creation.objects():
		if entry["instance"]==id:workbench=_world.block_catalog.content_definition(StringName(entry["content"])).get("function","")=="workbench"
	_title.text="Workbench · 3×3 crafting" if workbench else "Stone kiln" if station!=null else "Storage" if stored!=null else "Inventory · personal crafting"
	_hint=_label(_body,"",14)
	_top=BoxContainer.new();_top.add_theme_constant_override("separation",16);_body.add_child(_top)
	var top: BoxContainer = _top
	_storage_group=null
	if station!=null:
		var left: VBoxContainer = _column(top,"INPUT")
		_grid(left,station.input,3,0,3);_label(left,"FUEL",14);_grid(left,station.fuel,1,0,1)
		var process: VBoxContainer = _column(top,"CHARCOAL BURN")
		process.custom_minimum_size=Vector2(185,0)
		var recipe: Dictionary = _world.creation.recipes.definition("leyforge:charcoal_burn")
		_label(process,_entries(recipe["inputs"])+"\nFuel: "+_entries(recipe["fuel"])+"\n→ "+_entries(recipe["outputs"]),12)
		_progress=ProgressBar.new();_progress.custom_minimum_size=Vector2(180,24);process.add_child(_progress)
		var fire: Button = Button.new();fire.name="StartProcess";fire.text="Fire kiln"
		fire.pressed.connect(func() -> void: _ui_command("start_process",{"target":_object,"recipe":"leyforge:charcoal_burn"}))
		process.add_child(fire)
		_grid(_column(top,"OUTPUT"),station.output,3,0,3)
	elif stored!=null:
		_storage_group=VBoxContainer.new()
		top.add_child(_storage_group);_label(_storage_group,"STORED",16)
		_grid(_storage_group,stored,3 if not _storage_id.is_empty() else 9,0,stored.capacity())
	else:
		_world._sync_active_transform()
		crafting=_world.resource_grid(id if workbench else "")
		if crafting==null:
			_world.player.show_status("Crafting context is unavailable")
			return false
		var craft_column: VBoxContainer = _column(top,"")
		_craft_title=_label(craft_column,"CRAFTING  ·  %d×%d" % [crafting.size,crafting.size],16)
		if focus_crafting:_craft_title.modulate=Color(1,0.78,0.35)
		_grid(craft_column,crafting.inventory,crafting.size,0,crafting.inventory.capacity())
		var output_column: VBoxContainer = _column(top,"→ OUTPUT")
		_output=_slot_button();_output.name="CraftOutput"
		_output.pressed.connect(func() -> void:
			_ui_command("craft",{"recipe":_preview_recipe})
			_refresh())
		output_column.add_child(_output)
		var guide: VBoxContainer = _column(top,"CRAFTING HINT")
		var help: Label = _label(guide,"Log → planks; plank → sticks.\nFour planks fill 2×2 for a Workbench.\nAt a Workbench: head material above\ntwo vertical Oak Sticks.\nPickaxe: three heads; axe: three in an L;\nshovel: one head. Blank cells matter.",12)
		help.custom_minimum_size=Vector2(300,0)
	_grid(_column(top,"EQUIPMENT"),_world.personal_resources.equipment,1,0,_world.personal_resources.equipment.capacity())
	_label(_body,"PLAYER INVENTORY",16);_grid(_body,_world.personal_resources.inventory,9,9,18)
	_label(_body,"HOTBAR  ·  1–9",16);_grid(_body,_world.personal_resources.inventory,9,0,9)
	_label(_body,"Click source, then destination. Right-click splits half; Shift-click quick transfers. Take crafting output to craft once.",12)
	var close_button: Button = Button.new();close_button.name="CloseInventory";close_button.text="Close [Escape] — returns staged crafting items"
	close_button.pressed.connect(_world.close_inventory);_body.add_child(close_button)
	_world.set_primary_action(false)
	_panel.show();_hotbar.hide();_world.player.inventory_open=true
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	_layout()
	_scroll.set_deferred("scroll_vertical",0);_scroll.set_deferred("scroll_horizontal",0)
	_refresh()
	return true

func close(authorized: bool = false) -> bool:
	if _world.session_options.mode == "JOIN" and not authorized:
		_ui_command("close_grid")
		return false
	if not authorized and crafting!=null and not _ui_command("close_grid").success:
		_world.player.show_status("Backpack full — return crafting items to free slots before closing or saving",5000)
		return false
	manual.close()
	crafting=null;_picked_inventory=null;_picked_slot=-1
	_panel.hide();_hotbar.show();_world.player.inventory_open=false
	if DisplayServer.get_name()!="headless" and not OS.get_cmdline_user_args().has("--wave3-playtest") and not OS.get_cmdline_user_args().has("--wave4-playtest"):
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	return true

func context_valid() -> bool:
	if _object.is_empty():return true
	if not _storage_id.is_empty():
		for entry: Dictionary in _world.world_resources.snapshot()["storage"]:
			if entry["instance"]==_storage_id:
				var p: Array = entry["position"]
				return _world.region_relevant(Vector3(float(p[0]),float(p[1]),float(p[2]))) and _world._near_position(p,4)
		return false
	for entry: Dictionary in _world.creation.objects():
		if entry["instance"]==_object:
			var p: Array = entry["cell"]
			return _world.object_near(_object) and _world.region_relevant(Vector3(float(p[0])+0.5,float(p[1])+0.5,float(p[2])+0.5))
	return false

func _column(parent: Node, title: String) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new();parent.add_child(column)
	if not title.is_empty():_label(column,title,16)
	return column

func _label(parent: Node, text: String, size: int) -> Label:
	var label: Label = Label.new();label.text=text
	if parent==_body:label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size);parent.add_child(label)
	return label

func _slot_button() -> Button:
	var button: Button = Button.new();button.custom_minimum_size=Vector2(92,88)
	button.add_theme_font_size_override("font_size",14);button.clip_text=true
	button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var normal: StyleBoxFlat = StyleBoxFlat.new();normal.bg_color=Color(0.13,0.16,0.19)
	normal.border_color=Color(0.36,0.42,0.45);normal.set_border_width_all(1);normal.set_corner_radius_all(3)
	button.add_theme_stylebox_override("normal",normal)
	var hover: StyleBoxFlat = normal.duplicate();hover.border_color=Color(0.95,0.71,0.35);hover.bg_color=Color(0.19,0.22,0.25)
	button.add_theme_stylebox_override("hover",hover)
	return button

func _grid(parent: Node, inventory: LfeInventory, columns: int, first: int, count: int) -> void:
	var grid: GridContainer = GridContainer.new();grid.columns=columns;parent.add_child(grid)
	for slot: int in range(first,first+count):
		var button: Button = _slot_button()
		button.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
				_click_slot(inventory,slot,event.button_index==MOUSE_BUTTON_RIGHT,event.shift_pressed)
				button.accept_event())
		grid.add_child(button);_buttons.append({"button":button,"inventory":inventory,"slot":slot})

func _allowed(inventory: LfeInventory, destination: bool = false) -> bool:
	if inventory in [_world.personal_resources.inventory,_world.personal_resources.equipment]:return true
	if crafting!=null and inventory==crafting.inventory:return true
	if not context_valid():return false
	var station: LfeWorkstation = _world.creation.station(_object)
	if station!=null:return inventory in [station.input,station.fuel] or (not destination and inventory==station.output)
	var stored: LfeInventory = _world.creation.storage(_object) if _storage_id.is_empty() else _world.world_resources.storage_inventory(_storage_id)
	return stored!=null and inventory==stored

func _click_slot(inventory: LfeInventory, slot: int, split: bool, shift: bool) -> void:
	if not _allowed(inventory):return
	var stack: Dictionary = inventory.stack_at(slot)
	if shift and not stack.is_empty():
		var destination: LfeInventory = _world.personal_resources.inventory
		if inventory==destination:
			if crafting!=null:destination=crafting.inventory
			elif not _storage_id.is_empty():destination=_world.world_resources.storage_inventory(_storage_id)
			else:
				var station: LfeWorkstation = _world.creation.station(_object)
				destination=_world.creation.storage(_object)
				if station!=null:
					var ready: bool = true
					for entry: Dictionary in _world.creation.recipes.definition("leyforge:charcoal_burn")["inputs"]:ready=ready and station.input.total(StringName(entry["content"]))>=int(entry["quantity"])
					destination=station.fuel if ready else station.input
		if destination!=null and _allowed(destination,true):_transfer(inventory,slot,destination,int(stack["quantity"]),-1)
		_picked_inventory=null
	elif _picked_inventory==null:
		if not stack.is_empty():_picked_inventory=inventory;_picked_slot=slot
	else:
		var source: Dictionary = _picked_inventory.stack_at(_picked_slot)
		if not source.is_empty() and _allowed(_picked_inventory) and _allowed(inventory,true):
			var count: int = maxi(1,int(source["quantity"])/2) if split else int(source["quantity"])
			if not split and not stack.is_empty() and stack["content"] != source["content"]:
				_ui_command("swap",{"source":_world.resource_endpoint_name(_picked_inventory),"destination":_world.resource_endpoint_name(inventory),"source_slot":_picked_slot,"destination_slot":slot,"expected":source})
			else: _transfer(_picked_inventory,_picked_slot,inventory,count,slot)
		_picked_inventory=null;_picked_slot=-1
	_refresh()

func _process(_delta: float) -> void:
	if _world==null or _world.personal_resources==null:return
	for slot: int in 9:
		var button: Button = _hotbar.get_child(slot)
		button.text="%d\n%s" % [slot+1,_stack_text(_world.personal_resources.inventory,slot)]
		button.modulate=Color(1,0.85,0.3) if slot==_world.personal_resources.selected_slot() else Color.WHITE
	if _panel.visible:
		if not context_valid():
			if not close():_hint.text="Context unavailable — staging retained. Return items to backpack to close."
		else:_refresh()

func _refresh() -> void:
	if _hint==null:return
	if _feedback!=null:
		var waiting: bool = _world.resource_network!=null and not _world.resource_network.pending.is_empty()
		_feedback.text="Pending HOST transaction — waiting for authoritative result" if waiting else _feedback_text
		_feedback.modulate=Color(1,0.65,0.5) if _feedback_rejected and not waiting else Color(1,0.85,0.45)
	for entry: Dictionary in _buttons:
		var button: Button = entry["button"]
		button.text=_stack_text(entry["inventory"],entry["slot"]);button.tooltip_text=button.text
		if entry["inventory"]==_world.personal_resources.equipment:
			button.text=LfePlayerResourceState.EQUIPMENT_SLOTS[entry["slot"]].capitalize()+" · "+button.text
		button.modulate=Color(1,0.78,0.35) if entry["inventory"]==_picked_inventory and entry["slot"]==_picked_slot else Color.WHITE
	if crafting!=null:
		var match: Dictionary = crafting.preview();_preview_recipe=match.get("recipe","")
		_output.text="—" if match.is_empty() else _entries(match["outputs"])
		_output.tooltip_text=_output.text;_output.disabled=match.is_empty() or not context_valid()
		_hint.text="Arrange ingredients in the grid; output is a preview until taken." if match.is_empty() else "Matched: "+_preview_recipe.trim_prefix("leyforge:")+" · take output to craft once"
	else:
		var station: LfeWorkstation = _world.creation.station(_object)
		_hint.text="Select source then destination slot; output is withdrawal only." if station==null else station.status()+" · "+station.start_reason("leyforge:charcoal_burn")
		if station!=null:_progress.value=float(station.snapshot()["progress"])/float(_world.creation.recipes.definition("leyforge:charcoal_burn")["seconds"])*100

func _entries(entries: Array) -> String:
	var parts: PackedStringArray = []
	for entry: Dictionary in entries:parts.append("%d %s" % [int(entry["quantity"]),_world.block_catalog.content_definition(StringName(entry["content"]))["display_name"]])
	return ", ".join(parts)

func _stack_text(inventory: LfeInventory, slot: int) -> String:
	var stack: Dictionary = inventory.stack_at(slot)
	if stack.is_empty():
		if inventory == _world.personal_resources.equipment:
			return "Empty"
		return "—"
	var name: String = _world.block_catalog.content_definition(StringName(stack["content"]))["display_name"]
	if stack.has("durability"):
		return "%s\nDur %d/%d" % [name,int(stack["durability"]),int(_world.block_catalog.content_definition(StringName(stack["content"]))["tool"]["durability"])]
	return "%s\n×%d" % [name,int(stack["quantity"])]

func _transfer(source: LfeInventory,slot: int,destination: LfeInventory,count: int,target_slot: int) -> int:
	var result: LfeCommandResult=_ui_command("transfer",{"source":_world.resource_endpoint_name(source),"destination":_world.resource_endpoint_name(destination),"source_slot":slot,"destination_slot":target_slot,"quantity":count,"expected":source.stack_at(slot)})
	return int(result.data.get("quantity",0))

# Layout follows the logical viewport (including canvas stretch). The content
# scrolls rather than dropping controls or shrinking text at small resolutions.
func _layout() -> void:
	if _panel==null:return
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	_panel.position=Vector2(16,16)
	_panel.size=Vector2(minf(1120,viewport.x-32),viewport.y-32)
	_panel.position.x=(viewport.x-_panel.size.x)/2
	_scroll.custom_minimum_size=Vector2.ZERO
	if _top!=null:_top.vertical=viewport.x<1200
	_hotbar.position=Vector2(maxf(8,(viewport.x-_hotbar.get_combined_minimum_size().x)/2),viewport.y-104)

func record_result(operation: String, success: bool, reason: String, pending: bool = false) -> void:
	_feedback_rejected=not success
	_feedback_text=("Pending HOST: " if pending else "Accepted: " if success else "Rejected: ")+operation.replace("_"," ")
	if not success:_feedback_text+=" · "+reason.replace("_"," ")
	if pending:_feedback_text+=" — waiting for authoritative result"
	if _world.player!=null:_world.player.show_status(_feedback_text,3500)

func _ui_command(operation: String, args: Dictionary = {}) -> LfeCommandResult:
	var result: LfeCommandResult = _world.command(_world.local_player_id,operation,args)
	record_result(operation,result.success,result.reason_code,result.data.get("pending",false))
	return result
