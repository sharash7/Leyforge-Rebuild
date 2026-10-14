class_name LfeSessionLifecycleProtocol
extends RefCounted

const CHANNEL: int = 11
const MAX_BYTES: int = 128
const KINDS: Array = ["session_closing", "session_closing_ack", "client_leaving", "session_heartbeat", "session_ping", "session_pong"]

static func encode(packet: Dictionary) -> PackedByteArray:
	var bytes: PackedByteArray = JSON.stringify(packet).to_utf8_buffer()
	return bytes if not decode(bytes).is_empty() else PackedByteArray()

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_BYTES: return {}
	var source: String = bytes.get_string_from_utf8()
	if source.to_utf8_buffer() != bytes: return {}
	var parser: JSON = JSON.new()
	if parser.parse(source) != OK: return {}
	var value: Variant = parser.data
	if not value is Dictionary or not value.get("kind") is String or value["kind"] not in KINDS: return {}
	if value["kind"] == "session_closing":
		if not LfeCompatibilityManifest.exact_keys(value,["kind","reason"]) or not value["reason"] is String or value["reason"] != "host_shutdown": return {}
	elif value["kind"] in ["session_ping","session_pong"]:
		if not LfeCompatibilityManifest.exact_keys(value,["kind","sequence"]) or not LfeWorldSave._is_integer(value["sequence"]) or float(value["sequence"]) < 1 or float(value["sequence"]) > 2147483647: return {}
		value["sequence"] = int(value["sequence"])
	elif not LfeCompatibilityManifest.exact_keys(value,["kind"]): return {}
	return value
