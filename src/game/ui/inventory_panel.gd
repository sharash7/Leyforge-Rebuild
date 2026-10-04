class_name LeyforgeInventoryPanel
extends CanvasLayer

var _world: LeyforgeWave1Playground
var _panel: PanelContainer
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

func configure(world: LeyforgeWave1Playground) -> void:
	_world=world
	layer=3
	var base: Control = Control.new()
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(base)
	_hotbar=HBoxContainer.new();_hotbar.position=Vector2(280,550)
	base.add_child(_hotbar)
	for slot: int in 9:
		var button: Button = Button.new()
		button.custom_minimum_size=Vector2(76,54)
		button.clip_text=true
		button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(func() -> void: _world.resources.select(slot))
		_hotbar.add_child(button)
	_panel=PanelContainer.new();_panel.position=Vector2(180,50)
	_panel.custom_minimum_size=Vector2(920,570)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color=Color(0.075,0.095,0.115,0.98)
	style.border_color=Color(0.48,0.36,0.22);style.set_border_width_all(2)
	style.content_margin_left=16;style.content_margin_right=16
	style.content_margin_top=12;style.content_margin_bottom=12
	_panel.add_theme_stylebox_override("panel",style)
	base.add_child(_panel)
	_body=VBoxContainer.new();_body.add_theme_constant_override("separation",6)
	_panel.add_child(_body);_panel.hide()

func open(storage: bool = false) -> bool:
	var id: String = ""
	if storage and not _world.resources.snapshot()["storage"].is_empty():id=_world.resources.snapshot()["storage"][0]["instance"]
	return open_context(id)

func open_context(id: String = "", focus_crafting: bool = false) -> bool:
	if _panel.visible and not close():return false
	_object=id;_storage_id="";_picked_inventory=null;_picked_slot=-1
	_buttons.clear();_progress=null;_output=null;_craft_title=null;crafting=null
	for child: Node in _body.get_children():_body.remove_child(child);child.queue_free()
	var station: LfeWorkstation = _world.creation.station(id)
	var stored: LfeInventory = _world.creation.storage(id)
	if stored==null and not id.is_empty():
		stored=_world.resources.storage_inventory(id)
		if stored!=null:_storage_id=id
	var workbench: bool = false
	for entry: Dictionary in _world.creation.objects():
		if entry["instance"]==id:workbench=_world.block_catalog.content_definition(StringName(entry["content"])).get("function","")=="workbench"
	_label(_body,"Workbench · 3×3 crafting" if workbench else "Stone kiln" if station!=null else "Storage" if stored!=null else "Inventory · personal crafting",22)
	_hint=_label(_body,"",13)
	var top: HBoxContainer = HBoxContainer.new();top.add_theme_constant_override("separation",20);_body.add_child(top)
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
		fire.pressed.connect(func() -> void: _world.player.show_status("Process started" if _world.start_process(_object,"leyforge:charcoal_burn") else station.start_reason("leyforge:charcoal_burn")))
		process.add_child(fire)
		_grid(_column(top,"OUTPUT"),station.output,3,0,3)
	elif stored!=null:
		_storage_group=VBoxContainer.new()
		top.add_child(_storage_group);_label(_storage_group,"STORED",16)
		_grid(_storage_group,stored,3 if not _storage_id.is_empty() else 9,0,stored.capacity())
	else:
		crafting=LfeCraftingGrid.new(_world.block_catalog,_world.creation.recipes,3 if workbench else 2)
		var craft_column: VBoxContainer = _column(top,"")
		_craft_title=_label(craft_column,"CRAFTING  ·  %d×%d" % [crafting.size,crafting.size],16)
		if focus_crafting:_craft_title.modulate=Color(1,0.78,0.35)
		_grid(craft_column,crafting.inventory,crafting.size,0,crafting.inventory.capacity())
		var output_column: VBoxContainer = _column(top,"→ OUTPUT")
		_output=_slot_button();_output.name="CraftOutput"
		_output.pressed.connect(func() -> void:
			_world.craft_recipe(_preview_recipe)
			_refresh())
		output_column.add_child(_output)
		var guide: VBoxContainer = _column(top,"CRAFTING HINT")
		var help: Label = _label(guide,"Log → planks; plank → sticks.\nFour planks fill 2×2 for a Workbench.\nAt a Workbench: head material above\ntwo vertical Oak Sticks.\nPickaxe: three heads; axe: three in an L;\nshovel: one head. Blank cells matter.",12)
		help.custom_minimum_size=Vector2(300,0)
	_grid(_column(top,"EQUIPMENT"),_world.resources.equipment,1,0,_world.resources.equipment.capacity())
	_label(_body,"PLAYER INVENTORY",16);_grid(_body,_world.resources.inventory,9,9,18)
	_label(_body,"HOTBAR  ·  1–9",16);_grid(_body,_world.resources.inventory,9,0,9)
	_label(_body,"Click source, then destination. Right-click splits half; Shift-click quick transfers. Take crafting output to craft once.",12)
	var close_button: Button = Button.new();close_button.text="Close [Escape] — returns staged crafting items"
	close_button.pressed.connect(_world.close_inventory);_body.add_child(close_button)
	_world.set_primary_action(false)
	_panel.show();_hotbar.hide();_world.player.inventory_open=true
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	_refresh()
	return true

