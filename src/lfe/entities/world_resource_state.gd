class_name LfeWorldResourceState
extends RefCounted

const CRATE_PATH: String = "res://content/world_objects/wave_3_crate.json"

var _catalog: LfeBlockCatalog
var _drops: Dictionary = {}
var _storage: Dictionary = {}
var _busy: bool = false
var _crate: Dictionary = {}


func _init(catalog: LfeBlockCatalog) -> void:
	_catalog = catalog
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CRATE_PATH))
	if data is Dictionary and data.get("schema_version") == 1 and data.get("id") is String and data.get("display_name") is String and data.get("color") is String and LfeWorldSave._is_integer(data.get("slots")) and int(data["slots"]) > 0 and int(data["slots"]) <= 27:
		_crate = data






func storage_definition() -> Dictionary:
	return _crate.duplicate(true)


func ensure_crate(position: Vector3) -> String:
	if _crate.is_empty() or not _valid_position([position.x, position.y, position.z]):
		return ""
	if not _storage.is_empty():
		return String(_storage.keys()[0])
	var id: String = _new_identity()
	_storage[id] = {
		"instance": id, "content": _crate["id"],
		"position": [position.x, position.y, position.z],
		"inventory": LfeInventory.new(_catalog, int(_crate["slots"])),
	}
	return id


func storage_inventory(id: String) -> LfeInventory:
	return _storage[id]["inventory"] if _storage.has(id) else null


func drops() -> Array:
	return _drops.values().duplicate(true)


func drop(id: String) -> Dictionary:
	return (_drops.get(id, {}) as Dictionary).duplicate(true)


func snapshot() -> Dictionary:
	var containers: Array = []
	for id: String in _storage:
		var entry: Dictionary = _storage[id]
		containers.append({
			"instance": id, "content": entry["content"],
			"position": entry["position"].duplicate(),
			"slots": (entry["inventory"] as LfeInventory).snapshot(),
		})
	containers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["instance"] < b["instance"])
	var items: Array = drops()
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["instance"] < b["instance"])
	return {
		"drops": items, "storage": containers,
	}


func restore(data: Variant) -> bool:
	if _busy or _crate.is_empty() or not data is Dictionary or data.size() != 2:
		return false
	if not data.get("drops") is Array or not data.get("storage") is Array or data["drops"].size() > 10000 or data["storage"].size() > 1:
		return false
	var seen: Dictionary = {}
	var drops_next: Dictionary = {}
	var storage_next: Dictionary = {}
	for entry: Variant in data["drops"]:
		if not entry is Dictionary or entry.size() != 3 or not _valid_identity(entry.get("instance")) or seen.has(entry["instance"]):
			return false
		if not _valid_position(entry.get("position")) or not LfeItemStack.valid(entry.get("stack"), _catalog, false):
			return false
		seen[entry["instance"]] = true
		var coordinates: Array = entry["position"]
		var stack: Dictionary = entry["stack"].duplicate(true)
		stack["quantity"] = int(stack["quantity"])
		if stack.has("durability"):
			stack["durability"] = int(stack["durability"])
		drops_next[entry["instance"]] = {"instance":entry["instance"],"stack":stack,"position":_normalized_position(coordinates)}
	for entry: Variant in data["storage"]:
		if not entry is Dictionary or entry.size() != 4 or not _valid_identity(entry.get("instance")) or seen.has(entry["instance"]):
			return false
		if entry.get("content") != _crate["id"] or not _valid_position(entry.get("position")):
			return false
		var container: LfeInventory = LfeInventory.new(_catalog, int(_crate["slots"]))
		if not container.restore(entry.get("slots")):
			return false
		seen[entry["instance"]] = true
		storage_next[entry["instance"]] = {
			"instance": entry["instance"], "content": entry["content"],
			"position": _normalized_position(entry["position"]), "inventory": container,
		}
	var instance_slots: Array = []
	for entry: Dictionary in drops_next.values():
		instance_slots.append(entry["stack"])
	for entry: Dictionary in storage_next.values():
		instance_slots.append_array((entry["inventory"] as LfeInventory).snapshot())
	if not unique_instances(instance_slots, seen):
		return false
	_drops = drops_next
	_storage = storage_next
	return true


