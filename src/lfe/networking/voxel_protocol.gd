class_name LfeVoxelProtocol
extends RefCounted

const STATE_CHANNEL: int = 4
const ACTION_CHANNEL: int = 5
const MAX_BYTES: int = 1200
const MAX_ENTRIES: int = 4096
const PART_ENTRIES: int = 8
const MAX_PARTS: int = 512
const MAX_BUCKETS: int = 4096
const MAX_SYNC_ENTRIES: int = 65536
const MAX_TRANSFERS: int = 4
const TRANSFER_SECONDS: float = 5.0
const FLUSH_HZ: float = 20.0
const HOLD_SECONDS: float = 0.30
const HOLD_HZ: float = 10.0
const REASONS: Array = ["accepted","cancelled","stale_state","out_of_range","blocked","tool_required","completed","not_ready"]

static func coordinate(value: Variant, bucket: bool = false) -> bool:
	if not value is Array or value.size() != 3: return false
	var bound: int = 67108864 if bucket else LfeVoxelOverrideStore.MAX_COORDINATE
	for component: Variant in value:
		if not LfeMovementProtocol.finite(component,bound) or float(component) != floorf(float(component)) or (bucket and float(component) > 67108863): return false
	return true

static func cell(value: Array) -> Vector3i:
	return Vector3i(int(value[0]),int(value[1]),int(value[2]))

static func array3(value: Vector3i) -> Array:
	return [value.x,value.y,value.z]

static func block(value: Variant, catalog: LfeBlockCatalog) -> bool:
	return value is String and value.length() <= 64 and catalog.has_id(StringName(value))

static func entries(value: Variant, bucket: Vector3i, catalog: LfeBlockCatalog, maximum: int) -> bool:
	if not value is Array or value.size() > maximum: return false
	var seen: Dictionary = {}
	for entry: Variant in value:
		if not LfeCompatibilityManifest.exact_keys(entry,["position","block"]) or not coordinate(entry["position"]) or not block(entry["block"],catalog): return false
		var position: Vector3i = cell(entry["position"])
		if LfeVoxelOverrideStore.bucket_for(position) != bucket or seen.has(position): return false
		seen[position] = true
	return true

static func valid(value: Variant, catalog: LfeBlockCatalog) -> bool:
	if not value is Dictionary or not value.get("kind") is String: return false
	var kind: String = value["kind"]
	var keys: Array
	match kind:
		"voxel_sync_begin","voxel_sync_count": keys = ["kind","sync_id","count"]
		"voxel_sync_complete","voxel_sync_ack": keys = ["kind","sync_id"]
		"voxel_snapshot_begin": keys = ["kind","sync_id","transfer","bucket","revision","count","parts","hash"]
		"voxel_snapshot_part": keys = ["kind","transfer","index","entries"]
		"voxel_snapshot_complete": keys = ["kind","transfer"]
		"voxel_delta_batch": keys = ["kind","bucket","from_revision","to_revision","edits"]
		"voxel_resync_request": keys = ["kind","bucket","revision"]
		"voxel_harvest_state": keys = ["kind","action_sequence","active","target_cell","expected_block"]
		"voxel_harvest_result": keys = ["kind","action_sequence","reason","progress"]
		_: return false
	if not LfeCompatibilityManifest.exact_keys(value,keys): return false
	for field: String in ["sync_id","transfer","action_sequence"]:
		if value.has(field) and not LfeMovementProtocol.integer(value[field],1): return false
	for field: String in ["revision","from_revision","to_revision"]:
		if value.has(field) and not LfeMovementProtocol.integer(value[field]): return false
	if value.has("bucket") and not coordinate(value["bucket"],true): return false
	match kind:
		"voxel_sync_begin","voxel_sync_count": return LfeMovementProtocol.integer(value["count"]) and int(value["count"]) <= MAX_BUCKETS
		"voxel_snapshot_begin":
			return LfeMovementProtocol.integer(value["count"]) and int(value["count"]) <= MAX_ENTRIES and LfeMovementProtocol.integer(value["parts"],1) and int(value["parts"]) == maxi(1,ceili(float(value["count"]) / PART_ENTRIES)) and LfeCompatibilityManifest.valid_hash(value["hash"])
		"voxel_snapshot_part":
			if not LfeMovementProtocol.integer(value["index"]) or int(value["index"]) >= MAX_PARTS or not value["entries"] is Array or value["entries"].size() > PART_ENTRIES: return false
			for entry: Variant in value["entries"]:
				if not LfeCompatibilityManifest.exact_keys(entry,["position","block"]) or not coordinate(entry["position"]) or not block(entry["block"],catalog): return false
		"voxel_delta_batch":
			return int(value["to_revision"]) > int(value["from_revision"]) and int(value["to_revision"]) - int(value["from_revision"]) <= MAX_ENTRIES and value["edits"] is Array and not value["edits"].is_empty() and entries(value["edits"],cell(value["bucket"]),catalog,PART_ENTRIES)
		"voxel_harvest_state": return value["active"] is bool and coordinate(value["target_cell"]) and block(value["expected_block"],catalog)
		"voxel_harvest_result": return value["reason"] is String and value["reason"] in REASONS and LfeMovementProtocol.finite(value["progress"],1.0) and float(value["progress"]) >= 0
	return true

static func encode(value: Dictionary, catalog: LfeBlockCatalog) -> PackedByteArray:
	if not valid(value,catalog): return PackedByteArray()
	var bytes: PackedByteArray = JSON.stringify(value).to_utf8_buffer()
	return bytes if bytes.size() <= MAX_BYTES else PackedByteArray()

static func decode(bytes: PackedByteArray, catalog: LfeBlockCatalog) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_BYTES: return {}
	var source: String = bytes.get_string_from_utf8()
	if source.to_utf8_buffer() != bytes: return {}
	var parser: JSON = JSON.new()
	if parser.parse(source) != OK or not valid(parser.data,catalog): return {}
	return parser.data

static func snapshot_hash(bucket: Vector3i, revision: int, values: Array) -> String:
	var ordered: Array = values.duplicate(true)
	ordered.sort_custom(LfeVoxelOverrideStore.entry_less)
	# Arrays normalize key order and JSON numeric types.
	var normalized: Array = []
	for entry: Dictionary in ordered: normalized.append([array3(cell(entry["position"])),String(entry["block"])])
	return JSON.stringify([array3(bucket),revision,normalized]).sha256_text()

static func snapshot_packets(bucket: Vector3i, revision: int, values: Array, transfer: int, sync_id: int) -> Array[Dictionary]:
	var ordered: Array = values.duplicate(true)
	ordered.sort_custom(LfeVoxelOverrideStore.entry_less)
	var parts: int = maxi(1,ceili(float(ordered.size()) / PART_ENTRIES))
	var result: Array[Dictionary] = [{"kind":"voxel_snapshot_begin","sync_id":sync_id,"transfer":transfer,"bucket":array3(bucket),"revision":revision,"count":ordered.size(),"parts":parts,"hash":snapshot_hash(bucket,revision,ordered)}]
	for index: int in parts:
		result.append({"kind":"voxel_snapshot_part","transfer":transfer,"index":index,"entries":ordered.slice(index*PART_ENTRIES,(index+1)*PART_ENTRIES)})
	result.append({"kind":"voxel_snapshot_complete","transfer":transfer})
	return result
