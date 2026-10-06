class_name LfeResourceReplica
extends RefCounted

# Session-only facts. These objects provide display snapshots; UI submits commands.
var catalog: LfeBlockCatalog
var player_id: String
var personal: LfePlayerResourceState
var recipes: LfeRecipeCatalog = LfeRecipeCatalog.new()
var revisions: Dictionary = {}
var states: Dictionary = {}
var transfers: Dictionary = {}
var position_sequences: Dictionary = {}
var inventories: Dictionary = {}
var stations: Dictionary = {}
var grid: LfeCraftingGrid
var ready: bool = false
var _definitions: Dictionary = {}

func configure(c: LfeBlockCatalog, actor: String) -> void:
	catalog = c; player_id = actor
	personal = LfePlayerResourceState.new(c)
	recipes.load_default(c)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/world_objects/wave_4_sources.json"))
	for spec: Dictionary in data["sources"]: _definitions[spec["id"]] = spec

func valid_state(key: String, s: Dictionary) -> bool:
	var family: String = key.get_slice("/",0)
	var id: String = key.get_slice("/",1)
	match family:
		"player":
			return id == player_id and LfePlayerResourceState.new(catalog).restore(s)
		"grid":
			if id != player_id or not LfeCompatibilityManifest.exact_keys(s,["size","slots","context"]): return false
			return LfeResourceProtocol.integer(s["size"],2,3) and s["context"] is String and (s["context"].is_empty() or LfeWorldResourceState._valid_identity(s["context"])) and LfeInventory.new(catalog,int(s["size"])*int(s["size"])).validate(s["slots"])
		"drop":
			return LfeCompatibilityManifest.exact_keys(s,["instance","stack","position"]) and s["instance"] == id and LfeItemStack.valid(s["stack"],catalog,false) and LfeWorldResourceState._valid_position(s["position"])
		"source":
			if not LfeCompatibilityManifest.exact_keys(s,["instance","source","position","remaining"]) or s["instance"] != id or not s["source"] is String or not _definitions.has(s["source"]): return false
			return LfeWorldResourceState._valid_position(s["position"]) and LfeResourceProtocol.integer(s["remaining"],0,int(_definitions[s["source"]]["quantity"]))
		"storage":
			return LfeCompatibilityManifest.exact_keys(s,["instance","content","position","slots"]) and s["instance"] == id and s["content"] == "leyforge:storage_crate" and LfeWorldResourceState._valid_position(s["position"]) and LfeInventory.new(catalog,9).validate(s["slots"])
		"object":
			if s.get("instance") != id: return false
			# Canonical object validation includes function-specific slots/process state.
			var validator: LfeCreationState = LfeCreationState.new(catalog)
			return validator.restore({"objects":[s],"sources":[],"initialized":true,"elapsed":0.0})
	return false

func receive(p: Dictionary, now: float) -> Dictionary:
	var key: String = p.get("stream","")
	match p["kind"]:
		"resource_ready":
			if not states.has("player/"+player_id) or states.size() != int(p["count"]) or LfeResourceProtocol.normalized(revisions).sha256_text() != p["hash"] or not unique_snapshot(): return {"ok":false,"fatal":true}
			ready = true
			return {"ok":true}
		"resource_forget":
			states.erase(key); revisions.erase(key); position_sequences.erase(key)
			if key.begins_with("storage/"): inventories.erase(key)
			if key.begins_with("object/"):
				inventories.erase("storage/"+key.get_slice("/",1)); stations.erase(key.get_slice("/",1))
			if key.begins_with("grid/"): grid = null
			for t: String in transfers.keys():
				if transfers[t]["stream"] == key: transfers.erase(t)
			return {"ok":true}
		"resource_position":
			if not states.has(key) or int(revisions[key]) != int(p["revision"]) or int(p["sequence"]) <= int(position_sequences.get(key,0)): return {"ok":false}
			position_sequences[key] = int(p["sequence"])
			states[key]["position"] = p["position"].duplicate()
			return {"ok":true}
		"resource_part":
			if int(p["from_revision"]) >= 0 and int(p["revision"]) <= int(revisions.get(key,0)): return {"ok":true}
			if int(p["from_revision"]) >= 0 and int(p["from_revision"]) != int(revisions.get(key,0)): return {"ok":false,"resync":key}
			var t: String = p["transfer"]
			if not transfers.has(t):
				if transfers.size() >= 32 or (not states.has(key) and states.size() >= LfeResourceProtocol.MAX_STREAMS): return {"ok":false,"fatal":true}
				transfers[t] = {"stream":key,"revision":p["revision"],"from_revision":p["from_revision"],"count":p["count"],"hash":p["hash"],"parts":{},"deadline":now+5.0}
			var tx: Dictionary = transfers[t]
			for field: String in ["stream","revision","from_revision","count","hash"]:
				if tx[field] != p[field]: transfers.erase(t); return {"ok":false,"resync":key}
			var part: int = int(p["part"])
			if tx["parts"].has(part) and tx["parts"][part] != p["bytes"]: transfers.erase(t); return {"ok":false,"resync":key}
			tx["parts"][part] = p["bytes"]
			if tx["parts"].size() < int(tx["count"]): return {"ok":true}
			var data: PackedByteArray = PackedByteArray()
			for i: int in int(tx["count"]): data.append_array(String(tx["parts"][i]).hex_decode())
			transfers.erase(t)
			var s: Variant = JSON.parse_string(data.get_string_from_utf8())
			if data.hex_encode().sha256_text() != tx["hash"] or not s is Dictionary or not valid_state(key,s): return {"ok":false,"resync":key}
			if not publish(key,s): return {"ok":false,"resync":key}
			revisions[key] = int(p["revision"])
			return {"ok":true,"applied":key}
	return {"ok":false}

