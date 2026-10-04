class_name LfeLocalProfile
extends RefCounted

const PROFILE_VERSION: int = 1
const PROFILE_PATH: String = "user://identity/local_profile.json"
const LEGACY_PROFILE_PATH: String = "user://profile.json"
const MAX_BYTES: int = 1024
var player_id: String = ""
var error: String = ""

# Explicit paths support disposable fixtures. Only the default canonical path
# implicitly inspects historical userdata; it never claims or modifies it.
func open_profile(profile_path: String = PROFILE_PATH, legacy_path: String = "") -> Error:
	player_id = ""
	error = ""
	var absolute: String = ProjectSettings.globalize_path(profile_path)
	var pending: String = absolute + ".pending"
	if FileAccess.file_exists(absolute) or DirAccess.dir_exists_absolute(absolute):
		return _read(absolute)
	# Pending canonical creation takes precedence over legacy migration.
	if FileAccess.file_exists(pending) or DirAccess.dir_exists_absolute(pending):
		if _read(pending) != OK:
			return ERR_INVALID_DATA
		if FileAccess.file_exists(absolute) or DirAccess.rename_absolute(pending, absolute) != OK:
			error = "Could not recover local identity; identity retained in pending file."
			player_id = ""
			return ERR_FILE_CANT_WRITE
		return _read(absolute)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		error = "Could not create local identity directory."
		return ERR_FILE_CANT_WRITE

	if legacy_path.is_empty() and profile_path == PROFILE_PATH:
		legacy_path = LEGACY_PROFILE_PATH
	var chosen: String = ""
	if not legacy_path.is_empty():
		# A settings profile, including oversized/unreadable historical data,
		# is unrelated. An exact early-W5.1 schema preserves its player ID.
		chosen = _identity_at(ProjectSettings.globalize_path(legacy_path))
	if chosen.is_empty():
		chosen = Crypto.new().generate_random_bytes(16).hex_encode()
	if not LfeWorldResourceState._valid_identity(chosen):
		error = "Could not generate local player identity."
		return ERR_CANT_CREATE
	var file: FileAccess = FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		error = "Could not write local identity."
		return ERR_FILE_CANT_WRITE
	file.store_string(JSON.stringify({"profile_version":PROFILE_VERSION, "player_id":chosen}, "\t") + "\n")
	file.flush()
	var result: Error = file.get_error()
	file = null
	if result != OK:
		error = "Local identity pending write failed; pending data was retained."
		return ERR_FILE_CANT_WRITE
	if _read(pending) != OK or player_id != chosen:
		error = "Local identity pending verification failed; pending data was retained."
		player_id = ""
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(absolute) or DirAccess.rename_absolute(pending, absolute) != OK:
		player_id = ""
		error = "Local identity changed during creation; refusing replacement."
		return ERR_FILE_CANT_WRITE
	return _read(absolute)

func _identity_at(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return ""
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return ""
	var data: Variant = parser.data
	if not data is Dictionary or data.size() != 2:
		return ""
	if not LfeWorldSave._is_integer(data.get("profile_version")) or int(data["profile_version"]) != PROFILE_VERSION or not LfeWorldResourceState._valid_identity(data.get("player_id")):
		return ""
	return data["player_id"]

func _read(path: String) -> Error:
	var identity: String = _identity_at(path)
	if identity.is_empty():
		error = "Canonical local identity is unreadable, oversized or malformed; restore it from backup. Identity was not regenerated."
		player_id = ""
		return ERR_INVALID_DATA
	player_id = identity
	return OK
