extends SceneTree
var checks: int = 0
var failures: Array = []
var output: String
var catalog: LfeBlockCatalog
var generator: LfeWave1TerrainGenerator

func _initialize() -> void: call_deferred("_run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	catalog = LfeBlockCatalog.new()
	check(catalog.load_default() == OK,"canonical catalog")
	generator = LfeWave1TerrainGenerator.new()
	generator.configure(184552221,catalog,2)
	var spawn_game: LeyforgeWave1Playground = LeyforgeWave1Playground.new()
	spawn_game.block_catalog = catalog
	spawn_game._generator = generator
	var floor_y: int = 40
	while not catalog.is_solid_voxel(generator.sample_voxel_id(Vector3i(0,floor_y,0))): floor_y -= 1
	var airborne: Vector3 = Vector3(0.5,float(floor_y)+1.8,0.5)
	check(not spawn_game.network_position_safe(airborne),"new spawn still requires immediate support")
	check(spawn_game.network_position_safe(airborne,4.0),"safe saved airborne body retains nearby landing support")
	check(not spawn_game.network_position_safe(airborne+Vector3.UP*5,4.0),"saved body without bounded support rejected")
	check(not spawn_game.network_position_safe(airborne-Vector3.UP*1.8,4.0),"embedded saved capsule rejected")
	spawn_game.free()
	for pair: Array in [[Vector3i(0,15,16),Vector3i(0,0,1)],[Vector3i(-1,-16,-17),Vector3i(-1,-1,-2)],[Vector3i(31,32,33),Vector3i(1,2,2)]]:
		check(LfeVoxelOverrideStore.bucket_for(pair[0]) == pair[1],"positive/negative floor bucket math")
		check(LfeVoxelOverrideStore.bucket_aabb(pair[1]).has_point(Vector3(pair[0])+Vector3.ONE*0.5),"bucket AABB")
	check(not LfeVoxelProtocol.coordinate([67108864,0,0],true) and LfeVoxelProtocol.coordinate([-67108864,0,0],true),"asymmetric edge buckets remain within valid world cells")
	var extended: LfeVoxelReplica = _replica()
	extended.begin_sync(1,0)
	check(extended.receive({"kind":"voxel_sync_count","sync_id":1,"count":2},0)["ok"] and extended.expected == 2,"sync count extends for newly committed buckets")
	check(not extended.receive({"kind":"voxel_sync_count","sync_id":1,"count":1},0)["ok"],"sync count cannot lose required buckets")
	var bucket: Vector3i = Vector3i.ZERO
	var values: Array = [{"position":[0,1,0],"block":"leyforge:air"},{"position":[1,1,0],"block":"leyforge:dirt"}]
	var swapped: Array = values.duplicate(true); swapped.reverse()
	check(LfeVoxelProtocol.snapshot_hash(bucket,1,values) == LfeVoxelProtocol.snapshot_hash(bucket,1,swapped),"canonical sorted hash")
	check(LfeVoxelProtocol.snapshot_hash(bucket,1,values) != LfeVoxelProtocol.snapshot_hash(bucket,2,values),"revision hash")
	swapped[0]["block"] = "leyforge:air"
	check(LfeVoxelProtocol.snapshot_hash(bucket,1,values) != LfeVoxelProtocol.snapshot_hash(bucket,1,swapped),"changed override hash")
	var dense: Array = []
	for x: int in 16:
		for y: int in 16:
			for z: int in 16: dense.append({"position":[x,y,z],"block":"leyforge:dirt"})
	var packets: Array[Dictionary] = LfeVoxelProtocol.snapshot_packets(bucket,0,dense,1,1)
	check(packets.size() == 514,"maximum 4096 entries bounded parts")
	var maximum: int = 0
	for packet: Dictionary in packets:
		var bytes: PackedByteArray = LfeVoxelProtocol.encode(packet,catalog)
		maximum = maxi(maximum,bytes.size())
		check(not bytes.is_empty() and bytes.size() <= 1200,"all dense parts bounded")
		check(not LfeVoxelProtocol.decode(bytes,catalog).is_empty(),"all dense parts exact decode")
		for field: String in packet:
			var bad: Dictionary = packet.duplicate(true); bad.erase(field)
			check(not LfeVoxelProtocol.valid(bad,catalog),"missing exact field "+field)
	var replica: LfeVoxelReplica = _replica()
	check(replica.receive({"kind":"voxel_sync_begin","sync_id":1,"count":1},0)["ok"],"sync begin")
	check(replica.receive(packets[0],0)["ok"],"bounded begin")
	check(replica.receive(packets[1],0)["ok"] and replica.receive(packets[1],0)["ok"],"identical duplicate idempotent")
	check(replica.store.count() == 0,"no partial publish")
	for packet: Dictionary in packets.slice(2): check(replica.receive(packet,0).get("ok",false),"dense reassembly")
	check(replica.store.count() == 4096,"complete dense bucket atomic publish")
	check(replica.receive({"kind":"voxel_sync_complete","sync_id":1},0)["ok"] and replica.ready(),"explicit sync complete")
	var replacement: Array[Dictionary] = LfeVoxelProtocol.snapshot_packets(bucket,1,values,2,1)
	for packet: Dictionary in replacement: check(replica.receive(packet,0).get("ok",false),"replacement snapshot")
	check(replica.store.count() == 2,"omitted overrides removed")
	var empty: Array[Dictionary] = LfeVoxelProtocol.snapshot_packets(bucket,2,[],3,1)
	for packet: Dictionary in empty: check(replica.receive(packet,0).get("ok",false),"empty replacement")
	check(replica.store.count() == 0,"empty bucket restores base")
	var delta: Dictionary = {"kind":"voxel_delta_batch","bucket":[0,0,0],"from_revision":2,"to_revision":3,"edits":[{"position":[1,1,1],"block":"leyforge:air"}]}
	check(replica.receive(delta,0)["ok"],"contiguous delta")
	delta["from_revision"] = 5; delta["to_revision"] = 6
	var gap: Dictionary = replica.receive(delta,0)
	check(not gap["ok"] and gap.has("resync") and replica.revisions[bucket] == 3,"gap no partial publish")
	delta["from_revision"] = 3; delta["to_revision"] = 4
	delta["edits"][0]["block"] = String(catalog.canonical_id_for_voxel_id(generator.sample_voxel_id(Vector3i.ONE)))
	check(replica.receive(delta,0)["ok"] and replica.store.count() == 0,"delta base restoration removes sparse entry")
	for fault: String in ["hash","missing","conflict","malformed"]:
		var candidate: LfeVoxelReplica = _replica()
		candidate.begin_sync(1,1)
		var bad: Array[Dictionary] = LfeVoxelProtocol.snapshot_packets(bucket,1,values,1,1)
		if fault == "hash": bad[0]["hash"] = "0".repeat(64)
		candidate.receive(bad[0],0)
		if fault != "missing":
			candidate.receive(bad[1],0)
			if fault == "conflict":
				var conflict: Dictionary = bad[1].duplicate(true); conflict["entries"][0]["block"] = "leyforge:dirt"
				check(candidate.receive(conflict,0).has("resync"),"conflicting duplicate rejected")
			if fault == "malformed":
				var malformed: Dictionary = bad[1].duplicate(true); malformed["entries"][0]["position"] = [16,0,0]
				check(candidate.receive(malformed,0).has("resync"),"wrong bucket part rejected")
		var result: Dictionary = candidate.receive(bad[-1],0)
		check(not result["ok"] and candidate.store.count() == 0,"corrupt/missing snapshot never publishes "+fault)
	var timeout: LfeVoxelReplica = _replica(); timeout.begin_sync(1,1)
	timeout.receive(packets[0],0)
	check(timeout.expire(6).size() == 1 and timeout.transfers.is_empty(),"bounded transfer timeout")
	var action: Dictionary = {"kind":"voxel_harvest_state","action_sequence":1,"active":true,"target_cell":[1,1,1],"expected_block":"leyforge:dirt"}
	check(LfeVoxelProtocol.valid(action,catalog),"exact intent")
	for field: String in ["actor","player_id","resulting_block","position","progress","tool","drops"]:
		var bad: Dictionary = action.duplicate(true); bad[field] = "forged"
		check(not LfeVoxelProtocol.valid(bad,catalog),"authority smuggling "+field)
	for value: Variant in [true,"1",1.5,INF,NAN,2147483648,-1]:
		var bad: Dictionary = action.duplicate(true); bad["action_sequence"] = value
		check(not LfeVoxelProtocol.valid(bad,catalog),"sequence finite/bounds")
	for value: Variant in [[0,0],[0,0,0,0],[0,1.1,0],[0,INF,0],[0,1073741824,0],[true,0,0]]:
		var bad: Dictionary = action.duplicate(true); bad["target_cell"] = value
		check(not LfeVoxelProtocol.valid(bad,catalog),"coordinate shape/bound")
	action["expected_block"] = "leyforge:unknown"
	check(not LfeVoxelProtocol.valid(action,catalog),"unknown canonical block")
	for bytes: PackedByteArray in ["x".repeat(1201).to_utf8_buffer(),PackedByteArray([255,254]),"{bad".to_utf8_buffer(),var_to_bytes_with_objects(RefCounted.new())]:
		check(LfeVoxelProtocol.decode(bytes,catalog).is_empty(),"no object or oversized/malformed decoding")
	var network: LeyforgeVoxelNetwork = LeyforgeVoxelNetwork.new()
	check(network.relevant_bucket(Vector3i.ZERO,Vector3(100,0,0)),"interest AABB prefetch")
	check(not network.relevant_bucket(Vector3i.ZERO,Vector3(200,0,0)),"no full world broadcast")
	network.replica.transfers[1] = {"bucket":[0,0,0]}
	check(not network.local_region_ready(Vector3.ONE),"near incomplete bucket pauses local controls")
	check(network.local_region_ready(Vector3(100,0,0)),"far snapshot never pauses local controls")
	network.replica.transfers.clear()
	network.pending_resync[Vector3i.ZERO] = true
	check(not network.local_region_ready(Vector3.ONE),"near gap resync waits for collision state")
	network.pending_resync.clear()
	network.dirty_cells[Vector3i.ONE] = true
	check(not network.local_region_ready(Vector3.ONE),"unapplied near loaded cell keeps local controls gated")
	network.dirty_cells.clear()
	check(network.local_region_ready(Vector3.ONE),"local controls recover after atomic application")
	var bounded: LfeVoxelReplica = _replica()
	bounded.begin_sync(1,1)
	for index: int in LfeVoxelProtocol.MAX_BUCKETS: bounded.revisions[Vector3i(index+1,0,0)] = 0
	var bounded_result: Dictionary
	for packet: Dictionary in LfeVoxelProtocol.snapshot_packets(Vector3i.ZERO,0,[],1,1): bounded_result = bounded.receive(packet,0)
	check(bounded_result.get("fatal",false) and bounded.store.count() == 0,"receiver cache limit closes without publishing partial state")
	network.free()
	var hello: Dictionary = LfeCompatibilityManifest.hello("1".repeat(32),LfeCompatibilityManifest.fingerprint())
	var world: Dictionary = {"world_id":"fixture","seed":184552221,"worldgen_version":2,"save_version":4,"content_version":1,"content_hash":hello["content_hash"],"network_protocol_version":3}
	var old: Dictionary = hello.duplicate(true); old["network_protocol_version"] = 2
	check(LfeCompatibilityManifest.validate_hello(old,hello,world) == "protocol_mismatch","W5.3 rejects as protocol_mismatch")
	check(LfeCompatibilityManifest.PROTOCOL == 3 and LfeWorldSave.SAVE_VERSION == 4 and LfeWorldSave.CONTENT_VERSION == 1 and LfeWorldSave.WORLDGEN_VERSION == 2,"version boundary")
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"largest_snapshot_part":maximum},"\t"))
	print("W5_4_FOCUSED_%s checks=%d" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)

func _replica() -> LfeVoxelReplica:
	var replica: LfeVoxelReplica = LfeVoxelReplica.new()
	replica.catalog = catalog
	replica.generator = generator
	return replica
