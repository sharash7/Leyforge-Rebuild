class_name LfePlayerCharacter
extends RefCounted

# Durable world-local state; independent of the controller's Node lifetime.
var player_id: String
var transform: Dictionary = {}
var resources: LfePlayerResourceState
var survival: LfeCharacterSurvival = LfeCharacterSurvival.new()
var _catalog: LfeBlockCatalog

func _init(id: String,catalog: LfeBlockCatalog) -> void:
	player_id=id;_catalog=catalog;resources=LfePlayerResourceState.new(catalog)

func snapshot() -> Dictionary:
	return {"player_id":player_id,"transform":transform.duplicate(true),"resources":resources.snapshot(),"survival":survival.snapshot()}

func restore(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=4 or data.get("player_id")!=player_id or not LfeWorldResourceState._valid_identity(player_id) or not valid_transform(data.get("transform"),_catalog):return false
	var personal: LfePlayerResourceState=LfePlayerResourceState.new(_catalog)
	var biology: LfeCharacterSurvival=LfeCharacterSurvival.new()
	if not personal.restore(data.get("resources")) or not biology.restore(data.get("survival")):return false
	transform=data["transform"].duplicate(true);resources=personal;survival=biology
	return true

static func valid_transform(data: Variant,catalog: LfeBlockCatalog) -> bool:
	if not data is Dictionary or data.size() not in [3,4] or not LfeWorldResourceState._valid_position(data.get("position")) or not LfeWorldSave._finite_in_range(data.get("yaw"),1000000) or not LfeWorldSave._finite_in_range(data.get("pitch"),1.553344):return false
	for key: Variant in data:
		if key not in ["position","yaw","pitch","selected_block"]:return false
	var selected: Variant=data.get("selected_block","")
	return selected is String and (selected.is_empty() or catalog.has_id(StringName(selected)))
