class_name LfeLocalProfile
extends RefCounted

const PROFILE_VERSION: int = 1
const PROFILE_PATH: String = "user://profile.json"
const MAX_BYTES: int = 1024
var player_id: String = ""
var error: String = ""

func open_profile(profile_path: String = PROFILE_PATH) -> Error:
	player_id = "";error = ""
	var absolute: String = ProjectSettings.globalize_path(profile_path)
	var pending: String = absolute + ".pending"
	if FileAccess.file_exists(absolute):return _read(absolute)
	# Interrupted creation retains its identity, including malformed pending data.
	if FileAccess.file_exists(pending):
		if _read(pending) != OK:return ERR_INVALID_DATA
		if DirAccess.rename_absolute(pending,absolute) != OK:
			error = "Could not recover local profile; identity retained in pending file."
			player_id = ""
			return ERR_FILE_CANT_WRITE
		return OK
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		error = "Could not create local profile directory."
		return ERR_FILE_CANT_WRITE
	var generated: String = Crypto.new().generate_random_bytes(16).hex_encode()
	if not LfeWorldResourceState._valid_identity(generated):
		error = "Could not generate local player identity."
		return ERR_CANT_CREATE
	var file: FileAccess = FileAccess.open(pending,FileAccess.WRITE)
	if file == null:
		error = "Could not write local profile."
		return ERR_FILE_CANT_WRITE
	file.store_string(JSON.stringify({"profile_version":PROFILE_VERSION,"player_id":generated},"\t")+"\n")
	file.flush()
	var result: Error = file.get_error()
	file = null
	if result != OK or _read(pending) != OK:return ERR_FILE_CANT_WRITE
	if FileAccess.file_exists(absolute) or DirAccess.rename_absolute(pending,absolute) != OK:
		player_id = ""
		error = "Local profile changed during creation; refusing replacement."
		return ERR_FILE_CANT_WRITE
	return OK

func _read(profile_path: String) -> Error:
	var file: FileAccess = FileAccess.open(profile_path,FileAccess.READ)
	if file == null or file.get_length()>MAX_BYTES:
		error = "Local profile unreadable or oversized; existing identity was preserved."
		return ERR_INVALID_DATA
	var parser: JSON=JSON.new()
	var parsed: Error=parser.parse(file.get_as_text())
	var data: Variant=parser.data if parsed==OK else null
	if not data is Dictionary or data.size()!=2 or not LfeWorldSave._is_integer(data.get("profile_version")) or int(data["profile_version"])!=PROFILE_VERSION or not LfeWorldResourceState._valid_identity(data.get("player_id")):
		error = "Local profile is malformed; restore it from backup. Identity was not regenerated."
		return ERR_INVALID_DATA
	player_id = data["player_id"]
	return OK
