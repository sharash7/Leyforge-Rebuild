class_name LfeTestWorldSave
extends LfeWorldSave

# Historical assertions use their old field names, but save/load is always v4.
var player_state: Dictionary:
	get:
		for p: Dictionary in players_state:
			if p["player_id"]==local_player_id:return p["transform"].duplicate(true)
		return {}
var resource_state: Dictionary:
	get:
		var r: Dictionary=LfePlayerResourceState.new(_catalog).snapshot()
		for p: Dictionary in players_state:
			if p["player_id"]==local_player_id:r=p["resources"].duplicate(true)
		r.merge(world_resource_state.duplicate(true));return r
var legacy_creation_state: Dictionary:
	get:
		var c: Dictionary=creation_state.duplicate(true)
		c["survival"]=LfeCharacterSurvival.new().snapshot()
		for p: Dictionary in players_state:
			if p["player_id"]==local_player_id:c["survival"]=p["survival"].duplicate(true)
		return c
func save(transform: Variant=null,mixed_resources: Variant=null,mixed_creation: Variant=null) -> Error:
	var r: Variant=resource_state if mixed_resources==null else mixed_resources
	var c: Variant=legacy_creation_state if mixed_creation==null else mixed_creation
	if not transform is Dictionary or not r is Dictionary or r.size()!=5 or not c is Dictionary or c.size()!=5:return ERR_INVALID_DATA
	var creation: Dictionary=c.duplicate(true);creation.erase("survival")
	var player: Dictionary={"player_id":local_player_id,"transform":transform,"resources":{"inventory":r.get("inventory"),"equipment":r.get("equipment"),"hotbar_selected":r.get("hotbar_selected")},"survival":c.get("survival")}
	return super.save([player],{"drops":r.get("drops"),"storage":r.get("storage")},creation)
func is_dirty(transform: Variant,resources: Dictionary={},creation: Dictionary={}) -> bool:
	return _edits_dirty or player_state!=transform or (not resources.is_empty() and resource_state!=resources) or (not creation.is_empty() and legacy_creation_state!=creation) or last_saved_utc.is_empty()
static func player_transform(save: LfeWorldSave) -> Dictionary:
	for p: Dictionary in save.players_state:
		if p["player_id"]==save.local_player_id:return p["transform"].duplicate(true)
	return {}
static func legacy_payload(payload: Dictionary,version: int) -> Dictionary:
	if not payload.has("players"):return payload
	var data: Dictionary=payload.duplicate(true)
	var player: Dictionary=data["players"][0]
	data["player"]=player["transform"]
	data["resources"]=player["resources"];data["resources"].merge(data["world_resources"])
	data["creation"]["survival"]=player["survival"]
	data.erase("players");data.erase("world_resources");data["metadata"].erase("owner_player_id")
	data["metadata"]["save_version"]=version
	return data