func pickup(personal: LfePlayerResourceState, id: String) -> int:
	if _busy or not _drops.has(id):
		return 0
	var entry: Dictionary = _drops[id]
	var stack: Dictionary = entry["stack"]
	var accepted: int = 0
	if stack.has("instance"):
		var temporary: LfeInventory = LfeInventory.new(_catalog, 1)
		temporary.restore([stack])
		accepted = LfeItemTransactions.transfer(temporary, 0, personal.inventory, 1)
	else:
		accepted = LfeItemTransactions.add(personal.inventory, StringName(stack["content"]), int(stack["quantity"]), true)
	if accepted == 0:
		return 0
	var left: int = int(stack["quantity"]) - accepted
	if left == 0:
		_drops.erase(id)
	else:
		entry["stack"] = LfeItemStack.make(StringName(stack["content"]), left)
	return accepted


func drop_from_inventory(personal: LfePlayerResourceState, slot: int, quantity: int, position: Vector3) -> String:
	if _busy or _drops.size() >= 10000 or not _valid_position([position.x, position.y, position.z]):
		return ""
	var stack: Dictionary = personal.inventory.stack_at(slot)
	if stack.is_empty() or quantity <= 0 or quantity > int(stack["quantity"]):
		return ""
	var id: String = _new_identity()
	if not LfeItemTransactions.remove(personal.inventory, slot, quantity):
		return ""
	_drops[id] = _drop_entry(id, StringName(stack["content"]), quantity, position)
	if stack.has("instance"):
		_drops[id]["stack"] = stack.duplicate(true)
	return id


# World mutations are synchronous validated operations. The callback must return
# OK only after the voxel and its sparse override have changed successfully.
# The guard prevents reentrant pickup/drop/conversion while the world commits.
func break_to_drop(block: StringName, position: Vector3, world_commit: Callable, outputs: Variant = null) -> bool:
	if _busy or not world_commit.is_valid() or not _valid_position([position.x,position.y,position.z]):
		return false
	var definition: Dictionary = _catalog.definition_for_id(block)
	if not bool(definition.get("breakable",false)):
		return false
	var prepared: Array = []
	if outputs != null and not outputs is Array:
		return false
	var resolved: Array = [] if outputs == null else outputs.duplicate(true)
	if outputs == null:
		var id: String = definition.get("drop_content","")
		if not id.is_empty():
			resolved.append({"content":id,"quantity":1})
	for entry: Variant in resolved:
		if not LfeItemStack.valid(entry,_catalog,false) or entry.has("instance"):
			return false
		prepared.append(_drop_entry(_new_identity(),StringName(entry["content"]),int(entry["quantity"]),position))
	if _drops.size() + prepared.size() > 10000:
		return false
	_busy = true
	var result: Variant = world_commit.call()
	_busy = false
	if result != OK:
		return false
	for entry: Dictionary in prepared:
		_drops[entry["instance"]] = entry
	return true


func place_from_inventory(personal: LfePlayerResourceState, slot: int, world_commit: Callable) -> bool:
	if _busy or not world_commit.is_valid():
		return false
	var stack: Dictionary = personal.inventory.stack_at(slot)
	if stack.is_empty() or _catalog.placeable_voxel(StringName(stack["content"])) < 0:
		return false
	var prepared: LfeInventory = LfeInventory.new(_catalog, LfePlayerResourceState.PLAYER_SLOTS)
	prepared.restore(personal.inventory.snapshot())
	if not LfeItemTransactions.remove(prepared, slot, 1):
		return false
	_busy = true
	var result: Variant = world_commit.call()
	_busy = false
	if result != OK:
		return false
	personal.inventory.restore(prepared.snapshot())
	return true


func total(id: StringName) -> int:
	var result: int = 0
	for entry: Dictionary in _drops.values():
		if StringName(entry["stack"]["content"]) == id:
			result += int(entry["stack"]["quantity"])
	for entry: Dictionary in _storage.values():
		result += (entry["inventory"] as LfeInventory).total(id)
	return result


func _new_identity() -> String:
	var id: String = Crypto.new().generate_random_bytes(16).hex_encode()
	while _drops.has(id) or _storage.has(id):
		id = Crypto.new().generate_random_bytes(16).hex_encode()
	return id


func _drop_entry(id: String, content: StringName, quantity: int, position: Vector3) -> Dictionary:
	return {"instance": id, "stack": LfeItemStack.make(content, quantity), "position": [position.x, position.y, position.z]}


static func _valid_identity(value: Variant) -> bool:
	if not value is String or value.length() != 32:
		return false
	for character: String in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true


