class_name LfeWorldSave
extends RefCounted

const SAVE_VERSION: int = 3
const WORLDGEN_VERSION: int = 2
const CONTENT_VERSION: int = 1
const SAVE_FILE: String = "world.json"
const PREVIOUS_FILE: String = "world.json.previous"
const PENDING_FILE: String = "world.json.pending"

var world_id: String = ""
var display_name: String = ""
var seed: int = 0
var worldgen_version: int = WORLDGEN_VERSION
var created_utc: String = ""
var last_saved_utc: String = ""
var player_state: Dictionary = {}
var resource_state: Dictionary = {}
var creation_state: Dictionary = {}
var overrides: LfeVoxelOverrideStore = LfeVoxelOverrideStore.new()
var load_status: String = ""
var save_status: String = "Never saved"

var _catalog: LfeBlockCatalog
var _world_directory: String = ""
var _expected_primary_hash: String = ""
var _edits_dirty: bool = false
var _is_open: bool = false
var _last_error: String = ""


func get_last_error() -> String:
	return _last_error


func get_world_directory() -> String:
	return _world_directory


func get_primary_path() -> String:
	return _world_directory.path_join(SAVE_FILE)


func is_dirty(current_player_state: Dictionary, current_resources: Dictionary = {}, current_creation: Dictionary = {}) -> bool:
	return _edits_dirty or player_state != current_player_state or (not current_resources.is_empty() and resource_state != current_resources) or (not current_creation.is_empty() and creation_state != current_creation) or last_saved_utc.is_empty()


func record_voxel_edit(cell: Vector3i, voxel_id: int, base_voxel_id: int) -> Error:
	if not _is_open:
		return _fail(ERR_UNCONFIGURED, "World save is not open.")
	var result: Error = overrides.record_edit(cell, voxel_id, base_voxel_id, _catalog)
	if result != OK:
		_last_error = overrides.get_last_error()
		return result
	_edits_dirty = true
	return OK


func open_world(
	selected_id: String,
	requested_seed: int,
	seed_was_explicit: bool,
	catalog: LfeBlockCatalog,
	root_path: String = "user://worlds"
) -> Error:
	_is_open = false
	worldgen_version = WORLDGEN_VERSION
	_last_error = ""
	if not _valid_world_id(selected_id):
		return _fail(ERR_INVALID_PARAMETER, "World ID must be 1-64 ASCII letters, digits, underscores or hyphens.")
	_catalog = catalog
	world_id = selected_id
	var absolute_root: String = ProjectSettings.globalize_path(root_path) if root_path.begins_with("user://") else root_path
	_world_directory = absolute_root.path_join(world_id)
	var primary: String = get_primary_path()
	var previous: String = _world_directory.path_join(PREVIOUS_FILE)
	var path_to_load: String = ""
	if FileAccess.file_exists(primary):
		path_to_load = primary
	elif FileAccess.file_exists(previous):
		path_to_load = previous
	if path_to_load.is_empty():
		seed = LfeDeterministicSeed.normalize(requested_seed)
		display_name = world_id
		created_utc = Time.get_datetime_string_from_system(true)
		last_saved_utc = ""
		player_state = {}
		resource_state = LfeResourceState.new(_catalog).snapshot()
		creation_state = LfeCreationState.new(_catalog).snapshot()
		overrides = LfeVoxelOverrideStore.new()
		load_status = "New world; not yet saved"
		save_status = "Never saved"
		_expected_primary_hash = ""
		_edits_dirty = false
		_is_open = true
		_last_error = ""
		return OK

	var decoded: Dictionary = _decode_file(path_to_load)
	if decoded.is_empty():
		return ERR_INVALID_DATA
	var metadata: Dictionary = decoded["metadata"]
	if String(metadata["world_id"]) != world_id:
		return _fail(ERR_INVALID_DATA, "Save world ID does not match selected world ID.")
	var stored_seed: int = int(metadata["seed"])
	if seed_was_explicit and LfeDeterministicSeed.normalize(requested_seed) != stored_seed:
		return _fail(ERR_INVALID_DATA, "Explicit seed conflicts with saved world seed %d." % stored_seed)
	seed = stored_seed
	worldgen_version = int(metadata["worldgen_version"])
	display_name = String(metadata["display_name"])
	created_utc = String(metadata["created_utc"])
	last_saved_utc = String(metadata["last_saved_utc"])
	player_state = decoded["player"]
	resource_state = decoded["resources"]
	creation_state = decoded["creation"]
	overrides = decoded["overrides"]
	_expected_primary_hash = String(decoded["file_hash"]) if path_to_load == primary else ""
	_edits_dirty = false
	load_status = "Loaded world" if path_to_load == primary else "Recovered previous save; primary was missing"
	if int(metadata["save_version"]) < SAVE_VERSION:
		load_status += "; migrated v%d in memory; next save writes v%d" % [int(metadata["save_version"]), SAVE_VERSION]
	save_status = "Saved %s" % last_saved_utc
	_is_open = true
	_last_error = ""
	return OK