func close() -> bool:
	if crafting!=null and not crafting.release(_world.resources.inventory):
		_world.player.show_status("Backpack full — return crafting items to free slots before closing or saving",5000)
		return false
	crafting=null;_picked_inventory=null;_picked_slot=-1
	_panel.hide();_hotbar.show();_world.player.inventory_open=false
	if DisplayServer.get_name()!="headless" and not OS.get_cmdline_user_args().has("--wave3-playtest") and not OS.get_cmdline_user_args().has("--wave4-playtest"):
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	return true

func context_valid() -> bool:
	if _object.is_empty():return true
	if not _storage_id.is_empty():
		for entry: Dictionary in _world.resources.snapshot()["storage"]:
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
	label.add_theme_font_size_override("font_size",size);parent.add_child(label)
	return label

func _slot_button() -> Button:
	var button: Button = Button.new();button.custom_minimum_size=Vector2(86,50)
	button.add_theme_font_size_override("font_size",12);button.clip_text=true
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
	if inventory in [_world.resources.inventory,_world.resources.equipment]:return true
	if crafting!=null and inventory==crafting.inventory:return true
	if not context_valid():return false
	var station: LfeWorkstation = _world.creation.station(_object)
	if station!=null:return inventory in [station.input,station.fuel] or (not destination and inventory==station.output)
	var stored: LfeInventory = _world.creation.storage(_object) if _storage_id.is_empty() else _world.resources.storage_inventory(_storage_id)
	return stored!=null and inventory==stored

func _click_slot(inventory: LfeInventory, slot: int, split: bool, shift: bool) -> void:
	if not _allowed(inventory):return
	var stack: Dictionary = inventory.stack_at(slot)
	if shift and not stack.is_empty():
		var destination: LfeInventory = _world.resources.inventory
		if inventory==destination:
			if crafting!=null:destination=crafting.inventory
			elif not _storage_id.is_empty():destination=_world.resources.storage_inventory(_storage_id)
			else:
				var station: LfeWorkstation = _world.creation.station(_object)
				destination=_world.creation.storage(_object)
				if station!=null:
					var ready: bool = true
					for entry: Dictionary in _world.creation.recipes.definition("leyforge:charcoal_burn")["inputs"]:ready=ready and station.input.total(StringName(entry["content"]))>=int(entry["quantity"])
					destination=station.fuel if ready else station.input
		if destination!=null and _allowed(destination,true):LfeItemTransactions.transfer(inventory,slot,destination,int(stack["quantity"]),-1,true)
		_picked_inventory=null
	elif _picked_inventory==null:
		if not stack.is_empty():_picked_inventory=inventory;_picked_slot=slot
	else:
		var source: Dictionary = _picked_inventory.stack_at(_picked_slot)
		if not source.is_empty() and _allowed(_picked_inventory) and _allowed(inventory,true):
			var count: int = maxi(1,int(source["quantity"])/2) if split else int(source["quantity"])
			var moved: int = LfeItemTransactions.transfer(_picked_inventory,_picked_slot,inventory,count,slot,true)
			if moved==0 and not split and not stack.is_empty() and stack["content"]!=source["content"]:
				if LfeItemTransactions.swap(_picked_inventory,_picked_slot,inventory,slot):moved=count
			_world.player.show_status("Moved %d" % moved if moved>0 else "Transfer rejected — slot/context/full output")
		_picked_inventory=null;_picked_slot=-1
	_refresh()

func _process(_delta: float) -> void:
	if _world==null:return
	for slot: int in 9:
		var button: Button = _hotbar.get_child(slot)
		button.text="%d\n%s" % [slot+1,_stack_text(_world.resources.inventory,slot)]
		button.modulate=Color(1,0.85,0.3) if slot==_world.resources.selected_slot() else Color.WHITE
	if _panel.visible:
		if not context_valid():
			if not close():_hint.text="Context unavailable — staging retained. Return items to backpack to close."
		else:_refresh()

func _refresh() -> void:
	if _hint==null:return
	for entry: Dictionary in _buttons:
		var button: Button = entry["button"]
		button.text=_stack_text(entry["inventory"],entry["slot"]);button.tooltip_text=button.text
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
		if inventory == _world.resources.equipment:
			return LfeResourceState.EQUIPMENT_SLOTS[slot].capitalize() + "
Empty"
		return "—"
	var name: String = _world.block_catalog.content_definition(StringName(stack["content"]))["display_name"]
	if stack.has("durability"):
		return "%s\n%d / %d" % [name,int(stack["durability"]),int(_world.block_catalog.content_definition(StringName(stack["content"]))["tool"]["durability"])]
	return "%s\n×%d" % [name,int(stack["quantity"])]
