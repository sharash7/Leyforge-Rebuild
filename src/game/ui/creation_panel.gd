class_name LeyforgeCreationPanel
extends CanvasLayer

var _world: LeyforgeWave1Playground
var _panel: PanelContainer
var _body: VBoxContainer
var _status: Label
var _hud: Label
var _context: Label
var _progress: ProgressBar
var _object: String = ""
var _buttons: Array[Dictionary] = []
var _recipes: Dictionary = {}
var _picked: LfeInventory
var _picked_slot: int = -1

func configure(world: LeyforgeWave1Playground) -> void:
	_world=world
	layer=4
	var base: Control = Control.new()
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(base)
	_hud=Label.new()
	_hud.position=Vector2(950,20)
	base.add_child(_hud)
	_context=Label.new()
	_context.position=Vector2(330,370)
	_context.custom_minimum_size=Vector2(620,35)
	_context.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	base.add_child(_context)
	_panel=PanelContainer.new()
	_panel.position=Vector2(210,100)
	_panel.custom_minimum_size=Vector2(860,500)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color=Color(0.075,0.095,0.115,0.98)
	style.border_color=Color(0.48,0.36,0.22)
	style.set_border_width_all(2)
	style.content_margin_left=18;style.content_margin_right=18
	style.content_margin_top=12;style.content_margin_bottom=12
	_panel.add_theme_stylebox_override("panel",style)
	base.add_child(_panel)
	_body=VBoxContainer.new()
	_body.add_theme_constant_override("separation",8)
	_panel.add_child(_body)
	_panel.hide()

func open(id: String = "") -> void:
	_object=id
	_picked=null
	_picked_slot=-1
	_buttons.clear();_recipes.clear()
	_progress=null
	for child: Node in _body.get_children():
		_body.remove_child(child);child.queue_free()
	_label(_body,"Hand crafting" if id.is_empty() else "Stone kiln" if _world.creation.station(id)!=null else "Storage box",22)
	_status=_label(_body,"",14)
	if id.is_empty():
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.custom_minimum_size=Vector2(810,380)
		_body.add_child(scroll)
		var list: VBoxContainer = VBoxContainer.new()
		scroll.add_child(list)
		for recipe: Dictionary in _world.creation.recipes.all():
			if recipe["context"]!="hand":
				continue
			var button: Button = Button.new()
			button.text="%s → %s" % [_entries(recipe["inputs"]),_entries(recipe["outputs"])]
			button.pressed.connect(func() -> void: _world.craft_recipe(recipe["id"]))
			list.add_child(button)
			_recipes[recipe["id"]]=button
	else:
		var station: LfeWorkstation = _world.creation.station(id)
		if station!=null:
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation",20)
			_body.add_child(row)
			var left: VBoxContainer = VBoxContainer.new();row.add_child(left)
			_label(left,"INPUT",16);_grid(left,station.input,3,0,3)
			_label(left,"FUEL",16);_grid(left,station.fuel,1,0,1)
			var middle: VBoxContainer = VBoxContainer.new();row.add_child(middle)
			middle.custom_minimum_size=Vector2(210,0)
			_label(middle,"CHARCOAL BURN",16)
			var recipe: Dictionary = _world.creation.recipes.definition("leyforge:charcoal_burn")
			_label(middle,_entries(recipe["inputs"])+"\nFuel: "+_entries(recipe["fuel"])+"\n→ "+_entries(recipe["outputs"]),12)
			_progress=ProgressBar.new()
			_progress.custom_minimum_size=Vector2(200,25)
			middle.add_child(_progress)
			var fire: Button = Button.new();fire.name="StartProcess"
			fire.text="Fire kiln"
			fire.pressed.connect(func() -> void:
				_world.player.show_status("Process started" if _world.start_process(_object,"leyforge:charcoal_burn") else station.start_reason("leyforge:charcoal_burn")))
			middle.add_child(fire)
			var right: VBoxContainer = VBoxContainer.new();row.add_child(right)
			_label(right,"OUTPUT",16);_grid(right,station.output,3,0,3)
		else:
			_label(_body,"STORED",16)
			_grid(_body,_world.creation.storage(id),9,0,9)
		_label(_body,"PLAYER INVENTORY",16)
		_grid(_body,_world.resources.inventory,9,9,18)
		_label(_body,"HOTBAR  ·  1–9",16)
		_grid(_body,_world.resources.inventory,9,0,9)
		_label(_body,"Click source, then destination. Right-click splits half. Shift-click quick transfers. Output is withdrawal only.",12)
	var close_button: Button = Button.new()
	close_button.text="Close [Escape]"
	close_button.pressed.connect(_world.close_inventory)
	_body.add_child(close_button)
	_panel.show()
	_world.player.inventory_open=true
	_world.inventory_panel._hotbar.hide()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	_refresh()

