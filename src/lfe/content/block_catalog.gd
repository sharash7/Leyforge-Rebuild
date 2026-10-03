class_name LfeBlockCatalog
extends RefCounted

const DEFAULT_CATALOG_PATH: String = "res://content/blocks/wave_1_blocks.json"
const REQUIRED_CANONICAL_IDS: Array[StringName] = [
	&"leyforge:air",
	&"leyforge:grass",
	&"leyforge:dirt",
	&"leyforge:stone",
	&"leyforge:sand",
]

var _definitions_by_id: Dictionary = {}
var _definitions_by_voxel_id: Dictionary = {}
var _items_by_id: Dictionary = {}
var _placeable_ids: Array[StringName] = []
var _last_error: String = ""


func load_default() -> Error:
	return load_from_path(DEFAULT_CATALOG_PATH)


func load_from_path(path: String) -> Error:
	_definitions_by_id.clear()
	_items_by_id.clear()
	_definitions_by_voxel_id.clear()
	_placeable_ids.clear()
	_last_error = ""

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail(
			ERR_FILE_CANT_OPEN,
			"Could not open block catalog %s (error %s)." % [path, FileAccess.get_open_error()]
		)

	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		return _fail(
			ERR_PARSE_ERROR,
			"Invalid JSON in %s at line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()]
		)

	var root_value: Variant = parser.data
	if not root_value is Dictionary:
		return _fail(ERR_INVALID_DATA, "Block catalog root must be an object.")

	var root: Dictionary = root_value as Dictionary
	if not LfeWorldSave._is_integer(root.get("schema_version")) or int(root["schema_version"]) != 1:
		return _fail(ERR_INVALID_DATA, "Unsupported block catalog schema version.")

	var blocks_value: Variant = root.get("blocks", [])
	if not blocks_value is Array:
		return _fail(ERR_INVALID_DATA, "Block catalog 'blocks' must be an array.")

	var blocks: Array = blocks_value as Array
	for index: int in blocks.size():
		var definition_value: Variant = blocks[index]
		if not definition_value is Dictionary:
			return _fail(ERR_INVALID_DATA, "Block entry %d must be an object." % index)

		var definition: Dictionary = (definition_value as Dictionary).duplicate(true)
		var canonical_id: StringName = StringName(String(definition.get("id", "")).strip_edges())
		if not LfeWorldSave._is_integer(definition.get("voxel_id")):
			return _fail(ERR_INVALID_DATA, "Block voxel ID must be an integer.")
		var voxel_id: int = int(definition["voxel_id"])
		if canonical_id == &"":
			return _fail(ERR_INVALID_DATA, "Block entry %d has no canonical ID." % index)
		if voxel_id < 0:
			return _fail(ERR_INVALID_DATA, "Block %s has an invalid voxel ID." % canonical_id)
		if _definitions_by_id.has(canonical_id):
			return _fail(ERR_INVALID_DATA, "Duplicate canonical block ID: %s." % canonical_id)
		if _definitions_by_voxel_id.has(voxel_id):
			return _fail(ERR_INVALID_DATA, "Duplicate voxel ID: %d." % voxel_id)

		if not _valid_inventory_definition(definition, true):
			return _fail(ERR_INVALID_DATA, "Invalid inventory projection for %s." % canonical_id)
		definition["id"] = String(canonical_id)
		definition["voxel_id"] = voxel_id
		_definitions_by_id[canonical_id] = definition
		_definitions_by_voxel_id[voxel_id] = definition
		if bool(definition.get("development_placeable", false)):
			_placeable_ids.append(canonical_id)

	if blocks.size() < REQUIRED_CANONICAL_IDS.size():
		return _fail(
			ERR_INVALID_DATA,
			"Wave 1 catalog must contain exactly %d blocks." % REQUIRED_CANONICAL_IDS.size()
		)

	for required_id: StringName in REQUIRED_CANONICAL_IDS:
		if not _definitions_by_id.has(required_id):
			return _fail(ERR_INVALID_DATA, "Required block is missing: %s." % required_id)

	for expected_voxel_id: int in _definitions_by_voxel_id.size():
		if not _definitions_by_voxel_id.has(expected_voxel_id):
			return _fail(
				ERR_INVALID_DATA,
				"Voxel IDs must be contiguous from zero; missing %d." % expected_voxel_id
			)

	if get_voxel_id(&"leyforge:air") != 0:
		return _fail(ERR_INVALID_DATA, "Air must remain voxel ID 0 for Voxel Tools.")

	var items: Variant = root.get("items", [])
	if not items is Array:
		return _fail(ERR_INVALID_DATA, "Items must be an array.")
	for value: Variant in items:
		if not value is Dictionary or not _valid_inventory_definition(value, false):
			return _fail(ERR_INVALID_DATA, "Invalid standalone item definition.")
		var item: Dictionary = value.duplicate(true)
		var id: StringName = StringName(item["id"])
		if has_content(id):
			return _fail(ERR_INVALID_DATA, "Duplicate canonical content ID: %s." % id)
		_items_by_id[id] = item
	for definition: Dictionary in _definitions_by_id.values():
		var drop: StringName = StringName(definition.get("drop_content", ""))
		if drop != &"" and not is_inventory_content(drop):
			return _fail(ERR_INVALID_DATA, "Unknown block drop content: %s." % drop)
	for definition: Dictionary in _definitions_by_id.values():
		if not definition.get("breakable",false):
			continue
		var rule: Variant = definition.get("harvest")
		if not rule is Dictionary or not rule.get("class") is String or rule["class"] not in ["manual","mining","digging","woodcutting"] or not LfeWorldSave._is_integer(rule.get("capability")) or int(rule["capability"]) < 0 or not LfeWorldSave._finite_in_range(rule.get("seconds"),60) or float(rule["seconds"]) <= 0 or not rule.get("outputs") is Array:
			return _fail(ERR_INVALID_DATA,"Invalid harvest rule")
		for entry: Variant in rule["outputs"]:
			if not LfeItemStack.valid(entry,self,false) or entry.has("instance"):
				return _fail(ERR_INVALID_DATA,"Invalid harvest output")
	return OK


