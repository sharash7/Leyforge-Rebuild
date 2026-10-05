class_name LfeCompatibilityManifest
extends RefCounted

const PROTOCOL: int = 2
const MAX_BYTES: int = 4096
const HELLO_KEYS: Array = ["network_protocol_version", "build_version", "player_id", "save_version", "content_version", "content_hash", "worldgen_versions"]
const WORLD_KEYS: Array = ["world_id", "seed", "worldgen_version", "save_version", "content_version", "content_hash", "network_protocol_version"]
const REASONS: Array = ["ok", "malformed_handshake", "invalid_identity", "protocol_mismatch", "build_mismatch", "save_schema_mismatch", "content_version_mismatch", "content_hash_mismatch", "worldgen_unsupported", "duplicate_identity", "server_full", "auth_timeout", "connection_failed", "server_disconnected"]

static func hello(player_id: String, fingerprint: String) -> Dictionary:
	return {"network_protocol_version":PROTOCOL, "build_version":ProjectSettings.get_setting("application/config/version"), "player_id":player_id, "save_version":LfeWorldSave.SAVE_VERSION, "content_version":LfeWorldSave.CONTENT_VERSION, "content_hash":fingerprint, "worldgen_versions":[1,2]}

static func world(save: LfeWorldSave, fingerprint: String) -> Dictionary:
	return {"world_id":save.world_id, "seed":save.seed, "worldgen_version":save.worldgen_version, "save_version":LfeWorldSave.SAVE_VERSION, "content_version":LfeWorldSave.CONTENT_VERSION, "content_hash":fingerprint, "network_protocol_version":PROTOCOL}

static func decode(bytes: PackedByteArray) -> Variant:
	if bytes.is_empty() or bytes.size() > MAX_BYTES: return null
	var source: String = bytes.get_string_from_utf8()
	if source.to_utf8_buffer() != bytes: return null
	var parser: JSON = JSON.new()
	if parser.parse(source) != OK: return null
	return parser.data

static func exact_keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size(): return false
	for key: Variant in value:
		if key not in keys: return false
	return true

static func positive_integer(value: Variant) -> bool:
	return LfeWorldSave._is_integer(value) and float(value) >= 1 and float(value) <= 65535

static func valid_hash(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for c: String in value:
		if not c in "0123456789abcdef": return false
	return true

static func validate_hello(value: Variant, expected: Dictionary, hosted: Dictionary) -> String:
	if not exact_keys(value, HELLO_KEYS): return "malformed_handshake"
	if not LfeWorldResourceState._valid_identity(value["player_id"]): return "invalid_identity"
	if not value["build_version"] is String or value["build_version"].is_empty() or value["build_version"].length() > 64: return "malformed_handshake"
	for key: String in ["network_protocol_version", "save_version", "content_version"]:
		if not positive_integer(value[key]): return "malformed_handshake"
	if not valid_hash(value["content_hash"]): return "malformed_handshake"
	if not value["worldgen_versions"] is Array or value["worldgen_versions"].is_empty() or value["worldgen_versions"].size() > 8: return "malformed_handshake"
	var seen: Array = []
	for version: Variant in value["worldgen_versions"]:
		if not positive_integer(version) or int(version) in seen: return "malformed_handshake"
		seen.append(int(version))
	for pair: Array in [["network_protocol_version","protocol_mismatch"], ["build_version","build_mismatch"], ["save_version","save_schema_mismatch"], ["content_version","content_version_mismatch"], ["content_hash","content_hash_mismatch"]]:
		if value[pair[0]] != expected[pair[0]]: return pair[1]
	if hosted["save_version"] != value["save_version"]: return "save_schema_mismatch"
	if hosted["content_version"] != value["content_version"]: return "content_version_mismatch"
	if int(hosted["worldgen_version"]) not in seen: return "worldgen_unsupported"
	return "ok"

static func valid_world(value: Variant, local: Dictionary) -> bool:
	if not exact_keys(value, WORLD_KEYS) or not LfeWorldSave._valid_world_id(value["world_id"]): return false
	if not LfeWorldSave._is_integer(value["seed"]) or float(value["seed"]) < 0 or float(value["seed"]) > 2147483647: return false
	for key: String in ["network_protocol_version", "save_version", "content_version"]:
		if not positive_integer(value[key]) or value[key] != local[key]: return false
	return positive_integer(value["worldgen_version"]) and int(value["worldgen_version"]) in local["worldgen_versions"] and value["content_hash"] == local["content_hash"]

# Length-framed UTF-8 relative paths + raw bytes; excludes only .gitkeep.
# One implementation serves runtime and determinism fixtures.
static func fingerprint(root: String = "res://content", enumeration: Array[String] = []) -> String:
	var paths: Array[String] = enumeration.duplicate()
	if paths.is_empty() and not _collect(root, "", paths): return ""
	paths.sort()
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	for path: String in paths:
		if path.get_file() == ".gitkeep": continue
		var file: FileAccess = FileAccess.open(root.path_join(path), FileAccess.READ)
		if file == null: return ""
		var name: PackedByteArray = path.to_utf8_buffer()
		var frame: PackedByteArray = PackedByteArray()
		frame.resize(16)
		frame.encode_u64(0, name.size())
		frame.encode_u64(8, file.get_length())
		hash.update(frame)
		hash.update(name)
		while file.get_position() < file.get_length():
			hash.update(file.get_buffer(mini(65536, file.get_length() - file.get_position())))
		if file.get_error() not in [OK, ERR_FILE_EOF]: return ""
	return hash.finish().hex_encode()

static func _collect(root: String, relative: String, paths: Array[String]) -> bool:
	var dir: DirAccess = DirAccess.open(root.path_join(relative))
	if dir == null: return false
	dir.include_hidden = true
	for name: String in dir.get_files():
		paths.append(relative.path_join(name) if not relative.is_empty() else name)
	for name: String in dir.get_directories():
		if not _collect(root, relative.path_join(name) if not relative.is_empty() else name, paths): return false
	return true
