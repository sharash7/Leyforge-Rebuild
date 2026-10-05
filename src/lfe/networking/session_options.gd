class_name LfeSessionOptions
extends RefCounted

const DEFAULT_PORT: int = 25652
const CLIENT_PROFILE: String = "user://identity/development/wave5-client-2.json"
var mode: String = "OFFLINE"
var address: String = "127.0.0.1"
var port: int = DEFAULT_PORT
var profile_path: String = LfeLocalProfile.PROFILE_PATH
var error: String = ""

func parse(arguments: PackedStringArray) -> bool:
	var seen: Dictionary = {}
	for argument: String in arguments:
		var key: String = argument.get_slice("=", 0)
		if key not in ["--session", "--address", "--port", "--profile-path"]: continue
		if seen.has(key) or not argument.contains("="): return _fail("Duplicate or missing session argument: " + key)
		seen[key] = true
		var value: String = argument.substr(key.length() + 1)
		match key:
			"--session": mode = value.to_upper()
			"--address": address = value
			"--port":
				if not value.is_valid_int(): return _fail("Invalid UDP port")
				port = int(value)
			"--profile-path": profile_path = value
	if mode not in ["OFFLINE", "HOST", "JOIN"]: return _fail("Invalid session mode")
	if not valid_address(address) or port < 1 or port > 65535: return _fail("Invalid address or UDP port")
	if mode == "JOIN" and not seen.has("--profile-path"): profile_path = CLIENT_PROFILE
	if not valid_profile_path(profile_path): return _fail("Profile must be a bounded identity JSON path outside the project")
	return true

static func valid_address(value: String) -> bool:
	if value.is_empty() or value.length() > 253: return false
	var regex: RegEx = RegEx.new()
	regex.compile("^[A-Za-z0-9][A-Za-z0-9.:-]*$")
	return regex.search(value) != null

static func valid_profile_path(value: String) -> bool:
	if value.is_empty() or value.length() > 512 or not value.ends_with(".json") or ".." in value.replace("\\", "/").split("/"): return false
	for index: int in range(value.length()):
		if value.unicode_at(index) < 32: return false
	if value.begins_with("user://"):
		return value.begins_with("user://identity/") and not value.contains("\\") and not value.substr(7).contains("//") and not value.substr(7).contains(":")
	if not value.is_absolute_path() or value.begins_with("res://") or value.substr(2).contains(":"): return false
	var normalized: String = value.replace("\\", "/").simplify_path().to_lower()
	var project: String = ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
	return normalized != project and not normalized.begins_with(project + "/")

func _fail(message: String) -> bool:
	error = message
	return false