static func _valid_position(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for coordinate: Variant in value:
		if not LfeWorldSave._finite_in_range(coordinate, 1000000.0):
			return false
	return true


static func _normalized_position(coordinates: Array) -> Array:
	var position: Vector3 = Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
	return [position.x, position.y, position.z]


static func unique_instances(slots: Array, seen: Dictionary = {}) -> bool:
	for stack: Variant in slots:
		if stack != null and stack.has("instance"):
			if seen.has(stack["instance"]):
				return false
			seen[stack["instance"]] = true
	return true


# Local, bounded authority update. Visual animation never calls this method.
# Stateful instances are never combined; ordinary merges respect stack maxima.
func advance_drop_clusters(seconds: float, relevant: Callable, clear_path: Callable, resting_position: Callable = Callable()) -> bool:
	if _busy or not LfeWorldSave._finite_in_range(seconds,1) or seconds<=0 or not relevant.is_valid() or not clear_path.is_valid():
		return false
	var ids: Array = _drops.keys()
	ids.sort()
	var buckets: Dictionary = {}
	var changed: bool = settle_drops(relevant,resting_position) if resting_position.is_valid() else false
	var pairs: int = 0
	for id: String in ids:
		if not _drops.has(id):
			continue
		var entry: Dictionary = _drops[id]
		if entry["stack"].has("instance"):
			continue
		var p: Array = entry["position"]
		var position: Vector3 = Vector3(float(p[0]),float(p[1]),float(p[2]))
		if not relevant.call(position):
			continue
		var bucket: Vector3i = Vector3i((position/2.0).floor())
		var found: bool = false
		for x: int in range(-1,2):
			for y: int in range(-1,2):
				for z: int in range(-1,2):
					for other: String in buckets.get(bucket+Vector3i(x,y,z),[]):
						if found or pairs>=256 or not _drops.has(other):
							continue
						pairs+=1
						var anchor: Dictionary = _drops[other]
						if anchor["stack"]["content"]!=entry["stack"]["content"]:
							continue
						var q: Array = anchor["position"]
						var target: Vector3 = Vector3(float(q[0]),float(q[1]),float(q[2]))
						if absf(position.y-target.y)>0.2:continue
						var distance: float = Vector2(position.x,position.z).distance_to(Vector2(target.x,target.z))
						if distance>2 or not clear_path.call(position,target):
							continue
						if distance<=0.3:
							var room: int = _catalog.stack_limit(StringName(entry["stack"]["content"]))-int(anchor["stack"]["quantity"])
							var count: int = mini(room,int(entry["stack"]["quantity"]))
							if count>0:
								anchor["stack"]["quantity"]+=count
								entry["stack"]["quantity"]-=count
								if entry["stack"]["quantity"]==0:
									_drops.erase(id)
								changed=true
						else:
							var next: Vector3 = position.move_toward(Vector3(target.x,position.y,target.z),0.18*seconds)
							if resting_position.is_valid():
								var rested: Variant = resting_position.call(next)
								if not rested is Vector3 or absf(rested.y-position.y)>0.2:continue
								next=rested
							entry["position"]=[next.x,next.y,next.z]
							changed=true
						found=true
		if _drops.has(id):
			if not buckets.has(bucket):
				buckets[bucket]=[]
			buckets[bucket].append(id)
	return changed


# Only positions change. Resolve support through the world's loaded voxel query.
var _settle_cursor: int = 0

func ground_drop(id: String, resting_position: Callable) -> bool:
	if not _drops.has(id) or not resting_position.is_valid():return false
	var p: Array = _drops[id]["position"]
	var before: Vector3 = Vector3(float(p[0]),float(p[1]),float(p[2]))
	var after: Variant = resting_position.call(before)
	if not after is Vector3 or not after.is_finite() or after.x!=before.x or after.z!=before.z or absf(after.y)>1000000 or before==after:return false
	_drops[id]["position"]=[after.x,after.y,after.z]
	return true

func settle_drops(relevant: Callable, resting_position: Callable) -> bool:
	if not relevant.is_valid() or not resting_position.is_valid() or _drops.is_empty():return false
	var ids: Array = _drops.keys();ids.sort()
	var changed: bool = false
	var count: int = mini(64,ids.size())
	for index: int in count:
		var id: String = ids[(_settle_cursor+index)%ids.size()]
		var p: Array = _drops[id]["position"]
		if relevant.call(Vector3(float(p[0]),float(p[1]),float(p[2]))):changed=ground_drop(id,resting_position) or changed
	_settle_cursor=(_settle_cursor+count)%ids.size()
	return changed