func unique_snapshot() -> bool:
	var slots: Array = []
	for s: Dictionary in states.values():
		if s.has("inventory"): slots.append_array(s["inventory"]); slots.append_array(s["equipment"])
		if s.has("slots"): slots.append_array(s["slots"])
		if s.has("stack"): slots.append(s["stack"])
		if s.has("station"):
			for part: String in ["input","fuel","output"]: slots.append_array(s["station"][part])
	return LfeWorldResourceState.unique_instances(slots)

func publish(key: String, s: Dictionary) -> bool:
	match key.get_slice("/",0):
		"player":
			personal.inventory.restore(s["inventory"]); personal.equipment.restore(s["equipment"]); personal.select(int(s["hotbar_selected"]))
		"grid":
			if grid == null or grid.size != int(s["size"]): grid = LfeCraftingGrid.new(catalog,recipes,int(s["size"]))
			grid.inventory.restore(s["slots"])
		"storage":
			var name: String = "storage/"+s["instance"]
			if not inventories.has(name): inventories[name] = LfeInventory.new(catalog,9)
			inventories[name].restore(s["slots"])
		"object":
			var id: String = s["instance"]
			if s.has("slots"):
				var name: String = "storage/"+id
				if not inventories.has(name): inventories[name] = LfeInventory.new(catalog,9)
				inventories[name].restore(s["slots"])
			if s.has("station"):
				if not stations.has(id): stations[id] = LfeWorkstation.new(catalog,recipes)
				stations[id].restore(s["station"])
	states[key] = s.duplicate(true)
	return true

func expire(now: float) -> Array[String]:
	var keys: Array[String] = []
	for t: String in transfers.keys():
		if now > float(transfers[t]["deadline"]): keys.append(transfers[t]["stream"]); transfers.erase(t)
	return keys

func _family(family: String) -> Array:
	var result: Array = []
	for key: String in states:
		if key.begins_with(family+"/"): result.append(states[key].duplicate(true))
	return result

func drops() -> Array: return _family("drop")
func drop(id: String) -> Dictionary: return states.get("drop/"+id,{}).duplicate(true)
func sources() -> Array: return _family("source")
func source(id: String) -> Dictionary: return states.get("source/"+id,{}).duplicate(true)
func source_definition(id: String) -> Dictionary: return _definitions.get(id,{}).duplicate(true)
func objects() -> Array: return _family("object")
func object_at(cell: Vector3i) -> String:
	for s: Dictionary in objects():
		if LfeVoxelProtocol.cell(s["cell"]) == cell: return s["instance"]
	return ""
func storage(id: String) -> LfeInventory: return inventories.get("storage/"+id)
func storage_inventory(id: String) -> LfeInventory: return storage(id)
func station(id: String) -> LfeWorkstation: return stations.get(id) if states.has("object/"+id) else null
func storage_definition() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://content/world_objects/wave_3_crate.json"))
func snapshot() -> Dictionary: return {"drops":drops(),"storage":_family("storage")}
func endpoint(name: String) -> LfeInventory:
	if name == "inventory": return personal.inventory
	if name == "equipment": return personal.equipment
	if name == "grid": return grid.inventory if grid != null else null
	if name.begins_with("station/"):
		var s: LfeWorkstation = station(name.get_slice("/",1))
		if s == null: return null
		match name.get_slice("/",2):
			"input": return s.input
			"fuel": return s.fuel
			"output": return s.output
	return inventories.get(name)
func endpoint_name(inventory: LfeInventory) -> String:
	for name: String in ["inventory","equipment","grid"] + inventories.keys():
		if endpoint(name) == inventory: return name
	for id: String in stations:
		for part: String in ["input","fuel","output"]:
			var name: String = "station/"+id+"/"+part
			if endpoint(name) == inventory: return name
	return ""
