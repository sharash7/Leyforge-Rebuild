class_name LfeResourceProtocol
extends RefCounted

const STATE_CHANNEL: int = 6
const COMMAND_CHANNEL: int = 7
const POSITION_CHANNEL: int = 8
const PART_BYTES: int = 460
const MAX_PARTS: int = 128
const MAX_STREAMS: int = 2048
const MAX_SEQUENCE: int = 2147483647
const OPERATIONS: Dictionary = {
	"select":["slot"], "pickup":["target"], "drop":["slot","quantity","expected"],
	"transfer":["source","destination","source_slot","destination_slot","quantity","expected"],
	"swap":["source","destination","source_slot","destination_slot","expected"],
	"open_context":["target"], "close_grid":[], "craft":["recipe"],
	"start_process":["target","recipe"], "place":["cell","expected_block","slot","expected"],
	"source_hold":["target","active"]
}
const REASONS: Array = ["ok","stale_state","invalid_target","out_of_range","inventory_full","insufficient_resources","blocked","tool_required","context_invalid","output_full","not_ready","rate_limited","already_processed"]

static func integer(value: Variant, low: int, high: int) -> bool:
	return LfeWorldSave._is_integer(value) and value >= low and value <= high

static func endpoint(value: Variant) -> bool:
	if not value is String: return false
	if value in ["inventory","equipment","grid"]: return true
	var f: PackedStringArray = value.split("/")
	return (f.size() == 2 and f[0] == "storage" and LfeWorldResourceState._valid_identity(f[1])) or (f.size() == 3 and f[0] == "station" and LfeWorldResourceState._valid_identity(f[1]) and f[2] in ["input","fuel","output"])

static func stream(value: Variant) -> bool:
	if not value is String: return false
	var f: PackedStringArray = value.split("/")
	return f.size() == 2 and f[0] in ["player","grid","drop","source","storage","object"] and LfeWorldResourceState._valid_identity(f[1])

static func request_valid(p: Variant, catalog: LfeBlockCatalog) -> bool:
	if not LfeCompatibilityManifest.exact_keys(p,["kind","sequence","transaction_id","operation","args","expected_revisions"]): return false
	if p["kind"] != "resource_request" or not integer(p["sequence"],1,MAX_SEQUENCE) or not LfeWorldResourceState._valid_identity(p["transaction_id"]): return false
	if not p["operation"] is String or not OPERATIONS.has(p["operation"]) or not LfeCompatibilityManifest.exact_keys(p["args"],OPERATIONS[p["operation"]]): return false
	if not p["expected_revisions"] is Dictionary or p["expected_revisions"].size() > 4: return false
	for key: Variant in p["expected_revisions"]:
		if not stream(key) or not integer(p["expected_revisions"][key],0,MAX_SEQUENCE): return false
	var a: Dictionary = p["args"]
	for key: String in a:
		match key:
			"slot","source_slot":
				if not integer(a[key],0,26): return false
			"destination_slot":
				if not integer(a[key],-1,26): return false
			"quantity":
				if not integer(a[key],1,1000000): return false
			"source","destination":
				if not endpoint(a[key]): return false
			"target":
				if not a[key] is String or (not a[key].is_empty() and not LfeWorldResourceState._valid_identity(a[key])): return false
			"recipe":
				if not a[key] is String or a[key].length() > 96 or not a[key].begins_with("leyforge:"): return false
			"active":
				if not a[key] is bool: return false
			"expected":
				if not a[key] is Dictionary or not LfeItemStack.valid(a[key],catalog,false): return false
			"cell":
				if not a[key] is Array or a[key].size() != 3: return false
				for v: Variant in a[key]:
					if not integer(v,-1000000,1000000): return false
			"expected_block":
				if not a[key] is String or not catalog.has_id(StringName(a[key])): return false
	return true

