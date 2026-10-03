class_name LfeCreationState
extends RefCounted

var survival: LfeCharacterSurvival = LfeCharacterSurvival.new()
var recipes: LfeRecipeCatalog = LfeRecipeCatalog.new()
var _catalog: LfeBlockCatalog
var _objects: Dictionary = {}
var _sources: Array = []
var _initialized: bool = false
var _elapsed: float = 0.0
var _source_definitions: Dictionary = {}
var content_error: String = ""

func _init(catalog: LfeBlockCatalog) -> void:
	_catalog = catalog
	recipes.load_default(catalog)
	var root: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/world_objects/wave_4_sources.json"))
	if not root is Dictionary or root.get("schema_version") != 1 or not root.get("sources") is Array:
		content_error = "Invalid gathering source catalog"
		return
	for spec: Variant in root["sources"]:
		if not _valid_source_definition(spec):
			content_error = "Invalid source definition"
			_source_definitions.clear()
			return
		_source_definitions[spec["id"]] = spec.duplicate(true)

func initialize_sources(seed: int) -> bool:
	if _initialized:
		return true
	if not content_error.is_empty():
		return false
	var index: int = 0
	for spec: Dictionary in _source_definitions.values():
		for n: int in int(spec["count"]):
			var x: int = 4 + (index % 6) * 3
			var z: int = 4 + (index / 6) * 3
			var y: int = LfeWave1TerrainRules.height_at(seed, x, z) + 1
			_sources.append({"instance": (str(seed) + ":" + spec["id"] + ":" + str(n)).sha256_text().substr(0,32),
				"source": spec["id"], "position":[x+0.5,y+0.4,z+0.5], "remaining":int(spec["quantity"])})
			index += 1
	_initialized = true
	return true

func source_definition(id: String) -> Dictionary:
	return (_source_definitions.get(id,{}) as Dictionary).duplicate(true)

func sources() -> Array:
	return _sources.duplicate(true)

func source(id: String) -> Dictionary:
	for entry: Dictionary in _sources:
		if entry["instance"] == id:
			return entry.duplicate(true)
	return {}

func harvest_source(id: String, resources: LfeResourceState) -> bool:
	for entry: Dictionary in _sources:
		if entry["instance"] != id or int(entry["remaining"]) <= 0:
			continue
		var spec: Dictionary = source_definition(entry["source"])
		var effect: Dictionary = LfeHarvestRules.evaluate(spec, LfeHarvestRules.tool(resources), _catalog)
		if effect.is_empty() or float(survival.snapshot()["stamina"]) < 4 or not survival.alive():
			return false
		if LfeItemTransactions.add(resources.inventory, StringName(spec["content"]), int(entry["remaining"])) != int(entry["remaining"]):
			return false
		entry["remaining"] = 0
		survival.exert(4)
		if effect["wear"]:
			LfeHarvestRules.wear(resources, effect["instance"])
		return true
	return false

func objects() -> Array:
	var values: Array = []
	for entry: Dictionary in _objects.values():
		values.append(_object_snapshot(entry))
	values.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a["instance"] < b["instance"])
	return values

func object_at(cell: Vector3i) -> String:
	for id: String in _objects:
		if _objects[id]["cell"] == [cell.x,cell.y,cell.z]:
			return id
	return ""

func add_object(content: StringName, cell: Vector3i, orientation: int) -> bool:
	var function: String = _catalog.content_definition(content).get("function", "")
	if function.is_empty():
		return true
	if not object_at(cell).is_empty() or _objects.size() >= 10000 or orientation < 0 or orientation > 3:
		return false
	var id: String = Crypto.new().generate_random_bytes(16).hex_encode()
	_objects[id] = {"instance":id,"content":String(content),"cell":[cell.x,cell.y,cell.z],"orientation":orientation}
	if function == "kiln":
		_objects[id]["station"] = LfeWorkstation.new(_catalog,recipes)
	if function == "storage":
		_objects[id]["inventory"] = LfeInventory.new(_catalog,9)
	return true

func can_remove(cell: Vector3i) -> bool:
	var id: String = object_at(cell)
	if id.is_empty():
		return true
	var entry: Dictionary = _objects[id]
	if entry.has("station") and not entry["station"].empty():
		return false
	return not entry.has("inventory") or entry["inventory"].snapshot().all(func(v: Variant) -> bool: return v == null)

func remove_object(cell: Vector3i) -> bool:
	if not can_remove(cell):
		return false
	_objects.erase(object_at(cell))
	return true

func station(id: String) -> LfeWorkstation:
	return _objects.get(id,{}).get("station")

func storage(id: String) -> LfeInventory:
	return _objects.get(id,{}).get("inventory")

func advance(seconds: float, sheltered: bool, resting: bool, sprinting: bool) -> bool:
	if not LfeWorldSave._finite_in_range(seconds,60) or seconds < 0:
		return false
	_elapsed += seconds
	survival.advance(seconds,sheltered,resting,sprinting)
	for entry: Dictionary in _objects.values():
		if entry.has("station"):
			entry["station"].advance(seconds)
	return true

func snapshot() -> Dictionary:
	return {"survival":survival.snapshot(),"objects":objects(),"sources":sources(),"initialized":_initialized,"elapsed":_elapsed}

