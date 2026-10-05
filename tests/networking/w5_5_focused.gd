extends SceneTree

var catalog: LfeBlockCatalog
var authority: LfeGameplayAuthority
var router: LfeResourceTransactions
var checks: int = 0
var failures: Array = []
var trace: Array = []
var seqs: Dictionary = {}
var now: float = 0.0
var a: String = "a".repeat(32)
var b: String = "b".repeat(32)
var output: String
var fixture: String

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func request(actor: String, op: String, args: Dictionary, id: String = "") -> Dictionary:
	router.observe()
	seqs[actor] = int(seqs.get(actor,0))+1
	var expected: Dictionary = {}
	for key: String in router.required(actor,op,args): expected[key] = int(router.revisions.get(key,0))
	return {"kind":"resource_request","sequence":seqs[actor],"transaction_id":Crypto.new().generate_random_bytes(16).hex_encode() if id.is_empty() else id,"operation":op,"args":args,"expected_revisions":expected}
func run(actor: String, p: Dictionary, peer: int = 0) -> Dictionary:
	now += 1.0
	var r: Dictionary = router.execute((2 if actor == a else 3) if peer == 0 else peer,actor,p,now)
	trace.append({"operation":p["operation"],"id":p["transaction_id"],"result":r,"commits":router.commits})
	return r
func adapter(actor: String, op: String, args: Dictionary, _time: float) -> LfeCommandResult:
	if op == "drop":
		var transformed: Dictionary = args.duplicate(true); transformed["position"] = Vector3.ZERO
		return authority.execute(actor,op,transformed)
	if op == "pickup": return authority.execute(actor,op,args)
	return LfeCommandResult.rejected("invalid_target")
