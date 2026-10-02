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
var _placeable_ids: Array[StringName] = []
var _last_error: String = ""


func load_default() -> Error:
	return load_from_path(DEFAULT_CATALOG_PATH)


func load_from_path(path: String) -> Error:
	_definitions_by_id.clear()
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
	if int(root.get("schema_version", 0)) != 1:
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
		var voxel_id: int = int(definition.get("voxel_id", -1))
		if canonical_id == &"":
			return _fail(ERR_INVALID_DATA, "Block entry %d has no canonical ID." % index)
		if voxel_id < 0:
			return _fail(ERR_INVALID_DATA, "Block %s has an invalid voxel ID." % canonical_id)
		if _definitions_by_id.has(canonical_id):
			return _fail(ERR_INVALID_DATA, "Duplicate canonical block ID: %s." % canonical_id)
		if _definitions_by_voxel_id.has(voxel_id):
			return _fail(ERR_INVALID_DATA, "Duplicate voxel ID: %d." % voxel_id)

		definition["id"] = String(canonical_id)
		definition["voxel_id"] = voxel_id
		_definitions_by_id[canonical_id] = definition
		_definitions_by_voxel_id[voxel_id] = definition
		if bool(definition.get("development_placeable", false)):
			_placeable_ids.append(canonical_id)

	if blocks.size() != REQUIRED_CANONICAL_IDS.size():
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
	_last_error = message
	return error