func close() -> void:
	_panel.hide()
	_picked=null
	_world.player.inventory_open=false
	_world.inventory_panel._hotbar.show()

func _label(parent: Node, text: String, size: int) -> Label:
	var label: Label = Label.new()
	label.text=text
	label.add_theme_font_size_override("font_size",size)
	parent.add_child(label)
	return label

func _grid(parent: Node, inventory: LfeInventory, columns: int, first: int, count: int) -> void:
	if inventory==null:
		return
	var grid: GridContainer = GridContainer.new()
	grid.columns=columns
	parent.add_child(grid)
	for slot: int in range(first,first+count):
		var button: Button = Button.new()
		button.custom_minimum_size=Vector2(86,58)
		button.add_theme_font_size_override("font_size",12)
		var normal: StyleBoxFlat = StyleBoxFlat.new()
		normal.bg_color=Color(0.13,0.16,0.19)
		normal.border_color=Color(0.36,0.42,0.45)
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(3)
		button.add_theme_stylebox_override("normal",normal)
		var hover: StyleBoxFlat = normal.duplicate()
		hover.border_color=Color(0.95,0.71,0.35)
		hover.bg_color=Color(0.19,0.22,0.25)
		button.add_theme_stylebox_override("hover",hover)
		button.clip_text=true
		button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		button.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
				_click_slot(inventory,slot,event.button_index==MOUSE_BUTTON_RIGHT,event.shift_pressed)
				button.accept_event())
		grid.add_child(button)
		_buttons.append({"button":button,"inventory":inventory,"slot":slot})

func _click_slot(inventory: LfeInventory, slot: int, split: bool, shift: bool) -> void:
	var stack: Dictionary = inventory.stack_at(slot)
	var station: LfeWorkstation = _world.creation.station(_object)
	if shift and not stack.is_empty():
		var destination: LfeInventory = _world.resources.inventory
		if inventory==destination:
			destination=_world.creation.storage(_object)
			if station!=null:
				var ready: bool = true
				for requirement: Dictionary in _world.creation.recipes.definition("leyforge:charcoal_burn")["inputs"]:
					ready = ready and station.input.total(StringName(requirement["content"])) >= int(requirement["quantity"])
				destination=station.fuel if ready else station.input
		_world.workstation_slot_transfer(_object,inventory,slot,destination,-1,int(stack["quantity"]))
		_picked=null
	elif _picked==null:
		if not stack.is_empty():
			_picked=inventory;_picked_slot=slot
	else:
		var source: Dictionary = _picked.stack_at(_picked_slot)
		if not source.is_empty():
			var count: int = maxi(1,int(source["quantity"])/2) if split else int(source["quantity"])
			var moved: int = _world.workstation_slot_transfer(_object,_picked,_picked_slot,inventory,slot,count)
			_world.player.show_status("Moved %d" % moved if moved>0 else "Transfer rejected — output is withdrawal only / slot full")
		_picked=null;_picked_slot=-1
	_refresh()

func _process(_delta: float) -> void:
	if _world==null:
		return
	var v: Dictionary = _world.creation.survival.snapshot()
	var water: String = "  |  Water %.0f" % v["thirst"] if _world.creation.survival.thirst_enabled() else ""
	_hud.text="Health %.0f  |  Stamina %.0f\nFood %.0f%s\nFatigue %.1f\n%s" % [v["health"],v["stamina"],v["hunger"],water,v["fatigue"],"Sheltered" if _world._sheltered else "Outdoors"]
	_context.text=_world.player.context_text()
	_context.visible=not _world.player.inventory_open
	if _panel.visible:
		if not _object.is_empty() and not _world.object_near(_object):
			_world.close_inventory()
		else:
			_refresh()

func _refresh() -> void:
	if _status==null:
		return
	var station: LfeWorkstation = _world.creation.station(_object)
	_status.text="Select a recipe; exact ingredients and capacity are validated." if _object.is_empty() else "Select a stack, then a destination slot."
	if station!=null:
		_status.text=station.status()+"  ·  "+station.start_reason("leyforge:charcoal_burn")
		_progress.value=float(station.snapshot()["progress"])/float(_world.creation.recipes.definition("leyforge:charcoal_burn")["seconds"])*100
	for entry: Dictionary in _buttons:
		var inventory: LfeInventory = entry["inventory"]
		var slot: int = entry["slot"]
		var button: Button = entry["button"]
		button.text=_world.inventory_panel._stack_text(inventory,slot)
		button.tooltip_text=button.text
		button.modulate=Color(1,0.78,0.35) if inventory==_picked and slot==_picked_slot else Color.WHITE

func _entries(entries: Array) -> String:
	var parts: PackedStringArray = []
	for entry: Dictionary in entries:
		parts.append("%d %s" % [int(entry["quantity"]),_world.block_catalog.content_definition(StringName(entry["content"]))["display_name"]])
	return ", ".join(parts)