func save(current_player_state: Dictionary, current_resources: Variant = null, current_creation: Variant = null) -> Error:
	if not _is_open or _catalog == null or _world_directory.is_empty():
		return _fail(ERR_UNCONFIGURED, "World save is not open.")
	if not _valid_player_state(current_player_state):
		return ERR_INVALID_DATA
	var resources_to_save: Variant = resource_state if current_resources == null else current_resources
	var resource_validator: LfeResourceState = LfeResourceState.new(_catalog)
	if not resource_validator.restore(resources_to_save):
		return _fail(ERR_INVALID_DATA, "Invalid Wave 3 resources; refusing save.")
	var creation_validator: LfeCreationState = LfeCreationState.new(_catalog)
	if not creation_validator.restore(creation_state if current_creation == null else current_creation, resource_validator.snapshot()):
		return _fail(ERR_INVALID_DATA, "Invalid survival/creation state; refusing save.")
	if not creation_validator.initialize_sources(seed,worldgen_version) or not creation_validator.validate_source_layout(seed,worldgen_version) or not _valid_object_voxels(creation_validator.snapshot(), overrides):
		return _fail(ERR_INVALID_DATA, "Functional object does not match its authoritative voxel.")
	var proposed_saved_utc: String = Time.get_datetime_string_from_system(true)
	var metadata: Dictionary = {
		"world_id": world_id,
		"display_name": display_name,
		"seed": seed,
		"save_version": SAVE_VERSION,
		"worldgen_version": worldgen_version,
		"content_version": CONTENT_VERSION,
		"created_utc": created_utc,
		"last_saved_utc": proposed_saved_utc,
	}
	var payload: Dictionary = {
		"metadata": metadata,
		"player": current_player_state,
		"voxel_overrides": overrides.serialized_entries(),
		"resources": resource_validator.snapshot(),
		"creation": creation_validator.snapshot(),
	}
	var payload_json: String = JSON.stringify(payload, "", true, true)
	var envelope: Dictionary = {
		"save_version": SAVE_VERSION,
		"payload_json": payload_json,
		"sha256": payload_json.sha256_text(),
	}
	var serialized: String = JSON.stringify(envelope, "\t") + "\n"
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(_world_directory)
	if directory_error != OK:
		return _fail(directory_error, "Could not create world save directory %s." % _world_directory)

	var primary: String = get_primary_path()
	var previous: String = _world_directory.path_join(PREVIOUS_FILE)
	var pending: String = _world_directory.path_join(PENDING_FILE)
	var primary_exists: bool = FileAccess.file_exists(primary)
	if not primary_exists and not _expected_primary_hash.is_empty():
		return _fail(ERR_FILE_CORRUPT, "Authoritative save disappeared since load; refusing to replace it.")
	if primary_exists:
		var current_file: FileAccess = FileAccess.open(primary, FileAccess.READ)
		if current_file == null:
			return _fail(ERR_FILE_CANT_OPEN, "Could not inspect existing authoritative save.")
		var current_hash: String = current_file.get_as_text().sha256_text()
		if current_hash != _expected_primary_hash:
			return _fail(ERR_FILE_CORRUPT, "Authoritative save changed since load; refusing to overwrite it.")

	var pending_file: FileAccess = FileAccess.open(pending, FileAccess.WRITE)
	if pending_file == null:
		return _fail(ERR_FILE_CANT_OPEN, "Could not open temporary world save.")
	pending_file.store_string(serialized)
	pending_file.flush()
	var write_error: Error = pending_file.get_error()
	pending_file = null
	if write_error != OK:
		return _fail(write_error, "Temporary world save write failed.")
	var validated: Dictionary = _decode_file(pending)
	if validated.is_empty():
		return _fail(ERR_FILE_CORRUPT, "Temporary world save did not validate: %s" % _last_error)
	if String((validated["metadata"] as Dictionary)["world_id"]) != world_id:
		return _fail(ERR_INVALID_DATA, "Temporary save world ID changed unexpectedly.")

	if primary_exists:
		if FileAccess.file_exists(previous):
			var remove_error: Error = DirAccess.remove_absolute(previous)
			if remove_error != OK:
				return _fail(remove_error, "Could not retire previous world save.")
		var backup_error: Error = DirAccess.rename_absolute(primary, previous)
		if backup_error != OK:
			return _fail(backup_error, "Could not move authoritative save to previous copy.")
	var promote_error: Error = DirAccess.rename_absolute(pending, primary)
	if promote_error != OK:
		if primary_exists:
			DirAccess.rename_absolute(previous, primary)
		return _fail(promote_error, "Could not promote validated world save; previous copy retained.")
	_expected_primary_hash = serialized.sha256_text()
	player_state = current_player_state.duplicate(true)
	resource_state = resource_validator.snapshot()
	creation_state = creation_validator.snapshot()
	last_saved_utc = proposed_saved_utc
	_edits_dirty = false
	save_status = "Saved %s" % last_saved_utc
	_last_error = ""
	return OK


