class_name LeyforgeCreationPanel
extends CanvasLayer

var _world: LeyforgeWave1Playground
var _panel: PanelContainer
var _body: VBoxContainer
var _status: Label
var _hud: Label
var _object: String = ""
var _timer: float = 0.0

func configure(world: LeyforgeWave1Playground) -> void:
	_world = world
	layer = 4
	var control: Control = Control.new()
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(control)
	_hud = Label.new()
	_hud.position = Vector2(930,20)
	_hud.add_theme_font_size_override("font_size",19)
	control.add_child(_hud)
	_panel = PanelContainer.new()
	_panel.position = Vector2(270,160)
	_panel.custom_minimum_size = Vector2(670,310)
	control.add_child(_panel)
	_body = VBoxContainer.new()
	_panel.add_child(_body)
	_panel.hide()

func open(id: String = "") -> void:
	_object = id
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var title: Label = Label.new()
	title.text = "Hand crafting — exact ingredients → outputs" if id.is_empty() else "Work area — select a hotbar resource to deposit"
	_body.add_child(title)
	_status = Label.new()
	_body.add_child(_status)
	if id.is_empty():
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(650,310)
		_body.add_child(scroll)
		var list: VBoxContainer = VBoxContainer.new()
		scroll.add_child(list)
		for recipe: Dictionary in _world.creation.recipes.all():
			if recipe["context"] != "hand":
				continue
			var button: Button = Button.new()
			button.text = "%s → %s" % [_entries(recipe["inputs"]),_entries(recipe["outputs"])]
			button.pressed.connect(func() -> void: _world.craft_recipe(recipe["id"]))
			list.add_child(button)
	else:
		var station: LfeWorkstation = _world.creation.station(id)
		if station != null:
			_channel("input","Input",station.input)
			_channel("fuel","Fuel",station.fuel)
			_channel("output","Output",station.output)
			for recipe: Dictionary in _world.creation.recipes.all():
				if recipe["context"] != "kiln":
					continue
				var start: Button = Button.new()
				start.text = "Start: %s + fuel %s → %s (%.0f s)" % [_entries(recipe["inputs"]),_entries(recipe["fuel"]),_entries(recipe["outputs"]),float(recipe["seconds"])]
				start.pressed.connect(func() -> void:
					_world.player.show_status("Process started" if _world.start_process(id,recipe["id"]) else "Process rejected: inputs/fuel/output/context"))
				_body.add_child(start)
		else:
			_channel("storage","Storage",_world.creation.storage(id))
	var close_button: Button = Button.new()
	close_button.text = "Close [Escape]"
	close_button.pressed.connect(_world.close_inventory)
	_body.add_child(close_button)
	_panel.show()
	_world.player.inventory_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	_panel.hide()
	_world.player.inventory_open = false

func _channel(channel: String, title: String, inventory: LfeInventory) -> void:
	if inventory == null:
		return
	var row: HBoxContainer = HBoxContainer.new()
	_body.add_child(row)
	var label: Label = Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(60,0)
	row.add_child(label)
	if channel != "output":
		var deposit: Button = Button.new()
		deposit.text = "Deposit selected ×1"
		deposit.pressed.connect(func() -> void:
			var moved: int = _world.transfer_object(_object,channel,_world.resources.selected_slot(),1,false)
			_world.player.show_status("Deposited %d" % moved))
		row.add_child(deposit)
	for slot: int in inventory.capacity():
		var withdraw: Button = Button.new()
		withdraw.text = "Take %d" % (slot+1)
		withdraw.pressed.connect(func() -> void:
			var moved: int = _world.transfer_object(_object,channel,slot,1,true)
			_world.player.show_status("Withdrew %d" % moved))
		row.add_child(withdraw)

func _process(delta: float) -> void:
	if _world == null:
		return
	_timer -= delta
	if _timer > 0:
		return
	_timer = 0.2
	var v: Dictionary = _world.creation.survival.snapshot()
	_hud.text = "Health %.0f  |  Stamina %.0f\nFood %.0f  |  Water %.0f\nFatigue %.1f  |  Exposure %.1f\n%s%s" % [v["health"],v["stamina"],v["hunger"],v["thirst"],v["fatigue"],v["exposure"],"Sheltered" if _world._sheltered else "Exposed"," — resting" if _world._resting else ""]
	if not _panel.visible or _status == null:
		return
	if not _object.is_empty():
		if not _world.object_near(_object):
			_world.close_inventory()
			return
		var station: LfeWorkstation = _world.creation.station(_object)
		_status.text = (station.status() + "\nInput: " + _slots(station.input) + "  Fuel: " + _slots(station.fuel) + "\nOutput: " + _slots(station.output)) if station != null else "Stored: " + _slots(_world.creation.storage(_object))
	else:
		_status.text = "Crafting checks inventory capacity before committing. Recipes known by default."

func _entries(entries: Array) -> String:
	var parts: PackedStringArray = []
	for entry: Dictionary in entries:
		parts.append("%d %s" % [int(entry["quantity"]),_world.block_catalog.content_definition(StringName(entry["content"]))["display_name"]])
	return ", ".join(parts)

func _slots(inventory: LfeInventory) -> String:
	if inventory == null:
		return ""
	var parts: PackedStringArray = []
	for slot: int in inventory.capacity():
		var stack: Dictionary = inventory.stack_at(slot)
		parts.append("%d: %s" % [slot+1,"empty" if stack.is_empty() else _entries([stack])])
	return " | ".join(parts)
