class_name LfeVoxelReplica
extends RefCounted

var store: LfeVoxelOverrideStore = LfeVoxelOverrideStore.new()
var revisions: Dictionary = {}
var transfers: Dictionary = {}
var catalog: LfeBlockCatalog
var generator: LfeWave1TerrainGenerator
var sync_id: int = 0
var expected: int = 0
var received: Dictionary = {}
var complete_declared: bool = false
var synchronized: bool = false
var last_transfer: int = 0

func begin_sync(id: int, count: int) -> bool:
	if id <= sync_id or count > LfeVoxelProtocol.MAX_BUCKETS: return false
	sync_id = id
	expected = count
	received.clear()
	complete_declared = false
	return true

func ready() -> bool:
	return complete_declared and transfers.is_empty() and received.size() == expected

func receive(packet: Dictionary, now: float) -> Dictionary:
	if not LfeVoxelProtocol.valid(packet,catalog): return {"ok":false}
	var kind: String = packet["kind"]
	if kind == "voxel_sync_begin":
		return {"ok":begin_sync(int(packet["sync_id"]),int(packet["count"]))}
	if kind == "voxel_sync_count":
		if int(packet["sync_id"]) != sync_id or int(packet["count"]) < expected: return {"ok":false}
		expected = int(packet["count"])
		return {"ok":true}
	if kind == "voxel_sync_complete":
		if int(packet["sync_id"]) != sync_id: return {"ok":false}
		complete_declared = true
		return {"ok":true}
	if kind == "voxel_snapshot_begin":
		var id: int = int(packet["transfer"])
		if int(packet["sync_id"]) != sync_id or id <= last_transfer or transfers.has(id) or transfers.size() >= LfeVoxelProtocol.MAX_TRANSFERS: return {"ok":false}
		last_transfer = id
		var state: Dictionary = packet.duplicate(true)
		state["deadline"] = now + LfeVoxelProtocol.TRANSFER_SECONDS
		state["data"] = {}
		transfers[id] = state
		return {"ok":true}
	if kind == "voxel_snapshot_part":
		var id: int = int(packet["transfer"])
		if not transfers.has(id): return {"ok":false}
		var state: Dictionary = transfers[id]
		var bucket: Vector3i = LfeVoxelProtocol.cell(state["bucket"])
		var index: int = int(packet["index"])
		var wanted: int = mini(LfeVoxelProtocol.PART_ENTRIES,int(state["count"])-index*LfeVoxelProtocol.PART_ENTRIES)
		if index >= int(state["parts"]) or packet["entries"].size() != wanted or not LfeVoxelProtocol.entries(packet["entries"],bucket,catalog,LfeVoxelProtocol.PART_ENTRIES):
			transfers.erase(id)
			return {"ok":false,"resync":bucket}
		if state["data"].has(index) and state["data"][index] != packet["entries"]:
			transfers.erase(id)
			return {"ok":false,"resync":bucket}
		state["data"][index] = packet["entries"].duplicate(true)
		return {"ok":true}
	if kind == "voxel_snapshot_complete":
		var id: int = int(packet["transfer"])
		if not transfers.has(id): return {"ok":false}
		var state: Dictionary = transfers[id]
		transfers.erase(id)
		var bucket: Vector3i = LfeVoxelProtocol.cell(state["bucket"])
		if state["data"].size() != int(state["parts"]): return {"ok":false,"resync":bucket}
		var values: Array = []
		for index: int in int(state["parts"]): values.append_array(state["data"][index])
		var revision: int = int(state["revision"])
		if values.size() != int(state["count"]) or not LfeVoxelProtocol.entries(values,bucket,catalog,LfeVoxelProtocol.MAX_ENTRIES) or LfeVoxelProtocol.snapshot_hash(bucket,revision,values) != state["hash"]:
			return {"ok":false,"resync":bucket}
		if not revisions.has(bucket) and revisions.size() >= LfeVoxelProtocol.MAX_BUCKETS: return {"ok":false,"fatal":true}
		if store.count() - store.bucket_snapshot(bucket).size() + values.size() > LfeVoxelProtocol.MAX_SYNC_ENTRIES: return {"ok":false,"fatal":true}
		var result: Dictionary = store.replace_bucket(bucket,values,catalog)
		if not result["ok"]: return result
		revisions[bucket] = revision
		received[bucket] = true
		result["bucket"] = bucket
		result["snapshot"] = true
		return result
	if kind == "voxel_delta_batch":
		var bucket: Vector3i = LfeVoxelProtocol.cell(packet["bucket"])
		if not revisions.has(bucket) or int(packet["from_revision"]) != int(revisions[bucket]):
			# Never apply any future edit across a logical gap.
			return {"ok":false,"resync":bucket}
		var current: Dictionary = {}
		for entry: Dictionary in store.bucket_snapshot(bucket): current[LfeVoxelProtocol.cell(entry["position"])] = entry
		for entry: Dictionary in packet["edits"]:
			var position: Vector3i = LfeVoxelProtocol.cell(entry["position"])
			if catalog.get_voxel_id(StringName(entry["block"])) == generator.sample_voxel_id(position): current.erase(position)
			else: current[position] = entry
		if store.count() - store.bucket_snapshot(bucket).size() + current.size() > LfeVoxelProtocol.MAX_SYNC_ENTRIES: return {"ok":false,"fatal":true}
		var result: Dictionary = store.replace_bucket(bucket,current.values(),catalog)
		if not result["ok"]: return result
		var changed: Array = []
		for entry: Dictionary in packet["edits"]: changed.append(LfeVoxelProtocol.cell(entry["position"]))
		result["cells"] = changed
		result["bucket"] = bucket
		revisions[bucket] = int(packet["to_revision"])
		return result
	return {"ok":false}

func expire(now: float) -> Array:
	var buckets: Array = []
	for id: int in transfers.keys():
		if now >= float(transfers[id]["deadline"]):
			buckets.append(LfeVoxelProtocol.cell(transfers[id]["bucket"]))
			transfers.erase(id)
	return buckets

func hash_for(bucket: Vector3i) -> String:
	return LfeVoxelProtocol.snapshot_hash(bucket,int(revisions.get(bucket,0)),store.bucket_snapshot(bucket))