static func valid(p: Variant, catalog: LfeBlockCatalog) -> bool:
	if not p is Dictionary or not p.get("kind") is String: return false
	match p["kind"]:
		"resource_request": return request_valid(p,catalog)
		"resource_ready":
			return LfeCompatibilityManifest.exact_keys(p,["kind","count","hash"]) and integer(p["count"],1,MAX_STREAMS) and hex(p["hash"],64)
		"resource_result":
			return LfeCompatibilityManifest.exact_keys(p,["kind","transaction_id","success","reason","data"]) and LfeWorldResourceState._valid_identity(p["transaction_id"]) and p["success"] is bool and p["reason"] in REASONS and p["data"] is Dictionary and JSON.stringify(p["data"]).length() < 2048
		"resource_part":
			if not LfeCompatibilityManifest.exact_keys(p,["kind","stream","revision","from_revision","transfer","part","count","hash","bytes"]): return false
			return stream(p["stream"]) and integer(p["revision"],1,MAX_SEQUENCE) and integer(p["from_revision"],-1,MAX_SEQUENCE) and LfeWorldResourceState._valid_identity(p["transfer"]) and integer(p["count"],1,MAX_PARTS) and integer(p["part"],0,int(p["count"])-1) and hex(p["hash"],64) and p["bytes"] is String and p["bytes"].length() <= PART_BYTES*2 and hex(p["bytes"],p["bytes"].length())
		"resource_forget","resource_resync":
			return LfeCompatibilityManifest.exact_keys(p,["kind","stream"]) and stream(p["stream"])
		"resource_position":
			return LfeCompatibilityManifest.exact_keys(p,["kind","stream","revision","sequence","position"]) and stream(p["stream"]) and p["stream"].begins_with("drop/") and integer(p["revision"],1,MAX_SEQUENCE) and integer(p["sequence"],1,MAX_SEQUENCE) and LfeWorldResourceState._valid_position(p["position"])
	return false

static func hex(value: Variant, size: int) -> bool:
	if not value is String or value.length() != size or size == 0: return false
	for c: String in value:
		if not "0123456789abcdef".contains(c): return false
	return true

static func decode(bytes: PackedByteArray, catalog: LfeBlockCatalog) -> Dictionary:
	if bytes.is_empty() or bytes.size() > 8192: return {}
	var source: String = bytes.get_string_from_utf8()
	if source.to_utf8_buffer() != bytes: return {}
	var parser: JSON = JSON.new()
	if parser.parse(source) != OK or not valid(parser.data,catalog): return {}
	var p: Dictionary = parser.data
	if p["kind"] == "resource_request" and p["args"].has("expected"):
		p["args"]["expected"]["quantity"] = int(p["args"]["expected"]["quantity"])
		if p["args"]["expected"].has("durability"): p["args"]["expected"]["durability"] = int(p["args"]["expected"]["durability"])
	return p

static func encode(p: Dictionary, catalog: LfeBlockCatalog) -> PackedByteArray:
	if not valid(p,catalog): return PackedByteArray()
	var bytes: PackedByteArray = JSON.stringify(p,"",true).to_utf8_buffer()
	return bytes if bytes.size() <= 8192 else PackedByteArray()

static func normalized(value: Variant) -> String:
	if value is float and is_finite(value) and value == floor(value) and absf(value) <= MAX_SEQUENCE: return str(int(value))
	if value is Dictionary:
		var keys: Array = value.keys(); keys.sort()
		var fields: PackedStringArray = []
		for key: String in keys: fields.append(JSON.stringify(key)+":"+normalized(value[key]))
		return "{"+",".join(fields)+"}"
	if value is Array:
		var fields: PackedStringArray = []
		for entry: Variant in value: fields.append(normalized(entry))
		return "["+",".join(fields)+"]"
	return JSON.stringify(value)

static func parts(key: String, revision: int, state: Dictionary, from_revision: int = -1) -> Array[Dictionary]:
	var bytes: PackedByteArray = normalized(state).to_utf8_buffer()
	var count: int = ceili(float(bytes.size())/PART_BYTES)
	var packets: Array[Dictionary] = []
	if count < 1 or count > MAX_PARTS: return packets
	var transfer: String = Crypto.new().generate_random_bytes(16).hex_encode()
	for index: int in count:
		packets.append({"kind":"resource_part","stream":key,"revision":revision,"from_revision":from_revision,"transfer":transfer,"part":index,"count":count,"hash":bytes.hex_encode().sha256_text(),"bytes":bytes.slice(index*PART_BYTES,mini((index+1)*PART_BYTES,bytes.size())).hex_encode()})
	return packets