func get_last_error() -> String:
	return _last_error


func block_count() -> int:
	return _definitions_by_id.size()


func has_id(canonical_id: StringName) -> bool:
	return _definitions_by_id.has(canonical_id)


func get_voxel_id(canonical_id: StringName) -> int:
	var definition: Dictionary = definition_for_id(canonical_id)
	return int(definition.get("voxel_id", -1))


func definition_for_id(canonical_id: StringName) -> Dictionary:
	if not _definitions_by_id.has(canonical_id):
		return {}
	return (_definitions_by_id[canonical_id] as Dictionary).duplicate(true)


func definition_for_voxel_id(voxel_id: int) -> Dictionary:
	if not _definitions_by_voxel_id.has(voxel_id):
		return {}
	return (_definitions_by_voxel_id[voxel_id] as Dictionary).duplicate(true)


func canonical_id_for_voxel_id(voxel_id: int) -> StringName:
	var definition: Dictionary = definition_for_voxel_id(voxel_id)
	return StringName(String(definition.get("id", "")))


func display_name_for_voxel_id(voxel_id: int) -> String:
	var definition: Dictionary = definition_for_voxel_id(voxel_id)
	return String(definition.get("display_name", "Unknown"))


func color_for_voxel_id(voxel_id: int) -> Color:
	var definition: Dictionary = definition_for_voxel_id(voxel_id)
	return Color.from_string(String(definition.get("color", "#FF00FFFF")), Color.MAGENTA)


func is_solid_voxel(voxel_id: int) -> bool:
	var definition: Dictionary = definition_for_voxel_id(voxel_id)
	return bool(definition.get("solid", false))


func is_breakable_voxel(voxel_id: int) -> bool:
	var definition: Dictionary = definition_for_voxel_id(voxel_id)
	return bool(definition.get("breakable", false))


func development_placeable_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for canonical_id: StringName in _placeable_ids:
		result.append(canonical_id)
	return result


func _fail(error: Error, message: String) -> Error:
	_definitions_by_id.clear()
	_definitions_by_voxel_id.clear()
	_items_by_id.clear()
	_placeable_ids.clear()
	_last_error = message
	return error


# Inventory projections resolve the existing block definition; they never copy it
# into a second item registry. Item-only definitions share this catalog and ID space.
func has_content(id: StringName) -> bool:
	return has_id(id) or _items_by_id.has(id)


func content_definition(id: StringName) -> Dictionary:
	if has_id(id):
		return definition_for_id(id)
	return (_items_by_id.get(id, {}) as Dictionary).duplicate(true)


func is_inventory_content(id: StringName) -> bool:
	return bool(content_definition(id).get("inventory_capable", false))


func stack_limit(id: StringName) -> int:
	return int(content_definition(id).get("stack_limit", 0))


func placeable_voxel(id: StringName) -> int:
	if not bool(content_definition(id).get("placeable", false)):
		return -1
	return get_voxel_id(id)


func equipment_accepts(id: StringName, slot: String) -> bool:
	return slot in content_definition(id).get("equipment_slots", [])


func _valid_inventory_definition(d: Dictionary, block: bool) -> bool:
	if not d.get("id") is String or String(d["id"]).is_empty() or not String(d["id"]).contains(":"):
		return false
	if not d.get("display_name") is String or String(d["display_name"]).is_empty():
		return false
	if d.get("kind") != ("block" if block else "item"):
		return false
	if not d.get("inventory_capable") is bool or not d.get("placeable") is bool:
		return false
	if not LfeWorldSave._is_integer(d.get("stack_limit")):
		return false
	var limit: int = int(d["stack_limit"])
	if bool(d["inventory_capable"]):
		if limit < 1 or limit > 999:
			return false
	elif limit != 0 or bool(d["placeable"]):
		return false
	if not block and (bool(d["placeable"]) or not bool(d["inventory_capable"])):
		return false
	if not d.get("equipment_slots") is Array:
		return false
	var seen: Array = []
	for slot: Variant in d["equipment_slots"]:
		if not slot is String or slot not in ["hand", "body"] or slot in seen:
			return false
		seen.append(slot)
	if block and not d.get("drop_content") is String:
		return false
	if d.has("tool"):
		var t: Variant = d["tool"]
		if block or limit != 1 or not t is Dictionary or t.size() != 4:
			return false
		if t.get("class") not in ["mining", "woodcutting", "digging"] or not LfeWorldSave._is_integer(t.get("capability")) or int(t["capability"]) < 1:
			return false
		if not LfeWorldSave._is_integer(t.get("durability")) or int(t["durability"]) < 1 or not LfeWorldSave._finite_in_range(t.get("efficiency"), 10) or float(t["efficiency"]) < 1:
			return false
	if d.has("consume"):
		if not d["consume"] is Dictionary or d["consume"].is_empty():
			return false
		for key: Variant in d["consume"]:
			if key not in ["health", "hunger", "thirst"] or not LfeWorldSave._finite_in_range(d["consume"][key], 100) or float(d["consume"][key]) <= 0:
				return false
	return true
