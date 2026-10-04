class_name LfeTestResourceView
extends RefCounted
const PLAYER_SLOTS = LfePlayerResourceState.PLAYER_SLOTS
const HOTBAR_SLOTS = LfePlayerResourceState.HOTBAR_SLOTS
const EQUIPMENT_SLOTS = LfePlayerResourceState.EQUIPMENT_SLOTS
var personal: LfePlayerResourceState
var world: LfeWorldResourceState
var inventory: LfeInventory:
	get:return personal.inventory
var equipment: LfeInventory:
	get:return personal.equipment
var _catalog: LfeBlockCatalog
func _init(catalog: LfeBlockCatalog) -> void:
	_catalog=catalog;personal=LfePlayerResourceState.new(catalog);world=LfeWorldResourceState.new(catalog)
static func view(p: LfePlayerResourceState,w: LfeWorldResourceState) -> LfeTestResourceView:
	var result: LfeTestResourceView=LfeTestResourceView.new(p._catalog)
	result.personal=p;result.world=w
	return result
func snapshot() -> Dictionary:
	var result: Dictionary=personal.snapshot();result.merge(world.snapshot());return result
func restore(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=5:return false
	var p: LfePlayerResourceState=LfePlayerResourceState.new(_catalog)
	var w: LfeWorldResourceState=LfeWorldResourceState.new(_catalog)
	if not p.restore({"inventory":data.get("inventory"),"equipment":data.get("equipment"),"hotbar_selected":data.get("hotbar_selected")}) or not w.restore({"drops":data.get("drops"),"storage":data.get("storage")}):return false
	var seen: Dictionary={};var slots: Array=p.inventory.snapshot()+p.equipment.snapshot()
	for e: Dictionary in w.snapshot()["drops"]:seen[e["instance"]]=true;slots.append(e["stack"])
	for e: Dictionary in w.snapshot()["storage"]:seen[e["instance"]]=true;slots.append_array(e["slots"])
	if not LfeWorldResourceState.unique_instances(slots,seen):return false
	personal=p;world=w;return true
func selected_slot() -> int:return personal.selected_slot()
func select(slot: int) -> bool:return personal.select(slot)
func storage_definition() -> Dictionary:return world.storage_definition()
func ensure_crate(position: Vector3) -> String:return world.ensure_crate(position)
func storage_inventory(id: String) -> LfeInventory:return world.storage_inventory(id)
func drops() -> Array:return world.drops()
func drop(id: String) -> Dictionary:return world.drop(id)
func pickup(id: String) -> int:return world.pickup(personal,id)
func drop_from_inventory(slot: int,count: int,p: Vector3) -> String:return world.drop_from_inventory(personal,slot,count,p)
func break_to_drop(block: StringName,p: Vector3,commit: Callable,outputs: Variant=null) -> bool:return world.break_to_drop(block,p,commit,outputs)
func place_from_inventory(slot: int,commit: Callable) -> bool:return world.place_from_inventory(personal,slot,commit)
func total(id: StringName) -> int:return personal.total(id)+world.total(id)
func advance_drop_clusters(s: float,relevant: Callable,clear: Callable,rest: Callable=Callable()) -> bool:return world.advance_drop_clusters(s,relevant,clear,rest)
func ground_drop(id: String,rest: Callable) -> bool:return world.ground_drop(id,rest)
func settle_drops(relevant: Callable,rest: Callable) -> bool:return world.settle_drops(relevant,rest)