func _decode_file(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail(ERR_FILE_CANT_OPEN, "Could not open world save %s." % path)
		return {}
	var raw_text: String = file.get_as_text()
	var envelope_parser: JSON = JSON.new()
	if envelope_parser.parse(raw_text) != OK or not envelope_parser.data is Dictionary:
		_fail(ERR_PARSE_ERROR, "Malformed world save envelope at %s." % path)
		return {}
	var envelope: Dictionary = envelope_parser.data
	if not _is_integer(envelope.get("save_version")):
		_fail(ERR_INVALID_DATA, "World save has no valid save version.")
		return {}
	var version: int = int(envelope["save_version"])
	if version not in [1, 2, SAVE_VERSION]:
		_fail(ERR_INVALID_DATA, "Unsupported save version %d; this build supports %d." % [version, SAVE_VERSION])
		return {}
	if not envelope.get("payload_json") is String or not envelope.get("sha256") is String:
		_fail(ERR_INVALID_DATA, "World save payload or checksum is missing.")
		return {}
	var payload_json: String = envelope["payload_json"]
	if payload_json.sha256_text() != String(envelope["sha256"]):
		_fail(ERR_FILE_CORRUPT, "World save checksum mismatch at %s." % path)
		return {}
	var payload_parser: JSON = JSON.new()
	if payload_parser.parse(payload_json) != OK or not payload_parser.data is Dictionary:
		_fail(ERR_PARSE_ERROR, "Malformed world save payload at %s." % path)
		return {}
	var payload: Dictionary = payload_parser.data
	if not payload.get("metadata") is Dictionary or not payload.get("player") is Dictionary:
		_fail(ERR_INVALID_DATA, "World metadata or player state is missing.")
		return {}
	var metadata: Dictionary = payload["metadata"]
	if not _valid_metadata(metadata, version):
		return {}
	var parsed_player: Dictionary = payload["player"]
	if not _valid_player_state(parsed_player):
		return {}
	var parsed_overrides: LfeVoxelOverrideStore = LfeVoxelOverrideStore.new()
	if parsed_overrides.load_entries(payload.get("voxel_overrides"), _catalog) != OK:
		_fail(ERR_INVALID_DATA, parsed_overrides.get_last_error())
		return {}
	var resources: LfeResourceState = LfeResourceState.new(_catalog)
	if version >= 2 and not resources.restore(payload.get("resources")):
		_fail(ERR_INVALID_DATA, "Malformed Wave 3 resources or unknown canonical content.")
		return {}
	var creation: LfeCreationState = LfeCreationState.new(_catalog)
	if version == SAVE_VERSION and not creation.restore(payload.get("creation"), resources.snapshot()):
		_fail(ERR_INVALID_DATA, "Malformed survival, workstation or item-instance state.")
		return {}
	if version == SAVE_VERSION and (not creation.snapshot()["initialized"] or not creation.validate_source_layout(int(metadata["seed"]),int(metadata["worldgen_version"])) or not _valid_object_voxels(creation.snapshot(), parsed_overrides)):
		_fail(ERR_INVALID_DATA, "Functional world object/voxel mismatch.")
		return {}
	return {
		"creation": creation.snapshot(),
		"resources": resources.snapshot(),
		"metadata": metadata,
		"player": parsed_player,
		"overrides": parsed_overrides,
		"file_hash": raw_text.sha256_text(),
	}


func _valid_metadata(metadata: Dictionary, envelope_version: int) -> bool:
	if not metadata.get("world_id") is String or not _valid_world_id(String(metadata["world_id"])):
		_fail(ERR_INVALID_DATA, "Saved world ID is invalid.")
		return false
	if not metadata.get("display_name") is String:
		_fail(ERR_INVALID_DATA, "Saved display name is invalid.")
		return false
	if not _is_integer(metadata.get("seed")) or int(metadata["seed"]) < 0 or int(metadata["seed"]) > 2147483647:
		_fail(ERR_INVALID_DATA, "Saved seed is invalid.")
		return false
	for key: String in ["save_version", "worldgen_version", "content_version"]:
		if not _is_integer(metadata.get(key)):
			_fail(ERR_INVALID_DATA, "Saved %s is missing or invalid." % key)
			return false
	if int(metadata["save_version"]) != envelope_version:
		_fail(ERR_INVALID_DATA, "Metadata save version does not match supported version.")
		return false
	if int(metadata["worldgen_version"]) not in [1,2]:
		_fail(ERR_INVALID_DATA, "Unsupported worldgen version %s." % metadata["worldgen_version"])
		return false
	if int(metadata["content_version"]) != CONTENT_VERSION:
		_fail(ERR_INVALID_DATA, "Unsupported content version %s." % metadata["content_version"])
		return false
	for key: String in ["created_utc", "last_saved_utc"]:
		if not metadata.get(key) is String or String(metadata[key]).is_empty():
			_fail(ERR_INVALID_DATA, "Saved %s is missing." % key)
			return false
	return true


func _valid_player_state(state: Dictionary) -> bool:
	var position_value: Variant = state.get("position")
	if not position_value is Array or (position_value as Array).size() != 3:
		_fail(ERR_INVALID_DATA, "Player position must have three coordinates.")
		return false
	for component: Variant in position_value:
		if not _finite_in_range(component, 1000000.0):
			_fail(ERR_INVALID_DATA, "Player position contains an invalid coordinate.")
			return false
	if not _finite_in_range(state.get("yaw"), 1000000.0):
		_fail(ERR_INVALID_DATA, "Player yaw is invalid.")
		return false
	if not _finite_in_range(state.get("pitch"), 1.553344):
		_fail(ERR_INVALID_DATA, "Player pitch is invalid.")
		return false
	var selected: Variant = state.get("selected_block", "")
	if not selected is String or (not String(selected).is_empty() and not _catalog.has_id(StringName(selected))):
		_fail(ERR_INVALID_DATA, "Player selected block has an unknown canonical ID.")
		return false
	return true


static func _finite_in_range(value: Variant, maximum: float) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	var number: float = float(value)
	return not is_nan(number) and not is_inf(number) and absf(number) <= maximum


static func _is_integer(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return (not is_nan(number) and not is_inf(number) and number == floorf(number)
		and number >= -2147483648.0 and number <= 2147483647.0)


static func _valid_world_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index: int in value.length():
		var character: String = value.substr(index, 1)
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(character):
			return false
	return true


func _fail(error: Error, message: String) -> Error:
	_last_error = message
	save_status = "Error: %s" % message
	return error


func _valid_object_voxels(creation: Dictionary, edits: LfeVoxelOverrideStore) -> bool:
	var functional: int = 0
	for entry: Dictionary in edits.serialized_entries():
		if _catalog.content_definition(StringName(entry["block"])).has("function"):
			functional += 1
	if functional != creation["objects"].size():
		return false
	for entry: Dictionary in creation["objects"]:
		var coordinates: Array = entry["cell"]
		var cell: Vector3i = Vector3i(int(coordinates[0]),int(coordinates[1]),int(coordinates[2]))
		if edits.canonical_id_at(cell) != entry["content"]:
			return false
	return true