func audit() -> bool:
	var slots: Array = []
	for s: Dictionary in router.streams().values():
		if s.has("inventory"): slots.append_array(s["inventory"]); slots.append_array(s["equipment"])
		if s.has("slots"): slots.append_array(s["slots"])
		if s.has("stack"): slots.append(s["stack"])
		if s.has("station"):
			for part: String in ["input","fuel","output"]: slots.append_array(s["station"][part])
	return LfeWorldResourceState.unique_instances(slots)
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--fixture="): fixture = arg.trim_prefix("--fixture=")
	catalog = LfeBlockCatalog.new(); check(catalog.load_default() == OK,"catalog")
	var save: LfeWorldSave = LfeWorldSave.new()
	check(save.open_world("resource-proof",184552221,true,catalog,fixture,a) == OK,"v4 fixture")
	authority = LfeGameplayAuthority.new(); check(authority.configure(save,catalog),"authority")
	authority.add_character(a,Vector3.ZERO)
	authority.add_character(b,Vector3.ZERO)
	router = LfeResourceTransactions.new(); router.configure(authority,catalog,adapter)
	check(LfeCompatibilityManifest.PROTOCOL == 4 and LfeWorldSave.SAVE_VERSION == 4 and LfeWorldSave.CONTENT_VERSION == 1 and LfeWorldSave.WORLDGEN_VERSION == 2,"version boundary")
	LfeItemTransactions.add(authority.character(a).resources.inventory,&"leyforge:dirt",12)
	var total: int = authority.total(&"leyforge:dirt")
	var p: Dictionary = request(a,"drop",{"slot":0,"quantity":3,"expected":authority.character(a).resources.inventory.stack_at(0)})
	check(LfeResourceProtocol.normalized(LfeResourceProtocol.decode(LfeResourceProtocol.encode(p,catalog),catalog)) == LfeResourceProtocol.normalized(p),"strict round trip")
	var first: Dictionary = run(a,p)
	check(first.get("success",false),"drop commit")
	var committed: int = router.commits
	for i: int in 16: check(run(a,p) == first and router.commits == committed,"duplicate drop commits once")
	var changed: Dictionary = p.duplicate(true); changed["args"]["quantity"] = 2
	check(not run(a,changed)["success"],"same id conflicting payload")
	check(not run(b,p)["success"],"foreign id cannot impersonate owner")
	var drop_id: String = first["data"]["drop_id"]
	var pa: Dictionary = request(a,"pickup",{"target":drop_id})
	var pb: Dictionary = request(b,"pickup",{"target":drop_id})
	check(run(b,pb)["success"] and not run(a,pa)["success"],"same-drop contention exactly once")
	check(run(b,pb)["success"] and authority.character(b).resources.inventory.total(&"leyforge:dirt") == 3,"pickup retry no second transfer")
	check(authority.total(&"leyforge:dirt") == total and authority.world_resources.drop(drop_id).is_empty(),"pickup/drop conservation")
	# Retry after disconnect/reconnect returns cached result in a new peer sequence.
	router.leave(3,b)
	pb["sequence"] = 1
	check(run(b,pb,4)["success"] and authority.character(b).resources.inventory.total(&"leyforge:dirt") == 3,"lost result across reconnect retained")
	var crate: String = authority.world_resources.ensure_crate(Vector3.ZERO)
	LfeItemTransactions.add(authority.world_resources.storage_inventory(crate),&"leyforge:wooden_pickaxe",1)
	var tool: Dictionary = authority.world_resources.storage_inventory(crate).stack_at(0)
	pa = request(a,"transfer",{"source":"storage/"+crate,"destination":"inventory","source_slot":0,"destination_slot":-1,"quantity":1,"expected":tool})
	pb = request(b,"transfer",pa["args"])
	check(run(a,pa)["success"] and not run(b,pb)["success"],"same-stateful-storage contention")
	check(audit(),"stateful identity globally unique")
	var wrong: Dictionary = request(a,"select",{"slot":0}); wrong["args"]["actor"] = b
	check(not LfeResourceProtocol.request_valid(wrong,catalog),"fake actor field rejected")
	var malformed: Dictionary = request(a,"select",{"slot":-1})
	check(not LfeResourceProtocol.request_valid(malformed,catalog),"negative slot")
	for field: String in p:
		var bad: Dictionary = p.duplicate(true); bad.erase(field)
		check(not LfeResourceProtocol.request_valid(bad,catalog),"missing envelope "+field)
	for value: Variant in [-1,0,1.5,"1",null,2147483648]:
		var bad: Dictionary = p.duplicate(true); bad["sequence"] = value
		check(not LfeResourceProtocol.request_valid(bad,catalog),"malformed sequence")
	var replay: Dictionary = request(a,"select",{"slot":1}); replay["sequence"] = 1
	check(not run(a,replay)["success"],"stale conflicting sequence")
	var leap: Dictionary = request(a,"select",{"slot":1}); leap["sequence"] = 1000000
	check(not run(a,leap)["success"],"sequence jump")
	var opened: Dictionary = run(a,request(a,"open_context",{"target":""}))
	check(opened["success"],"personal grid authority")
	LfeItemTransactions.add(authority.character(a).resources.inventory,&"leyforge:oak_planks",1)
	var plank_slot: int = -1
	for slot: int in 27:
		if authority.character(a).resources.inventory.stack_at(slot).get("content") == "leyforge:oak_planks": plank_slot = slot
	var grid: LfeCraftingGrid = authority._grids[a]
	pa = request(a,"transfer",{"source":"inventory","destination":"grid","source_slot":plank_slot,"destination_slot":0,"quantity":1,"expected":authority.character(a).resources.inventory.stack_at(plank_slot)})
	check(run(a,pa)["success"],"grid staging conserved transfer")
	pa = request(a,"craft",{"recipe":"leyforge:split_oak_sticks"})
	first = run(a,pa); committed = router.commits
	check(first["success"] and authority.character(a).resources.inventory.total(&"leyforge:oak_stick") == 4,"canonical crafting transformation")
	check(run(a,pa) == first and router.commits == committed and authority.character(a).resources.inventory.total(&"leyforge:oak_stick") == 4,"duplicate craft at most once")
	LfeItemTransactions.add(grid.inventory,&"leyforge:oak_heartwood",1)
	router.leave(2,a)
	check(not authority._grids.has(a) and authority.character(a).resources.inventory.total(&"leyforge:oak_heartwood") == 1,"disconnect returns staging")
	# Shared kiln process/output races use the same inventory transaction path.
	authority.creation.add_object(&"leyforge:kiln",Vector3i.ZERO,0)
	var kiln: String = authority.creation.object_at(Vector3i.ZERO)
	var station: LfeWorkstation = authority.creation.station(kiln)
	LfeItemTransactions.add(station.input,&"leyforge:oak_heartwood",2)
	LfeItemTransactions.add(station.fuel,&"leyforge:oak_heartwood",1)
	pa = request(a,"start_process",{"target":kiln,"recipe":"leyforge:charcoal_burn"})
	pb = request(b,"start_process",pa["args"])
	check(run(a,pa)["success"] and not run(b,pb)["success"],"kiln start once")
	station.advance(8)
	pa = request(a,"transfer",{"source":"station/"+kiln+"/output","destination":"inventory","source_slot":0,"destination_slot":-1,"quantity":2,"expected":station.output.stack_at(0)})
	pb = request(b,"transfer",pa["args"])
	check(run(a,pa)["success"] and not run(b,pb)["success"] and authority.total(&"leyforge:charcoal") == 2,"kiln output contention")
	check(audit(),"identities after kiln")
	# Canonical finite-source primitive is the final shared commit after held-work validation.
	authority.creation.initialize_sources(184552221,2)
	var source_id: String = ""
	for source: Dictionary in authority.creation.sources():
		if source["source"] == "trail_water": source_id = source["instance"]; break
	check(authority.creation.harvest_source(source_id,authority.character(a).resources,authority.character(a).survival),"finite source first canonical output")
	check(not authority.creation.harvest_source(source_id,authority.character(b).resources,authority.character(b).survival) and authority.total(&"leyforge:drinking_water") == 4,"finite source second actor no duplicate output")
	# Full backpack on disconnect retains staging; later close can release it intact.
	var packed: Array = []
	for slot: int in 27: packed.append({"content":"leyforge:dirt","quantity":64})
	var old_personal: Dictionary = authority.character(a).resources.snapshot()
	authority.character(a).resources.inventory.restore(packed)
	var retained: LfeCraftingGrid = authority.open_grid(a)
	LfeItemTransactions.add(retained.inventory,&"leyforge:oak_planks",1)
	router.leave(2,a)
	check(authority._grids.has(a) and retained.inventory.total(&"leyforge:oak_planks") == 1,"full backpack disconnect safely retains staging")
	authority.character(a).resources.restore(old_personal)
	check(authority.execute(a,"close_grid").success and not authority._grids.has(a),"retained staging later releases without loss")
	# Full replacement never exposes partial or malformed inventory state.
	var replica: LfeResourceReplica = LfeResourceReplica.new(); replica.configure(catalog,a)
	var state: Dictionary = authority.character(a).resources.snapshot()
	for slot: int in 27:
		if state["inventory"][slot] == null: state["inventory"][slot] = LfeItemInstance.create(&"leyforge:wooden_pickaxe",catalog)
	var key: String = "player/"+a
	var packets: Array[Dictionary] = LfeResourceProtocol.parts(key,1,state)
	var largest: int = 0
	for packet: Dictionary in packets:
		var bytes: PackedByteArray = LfeResourceProtocol.encode(packet,catalog)
		largest = maxi(largest,bytes.size())
		check(not bytes.is_empty() and bytes.size() <= 1300,"bounded snapshot parts")
		check(replica.receive(LfeResourceProtocol.decode(bytes,catalog),0)["ok"],"fragment applies")
	check(not replica.ready,"no readiness claim before complete relevant snapshot barrier")
	check(replica.receive({"kind":"resource_ready","count":1,"hash":LfeResourceProtocol.normalized(replica.revisions).sha256_text()},0)["ok"] and replica.ready and replica.personal.snapshot() == state,"personal snapshot exact")
	var duplicated: LfeResourceReplica = LfeResourceReplica.new(); duplicated.configure(catalog,a)
	for packet: Dictionary in LfeResourceProtocol.parts(key,1,state): duplicated.receive(packet,0)
	var other_slots: Array = []; other_slots.resize(9)
	other_slots[0] = state["inventory"].filter(func(v: Variant)->bool: return v != null and v.has("instance"))[0].duplicate(true)
	var storage_key: String = "storage/"+"c".repeat(32)
	for packet: Dictionary in LfeResourceProtocol.parts(storage_key,1,{"instance":"c".repeat(32),"content":"leyforge:storage_crate","position":[0,0,0],"slots":other_slots}): duplicated.receive(packet,0)
	check(duplicated.receive({"kind":"resource_ready","count":2,"hash":LfeResourceProtocol.normalized(duplicated.revisions).sha256_text()},0).get("fatal",false) and not duplicated.ready,"cross-domain duplicate snapshot cannot expose ready UI")
	var bad_state: Dictionary = state.duplicate(true); bad_state["inventory"][0] = {"content":"unknown:item","quantity":1}
	check(not replica.valid_state(key,bad_state),"unknown content snapshot")
	bad_state = state.duplicate(true); bad_state["inventory"].pop_back()
	check(not replica.valid_state(key,bad_state),"slot count")
	var tools: Array = [tool.duplicate(true),tool.duplicate(true)]
	bad_state = state.duplicate(true); bad_state["inventory"][0] = tools[0]; bad_state["inventory"][1] = tools[1]
	check(not replica.valid_state(key,bad_state),"duplicate tool snapshot")
	bad_state = state.duplicate(true); bad_state["inventory"][0] = tool.duplicate(true); bad_state["inventory"][0]["durability"] = -1
	check(not replica.valid_state(key,bad_state),"invalid durability")
	packets = LfeResourceProtocol.parts(key,3,state,2)
	check(replica.receive(packets[0],0).has("resync") and replica.revisions[key] == 1,"revision gap requests resync")
	packets = LfeResourceProtocol.parts(key,2,state)
	var corrupt: Dictionary = packets[0].duplicate(true); corrupt["hash"] = "0".repeat(64)
	replica.receive(corrupt,0)
	if packets.size() > 1:
		check(replica.receive(packets[1],0).has("resync"),"conflicting hash metadata")
		replica.receive(packets[0],0)
		var conflict: Dictionary = packets[0].duplicate(true); conflict["bytes"] = "00"
		check(replica.receive(conflict,0).has("resync"),"conflicting duplicate part")
	replica.receive(packets[0],0)
	check(replica.expire(6).size() == 1 and replica.revisions[key] == 1,"missing part expiry no publication")
	var fresh: LfeResourceReplica = LfeResourceReplica.new(); fresh.configure(catalog,a)
	for packet: Dictionary in LfeResourceProtocol.parts(key,1,state):
		packet["hash"] = "0".repeat(64)
		fresh.receive(packet,0)
	check(not fresh.ready and fresh.states.is_empty(),"corrupted hash never publishes")
	# Burst limits and retention are bounded independently of UI.
	var hits: int = 0
	for i: int in 25:
		pa = request(a,"select",{"slot":i%9})
		if router.execute(99,a,pa,1000).get("reason") == "rate_limited": hits += 1
	check(hits > 0,"rate limit burst")
	for i: int in 270: run(b,request(b,"select",{"slot":i%9}))
	check(router.completed[b].size() == 256,"completed-result retention bound")
	check(audit(),"final global instance uniqueness")
	authority.creation.initialize_sources(184552221,2)
	save.record_voxel_edit(Vector3i.ZERO,catalog.get_voxel_id(&"leyforge:kiln"),catalog.get_voxel_id(&"leyforge:air"))
	check(save.save(authority.players_snapshot(),authority.world_resources.snapshot(),authority.creation.snapshot()) == OK,"save v4 resources")
	var reopened: LfeWorldSave = LfeWorldSave.new()
	check(reopened.open_world("resource-proof",184552221,true,catalog,fixture,a) == OK and LfeResourceProtocol.normalized(reopened.players_state) == LfeResourceProtocol.normalized(authority.players_snapshot()),"save/reload exact resources")
	var report: Dictionary = {"passed":failures.is_empty(),"checks":checks,"failures":failures,"trace":trace,"largest_part":largest,"retention":router.completed[b].size()}
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file = null
	print("W5_5_FOCUSED checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
