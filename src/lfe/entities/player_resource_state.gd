class_name LfePlayerResourceState
extends RefCounted

const PLAYER_SLOTS: int = 27
const HOTBAR_SLOTS: int = 9
const EQUIPMENT_SLOTS: Array[String] = ["hand", "body"]
var inventory: LfeInventory
var equipment: LfeInventory
var _selected: int = 0
var _catalog: LfeBlockCatalog

func _init(catalog: LfeBlockCatalog) -> void:
	_catalog = catalog
	inventory = LfeInventory.new(catalog, PLAYER_SLOTS)
	equipment = LfeInventory.new(catalog, EQUIPMENT_SLOTS.size(), EQUIPMENT_SLOTS)

func selected_slot() -> int:
	return _selected

func select(slot: int) -> bool:
	if slot < 0 or slot >= HOTBAR_SLOTS:
		return false
	_selected = slot
	return true

func snapshot() -> Dictionary:
	return {"inventory":inventory.snapshot(), "equipment":equipment.snapshot(), "hotbar_selected":_selected}

func restore(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=3 or not LfeWorldSave._is_integer(data.get("hotbar_selected")) or int(data["hotbar_selected"])<0 or int(data["hotbar_selected"])>=HOTBAR_SLOTS:return false
	var next: LfeInventory = LfeInventory.new(_catalog,PLAYER_SLOTS)
	var gear: LfeInventory = LfeInventory.new(_catalog,EQUIPMENT_SLOTS.size(),EQUIPMENT_SLOTS)
	if not next.restore(data.get("inventory")) or not gear.restore(data.get("equipment")) or not LfeWorldResourceState.unique_instances(next.snapshot()+gear.snapshot()):return false
	inventory=next;equipment=gear;_selected=int(data["hotbar_selected"])
	return true

func total(id: StringName) -> int:
	return inventory.total(id)+equipment.total(id)