func restore(data: Variant, resources: Dictionary = {}) -> bool:
	if not content_error.is_empty() or not recipes.error.is_empty():
		return false
	if not data is Dictionary or data.size() != 5 or not data.get("initialized") is bool or not data.get("objects") is Array or not data.get("sources") is Array or data["objects"].size() > 10000 or data["sources"].size() > 1000 or not LfeWorldSave._finite_in_range(data.get("elapsed"),1000000000) or float(data["elapsed"]) < 0:
		return false
	var character: LfeCharacterSurvival = LfeCharacterSurvival.new()
	if not character.restore(data.get("survival")):
		return false
	var next: Dictionary = {}
	var seen: Dictionary = {}
	var cells: Dictionary = {}
	var slots: Array = []
	if not resources.is_empty():
		slots.append_array(resources["inventory"] + resources["equipment"])
		for entry: Dictionary in resources["drops"]:
			seen[entry["instance"]] = true
			slots.append(entry["stack"])
		for entry: Dictionary in resources["storage"]:
			seen[entry["instance"]] = true
			slots.append_array(entry["slots"])
	for entry: Variant in data["objects"]:
		if not entry is Dictionary or not LfeResourceState._valid_identity(entry.get("instance")) or seen.has(entry["instance"]) or not entry.get("content") is String or not entry.get("cell") is Array or entry["cell"].size() != 3 or not LfeWorldSave._is_integer(entry.get("orientation")) or int(entry["orientation"]) < 0 or int(entry["orientation"]) > 3:
			return false
		for coordinate: Variant in entry["cell"]:
			if not LfeWorldSave._is_integer(coordinate) or absf(float(coordinate)) > 1000000:
				return false
		if cells.has(str(entry["cell"])):
			return false
		cells[str(entry["cell"])] = true
		var function: String = _catalog.content_definition(StringName(entry["content"])).get("function", "")
		if function not in ["kiln", "rest", "storage", "light"] or entry.size() != (5 if function in ["kiln","storage"] else 4):
			return false
		var object: Dictionary = entry.duplicate(true)
		object["cell"] = [int(entry["cell"][0]),int(entry["cell"][1]),int(entry["cell"][2])]
		object["orientation"] = int(entry["orientation"])
		if function == "kiln":
			var process: LfeWorkstation = LfeWorkstation.new(_catalog,recipes)
			if not process.restore(entry.get("station")):
				return false
			object["station"] = process
			slots.append_array(process.input.snapshot() + process.fuel.snapshot() + process.output.snapshot())
		if function == "storage":
			var inventory: LfeInventory = LfeInventory.new(_catalog,9)
			if not inventory.restore(entry.get("slots")):
				return false
			object.erase("slots")
			object["inventory"] = inventory
			slots.append_array(inventory.snapshot())
		seen[entry["instance"]] = true
		next[entry["instance"]] = object
	for entry: Variant in data["sources"]:
		if not entry is Dictionary or entry.size() != 4 or not LfeResourceState._valid_identity(entry.get("instance")) or seen.has(entry["instance"]) or not LfeResourceState._valid_position(entry.get("position")) or not entry.get("source") is String or not LfeWorldSave._is_integer(entry.get("remaining")):
			return false
		var spec: Dictionary = source_definition(entry["source"])
		if spec.is_empty() or int(entry["remaining"]) < 0 or int(entry["remaining"]) > int(spec["quantity"]):
			return false
		seen[entry["instance"]] = true
	if not LfeResourceState.unique_instances(slots,seen):
		return false
	if not data["initialized"] and not data["sources"].is_empty():
		return false
	survival = character
	_objects = next
	_sources = data["sources"].duplicate(true)
	for entry: Dictionary in _sources:
		entry["remaining"] = int(entry["remaining"])
	_initialized = data["initialized"]
	_elapsed = float(data["elapsed"])
	return true

func _object_snapshot(entry: Dictionary) -> Dictionary:
	var result: Dictionary = {"instance":entry["instance"],"content":entry["content"],"cell":entry["cell"].duplicate(),"orientation":entry["orientation"]}
	if entry.has("station"):
		result["station"] = entry["station"].snapshot()
	if entry.has("inventory"):
		result["slots"] = entry["inventory"].snapshot()
	return result


func validate_source_layout(seed: int) -> bool:
	if not _initialized:
		return _sources.is_empty()
	var expected: LfeCreationState = LfeCreationState.new(_catalog)
	if not expected.initialize_sources(seed) or expected._sources.size() != _sources.size():
		return false
	for index: int in _sources.size():
		var entry: Dictionary = _sources[index].duplicate(true)
		entry["remaining"] = expected._sources[index]["remaining"]
		if entry != expected._sources[index]:
			return false
	return true


func _valid_source_definition(spec: Variant) -> bool:
	if not spec is Dictionary or not spec.get("id") is String or _source_definitions.has(spec["id"]) or not spec.get("display_name") is String or not spec.get("color") is String or not spec.get("content") is String:
		return false
	if not _catalog.is_inventory_content(StringName(spec["content"])) or LfeItemInstance.is_stateful(StringName(spec["content"]),_catalog):
		return false
	if not LfeWorldSave._is_integer(spec.get("quantity")) or int(spec["quantity"]) < 1 or int(spec["quantity"]) > _catalog.stack_limit(StringName(spec["content"])):
		return false
	if not LfeWorldSave._is_integer(spec.get("count")) or int(spec["count"]) < 1 or int(spec["count"]) > 100:
		return false
	return spec.get("class") in ["manual","mining","digging","woodcutting"] and LfeWorldSave._is_integer(spec.get("capability")) and int(spec["capability"]) >= 0 and int(spec["capability"]) <= 16 and LfeWorldSave._finite_in_range(spec.get("seconds"),60) and float(spec["seconds"]) > 0
