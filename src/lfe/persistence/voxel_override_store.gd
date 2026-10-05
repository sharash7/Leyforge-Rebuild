class_name LfeVoxelOverrideStore
extends RefCounted

# Generator callbacks can run on worker threads. Mutations and snapshots share a lock.
const BUCKET_SIZE: int = 16
const MAX_COORDINATE: int = 1073741823

var _entries: Dictionary = {}
var _buckets: Dictionary = {}
var _mutex: Mutex = Mutex.new()
var _last_error: String = ""


func get_last_error() -> String:
	return _last_error


func count() -> int:
	_mutex.lock()
	var result: int = _entries.size()
	_mutex.unlock()
	return result


func record_edit(cell: Vector3i, voxel_id: int, base_voxel_id: int, catalog: LfeBlockCatalog) -> Error:
	if not valid_cell(cell): return ERR_INVALID_DATA
	var canonical_id: StringName = catalog.canonical_id_for_voxel_id(voxel_id)
	if canonical_id == &"":
		_last_error = "Edited voxel has no canonical block ID: %d." % voxel_id
		return ERR_INVALID_DATA
	_mutex.lock()
	if voxel_id == base_voxel_id:
		_entries.erase(cell)
		var bucket: Vector3i = _bucket_for(cell)
		if _buckets.has(bucket):
			var bucket_entries: Dictionary = _buckets[bucket]
			bucket_entries.erase(cell)
			if bucket_entries.is_empty():
				_buckets.erase(bucket)
	else:
		var entry: Dictionary = {"block": String(canonical_id), "voxel_id": voxel_id}
		_entries[cell] = entry
		var bucket: Vector3i = _bucket_for(cell)
		if not _buckets.has(bucket):
			_buckets[bucket] = {}
		var bucket_entries: Dictionary = _buckets[bucket]
		bucket_entries[cell] = entry
	_mutex.unlock()
	_last_error = ""
	return OK


func voxel_id_at(cell: Vector3i, base_voxel_id: int) -> int:
	_mutex.lock()
	var result: int = base_voxel_id
	if _entries.has(cell):
		result = int((_entries[cell] as Dictionary)["voxel_id"])
	_mutex.unlock()
	return result


func canonical_id_at(cell: Vector3i) -> String:
	_mutex.lock()
	var result: String = ""
	if _entries.has(cell):
		result = String((_entries[cell] as Dictionary)["block"])
	_mutex.unlock()
	return result


func snapshot_for_block(origin: Vector3i, size: Vector3i) -> Dictionary:
	var result: Dictionary = {}
	var last: Vector3i = origin + size - Vector3i.ONE
	var first_bucket: Vector3i = _bucket_for(origin)
	var last_bucket: Vector3i = _bucket_for(last)
	_mutex.lock()
	for bucket_z: int in range(first_bucket.z, last_bucket.z + 1):
		for bucket_y: int in range(first_bucket.y, last_bucket.y + 1):
			for bucket_x: int in range(first_bucket.x, last_bucket.x + 1):
				var bucket: Vector3i = Vector3i(bucket_x, bucket_y, bucket_z)
				if not _buckets.has(bucket):
					continue
				var bucket_entries: Dictionary = _buckets[bucket]
				for cell: Vector3i in bucket_entries:
					if (
						cell.x >= origin.x and cell.x <= last.x
						and cell.y >= origin.y and cell.y <= last.y
						and cell.z >= origin.z and cell.z <= last.z
					):
						result[cell] = int((bucket_entries[cell] as Dictionary)["voxel_id"])
	_mutex.unlock()
	return result


func serialized_entries() -> Array:
	var result: Array = []
	_mutex.lock()
	for cell: Vector3i in _entries:
		result.append({
			"position": [cell.x, cell.y, cell.z],
			"block": String((_entries[cell] as Dictionary)["block"]),
		})
	_mutex.unlock()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: Array = a["position"]
		var right: Array = b["position"]
		for axis: int in range(3):
			if left[axis] != right[axis]:
				return int(left[axis]) < int(right[axis])
		return false
	)
	return result


