class_name LeyforgeInventoryPanel
extends CanvasLayer

var _world: LeyforgeWave1Playground
var _panel: PanelContainer
var _hotbar: HBoxContainer
var _buttons: Array[Dictionary] = []
var _picked_inventory: LfeInventory
var _picked_slot: int = -1
var _storage_id: String = ""
var _hint: Label
var _storage_group: VBoxContainer


func configure(world: LeyforgeWave1Playground) -> void:
	_world = world
	layer = 3
	var base: Control = Control.new()
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	_hotbar = HBoxContainer.new()
	_hotbar.position = Vector2(280, 550)
	base.add_child(_hotbar)
	for slot: int in 9:
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(76, 54)
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(func() -> void: _world.resources.select(slot))
		_hotbar.add_child(button)
	_panel = PanelContainer.new()
	_panel.position = Vector2(80, 210)
	base.add_child(_panel)
	var columns: HBoxContainer = HBoxContainer.new()
	_panel.add_child(columns)
	var player_column: VBoxContainer = _column(columns, "Backpack / hotbar")
	_grid(player_column, _world.resources.inventory, 9)
	var equipment_column: VBoxContainer = _column(columns, "Equipment")
	_grid(equipment_column, _world.resources.equipment, 1)
	_storage_group = _column(columns, "Storage crate")
	if not _world.resources.snapshot()["storage"].is_empty():
		_storage_id = _world.resources.snapshot()["storage"][0]["instance"]
		_grid(_storage_group, _world.resources.storage_inventory(_storage_id), 3)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(260, 70)
	_hint.text = "Click source then destination to move/merge. Right-click destination splits half. Shift-click transfers to/from open storage. Click unlike stacks to swap."
	player_column.add_child(_hint)
	_panel.visible = false


func _column(parent: HBoxContainer, title: String) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	parent.add_child(column)
	var label: Label = Label.new()
	label.text = title
	column.add_child(label)
	return column


func _grid(parent: VBoxContainer, inventory: LfeInventory, columns: int) -> void:
	var grid: GridContainer = GridContainer.new()
	grid.columns = columns
	parent.add_child(grid)
	for slot: int in inventory.capacity():
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(76, 54)
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
				_click_slot(inventory, slot, event.button_index == MOUSE_BUTTON_RIGHT, event.shift_pressed)
				button.accept_event()
		)
		grid.add_child(button)
		_buttons.append({"button": button, "inventory": inventory, "slot": slot})


func open(storage: bool = false) -> void:
	_picked_inventory = null
	_picked_slot = -1
	_panel.visible = true
	_storage_group.visible = storage
	_world.player.inventory_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_panel.visible = false
	_picked_inventory = null
	_picked_slot = -1
	_world.player.inventory_open = false
	if DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--wave3-playtest"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if _world == null:
		return
	for slot: int in 9:
		var button: Button = _hotbar.get_child(slot)
		button.text = "%d
%s" % [slot + 1, _stack_text(_world.resources.inventory, slot)]
		button.modulate = Color(1.0, 0.85, 0.3) if slot == _world.resources.selected_slot() else Color.WHITE
	for entry: Dictionary in _buttons:
		var button: Button = entry["button"]
		button.text = _stack_text(entry["inventory"], entry["slot"])
		button.tooltip_text = button.text
		button.modulate = Color(1.0, 0.85, 0.3) if entry["inventory"] == _picked_inventory and entry["slot"] == _picked_slot else Color.WHITE


func _stack_text(inventory: LfeInventory, slot: int) -> String:
	var stack: Dictionary = inventory.stack_at(slot)
	if stack.is_empty():
		if inventory == _world.resources.equipment:
			return LfeResourceState.EQUIPMENT_SLOTS[slot].capitalize() + "
Empty"
		return "—"
	var name: String = _world.block_catalog.content_definition(StringName(stack["content"]))["display_name"]
	return "%s
×%d" % [name, int(stack["quantity"])]


func _click_slot(inventory: LfeInventory, slot: int, split: bool, shift: bool) -> void:
	var stack: Dictionary = inventory.stack_at(slot)
	if shift and _storage_group.visible and not stack.is_empty():
		var storage: LfeInventory = _world.resources.storage_inventory(_storage_id)
		var destination: LfeInventory = storage if inventory == _world.resources.inventory else _world.resources.inventory
		var moved: int = LfeItemTransactions.transfer(inventory, slot, destination, int(stack["quantity"]), -1, true)
		_world.player.show_status("Transferred %d" % moved if moved > 0 else "Destination is full")
		return
	if _picked_inventory == null:
		if not stack.is_empty():
			_picked_inventory = inventory
			_picked_slot = slot
		return
	var source: Dictionary = _picked_inventory.stack_at(_picked_slot)
	if source.is_empty() or (_picked_inventory == inventory and _picked_slot == slot):
		_picked_inventory = null
		return
	var quantity: int = maxi(1, int(source["quantity"]) / 2) if split else int(source["quantity"])
	var moved: int = LfeItemTransactions.transfer(_picked_inventory, _picked_slot, inventory, quantity, slot, true)
	if moved == 0 and not split and not stack.is_empty() and stack["content"] != source["content"]:
		if LfeItemTransactions.swap(_picked_inventory, _picked_slot, inventory, slot):
			moved = int(source["quantity"])
	_world.player.show_status("Moved %d" % moved if moved > 0 else "Transfer rejected")
	_picked_inventory = null
	_picked_slot = -1
