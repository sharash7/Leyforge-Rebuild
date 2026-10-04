class_name LfeInventory
extends RefCounted

var _catalog: LfeBlockCatalog
var _slots: Array = []
var _restrictions: Array[String] = []


func _init(catalog: LfeBlockCatalog, capacity: int = 27, restrictions: Array[String] = []) -> void:
	_catalog = catalog
	_slots.resize(capacity)
	_slots.fill(null)
	_restrictions = restrictions.duplicate()


func capacity() -> int:
	return _slots.size()


func snapshot() -> Array:
	return _slots.duplicate(true)


func stack_at(slot: int) -> Dictionary:
	if slot < 0 or slot >= capacity() or _slots[slot] == null:
		return {}
	return (_slots[slot] as Dictionary).duplicate(true)


func accepts(slot: int, id: StringName) -> bool:
	return slot >= 0 and slot < capacity() and _catalog.is_inventory_content(id) and (
		_restrictions.is_empty() or _catalog.equipment_accepts(id, _restrictions[slot])
	)


func validate(values: Variant) -> bool:
	if not values is Array or values.size() != capacity():
		return false
	for slot: int in capacity():
		if not LfeItemStack.valid(values[slot], _catalog):
			return false
		if values[slot] != null and not accepts(slot, StringName(values[slot]["content"])):
			return false
	return LfeWorldResourceState.unique_instances(values)


func restore(values: Variant) -> bool:
	if not validate(values):
		return false
	_slots = []
	for value: Variant in values:
		if value == null:
			_slots.append(null)
		else:
			var stack: Dictionary = value.duplicate(true)
			stack["quantity"] = int(stack["quantity"])
			if stack.has("durability"):
				stack["durability"] = int(stack["durability"])
			_slots.append(stack)
	return true


func total(id: StringName) -> int:
	var quantity: int = 0
	for value: Variant in _slots:
		if value != null and StringName(value["content"]) == id:
			quantity += int(value["quantity"])
	return quantity