func load_entries(value: Variant, catalog: LfeBlockCatalog) -> Error:
	if not value is Array:
		_last_error = "Voxel overrides must be an array."
		return ERR_INVALID_DATA
	var staged_entries: Dictionary = {}
	var staged_buckets: Dictionary = {}
	for raw_entry: Variant in value:
		if not raw_entry is Dictionary:
			_last_error = "Voxel override must be an object."
			return ERR_INVALID_DATA
		var entry: Dictionary = raw_entry
		var raw_position: Variant = entry.get("position")
		if not raw_position is Array or (raw_position as Array).size() != 3:
			_last_error = "Voxel override position must contain three integer coordinates."
			return ERR_INVALID_DATA
		var coordinates: Array = raw_position
		for component: Variant in coordinates:
			if not _is_valid_coordinate(component):
				_last_error = "Voxel override coordinate is invalid or out of range."
				return ERR_INVALID_DATA
		var cell: Vector3i = Vector3i(int(coordinates[0]), int(coordinates[1]), int(coordinates[2]))
		if staged_entries.has(cell):
			_last_error = "Duplicate voxel override at %s." % cell
			return ERR_INVALID_DATA
		var block_value: Variant = entry.get("block")
		if not block_value is String or String(block_value).is_empty():
			_last_error = "Voxel override has no canonical block ID."
			return ERR_INVALID_DATA
		var canonical_id: StringName = StringName(block_value)
		if not catalog.has_id(canonical_id):
			_last_error = "Unknown canonical block ID: %s." % canonical_id
			return ERR_INVALID_DATA
		var stored: Dictionary = {
			"block": String(canonical_id),
			"voxel_id": catalog.get_voxel_id(canonical_id),
		}
		staged_entries[cell] = stored
		var bucket: Vector3i = _bucket_for(cell)
		if not staged_buckets.has(bucket):
			staged_buckets[bucket] = {}
		var bucket_entries: Dictionary = staged_buckets[bucket]
		bucket_entries[cell] = stored
	_mutex.lock()
	_entries = staged_entries
	_buckets = staged_buckets
	_mutex.unlock()
	_last_error = ""
	return OK


static func _is_valid_coordinate(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var numeric: float = float(value)
	return (
		not is_nan(numeric) and not is_inf(numeric)
		and numeric == floorf(numeric)
		and absf(numeric) <= float(MAX_COORDINATE)
	)


static func _bucket_for(cell: Vector3i) -> Vector3i:
	return bucket_for(cell)


static func bucket_for(cell: Vector3i) -> Vector3i:
	return Vector3i(
		floori(float(cell.x) / float(BUCKET_SIZE)),
		floori(float(cell.y) / float(BUCKET_SIZE)),
		floori(float(cell.z) / float(BUCKET_SIZE))
	)

static func valid_cell(cell: Vector3i) -> bool:
	return absi(cell.x) <= MAX_COORDINATE and absi(cell.y) <= MAX_COORDINATE and absi(cell.z) <= MAX_COORDINATE

static func bucket_origin(bucket: Vector3i) -> Vector3i:
	return bucket * BUCKET_SIZE

static func bucket_aabb(bucket: Vector3i) -> AABB:
	return AABB(Vector3(bucket_origin(bucket)), Vector3.ONE * BUCKET_SIZE)

func bucket_keys() -> Array:
	_mutex.lock()
	var result: Array = _buckets.keys()
	_mutex.unlock()
	return result

func bucket_snapshot(bucket: Vector3i) -> Array:
	var result: Array = []
	_mutex.lock()
	for cell: Vector3i in _buckets.get(bucket, {}):
		result.append({"position": [cell.x,cell.y,cell.z], "block": _entries[cell]["block"]})
	_mutex.unlock()
	result.sort_custom(entry_less)
	return result

static func entry_less(a: Dictionary, b: Dictionary) -> bool:
	for axis: int in range(3):
		if a["position"][axis] != b["position"][axis]:
			return int(a["position"][axis]) < int(b["position"][axis])
	return false

# Validate off-lock; publish one complete bucket under the generator lock.
# Omitted old cells are returned too, so loaded terrain can restore base.
func replace_bucket(bucket: Vector3i, entries: Array, catalog: LfeBlockCatalog) -> Dictionary:
	if entries.size() > BUCKET_SIZE * BUCKET_SIZE * BUCKET_SIZE: return {"ok":false}
	var staged: LfeVoxelOverrideStore = LfeVoxelOverrideStore.new()
	if staged.load_entries(entries,catalog) != OK: return {"ok":false}
	for cell: Vector3i in staged._entries:
		if bucket_for(cell) != bucket: return {"ok":false}
	var changed: Dictionary = {}
	_mutex.lock()
	for cell: Vector3i in _buckets.get(bucket,{}):
		changed[cell] = true
		_entries.erase(cell)
	_buckets.erase(bucket)
	for cell: Vector3i in staged._entries:
		changed[cell] = true
		_entries[cell] = staged._entries[cell]
	if not staged._entries.is_empty(): _buckets[bucket] = staged._entries
	_mutex.unlock()
	return {"ok":true,"cells":changed.keys()}
