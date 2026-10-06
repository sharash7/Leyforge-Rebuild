extends SceneTree

var checks: int = 0
var failures: Array[String] = []
var output: String
const A: String = "11111111111111111111111111111111"
const B: String = "22222222222222222222222222222222"
const C: String = "33333333333333333333333333333333"

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var biology: LfeCharacterSurvival = LfeCharacterSurvival.new()
	var packet: Dictionary = LfeSurvivalProtocol.view(biology,1,1,false,false)
	check(LfeSurvivalProtocol.valid(packet),"exact canonical owner view")
	for key: String in packet:
		var bad: Dictionary = packet.duplicate(true); bad.erase(key)
		check(not LfeSurvivalProtocol.valid(bad),"missing "+key)
	for key: String in LfeCharacterSurvival.KEYS:
		for value: Variant in [NAN,INF,-INF,-1,101,true,"100",null]:
			var bad: Dictionary = packet.duplicate(true); bad[key] = value
			check(not LfeSurvivalProtocol.valid(bad),"bounded finite "+key)
	for key: String in ["alive","thirst_enabled","sheltered","resting"]:
		var bad: Dictionary = packet.duplicate(true); bad[key] = 1
		check(not LfeSurvivalProtocol.valid(bad),"strict bool "+key)
	for key: String in ["revision","mutation_revision"]:
		for value: Variant in [0,-1,1.5,2147483648,true,"1"]:
			var bad: Dictionary = packet.duplicate(true); bad[key] = value
			check(not LfeSurvivalProtocol.valid(bad),"bounded revision "+key)
	var bad: Dictionary = packet.duplicate(true); bad["player_id"] = B
	check(not LfeSurvivalProtocol.valid(bad),"foreign owner queries/state rejected")
	check(not LfeSurvivalProtocol.valid({"kind":"survival_resync","player_id":B}),"resync cannot query another actor")
	for data: PackedByteArray in ["bad".to_utf8_buffer(),"x".repeat(1025).to_utf8_buffer(),PackedByteArray([255,254])]:
		check(LfeSurvivalProtocol.decode(data).is_empty(),"malformed bytes rejected")
	var replica: LfeSurvivalReplica = LfeSurvivalReplica.new()
	check(not replica.ready() and not replica.can_sprint(),"no invented initial values")
	check(replica.receive(packet,0),"reliable initial bootstrap")
	packet["revision"] = 8; packet["hunger"] = 73
	check(replica.receive(packet,1),"loss converges complete replacement")
	packet["revision"] = 7; packet["hunger"] = 100
	check(not replica.receive(packet,2) and replica.snapshot()["hunger"] == 73,"out-of-order state rejected")
	packet["revision"] = 8
	check(not replica.receive(packet,2),"duplicate rejected")
	var unbooted: LfeSurvivalReplica = LfeSurvivalReplica.new()
	var periodic: Dictionary = packet.duplicate(true); periodic["kind"] = "survival_snapshot"
	check(not unbooted.receive(periodic,1) and not unbooted.ready(),"unreliable packet cannot replace reliable initial barrier")
	var exposed: Dictionary = replica.snapshot(); exposed["health"] = 0
	check(replica.snapshot()["health"] == 100,"no mutable view object exposure")
	var catalog: LfeBlockCatalog = LfeBlockCatalog.new(); check(catalog.load_default() == OK,"canonical content")
	var inv: LfeInventory = LfeInventory.new(catalog)
	check(LfeItemTransactions.add(inv,&"leyforge:provisions",3) == 3,"provisions fixture")
	check(not biology.consume(inv,0) and inv.total(&"leyforge:provisions") == 3,"full hunger no-op conserves items")
	var state: Dictionary = biology.snapshot(); state["hunger"] = 50; state["health"] = 61
	biology.restore(state)
	check(biology.consume(inv,0) and biology.snapshot()["hunger"] == 80 and biology.snapshot()["health"] == 61 and inv.total(&"leyforge:provisions") == 2,"canonical atomic +30 food without instant health")
	LfeItemTransactions.add(inv,&"leyforge:drinking_water",2)
	state = biology.snapshot(); state["thirst"] = 40; biology.restore(state)
	check(not biology.consume(inv,1) and inv.total(&"leyforge:drinking_water") == 2 and biology.snapshot()["thirst"] == 40,"Standard water no-op retains stored thirst")
	biology.configure_profile("Harsh")
	check(biology.consume(inv,1) and biology.snapshot()["thirst"] > 40 and inv.total(&"leyforge:drinking_water") == 1,"Harsh hydration canonical")
	check(LfeSurvivalProtocol.view(biology,1,1,false,false)["thirst_enabled"],"Harsh owner HUD hydration")
	check(LeyforgeMovementRules.fall_damage(12) == 0 and LeyforgeMovementRules.fall_damage(16) == 12 and LeyforgeMovementRules.fall_damage(100) == 100,"one Wave-4 fall formula")
	var authority: LfeGameplayAuthority = LfeGameplayAuthority.new()
	authority._catalog = catalog; authority.world_resources = LfeWorldResourceState.new(catalog); authority.creation = LfeCreationState.new(catalog)
	for actor: String in [A,B,C]: authority.add_character(actor,Vector3.ZERO)
	var ledger: LfeResourceTransactions = LfeResourceTransactions.new(); ledger.configure(authority,catalog,Callable())
	ledger.survival_revision = func(_actor: String)->int:return 1
	LfeItemTransactions.add(authority.character(B).resources.inventory,&"leyforge:provisions",3)
	state = authority.character(B).survival.snapshot(); state["hunger"] = 45; authority.character(B).survival.restore(state)
	ledger.observe()
	var request: Dictionary = {"kind":"resource_request","sequence":1,"transaction_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","operation":"consume","args":{"slot":0,"expected":authority.character(B).resources.inventory.stack_at(0),"survival_revision":1},"expected_revisions":{"player/"+B:ledger.revisions["player/"+B]}}
	check(ledger.execute(2,B,request,1)["success"],"consume existing ledger commits")
	check(ledger.execute(2,B,request,2)["success"] and authority.character(B).resources.total(&"leyforge:provisions") == 2 and authority.character(B).survival.snapshot()["hunger"] == 75,"retry one effect/item")
	request["args"]["slot"] = 1
	check(not ledger.execute(2,B,request,3)["success"],"changed payload same transaction rejected")
	check(authority.character(A).survival.snapshot()["hunger"] == 100 and authority.character(C).survival.snapshot()["hunger"] == 100,"third identity survival independence")
	var before_stale: Dictionary = authority.character(B).snapshot()
	request["transaction_id"] = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"; request["sequence"] = 2
	request["args"]["slot"] = 0; request["args"]["expected"]["quantity"] = 9
	request["expected_revisions"]["player/"+B] = ledger.revisions["player/"+B]
	check(not ledger.execute(2,B,request,4)["success"] and authority.character(B).snapshot() == before_stale,"stale stack consumes no unrelated item/effect")
	request["transaction_id"] = "cccccccccccccccccccccccccccccccc"; request["sequence"] = 3
	request["args"]["expected"] = authority.character(B).resources.inventory.stack_at(0)
	request["args"]["survival_revision"] = 2
	check(not ledger.execute(2,B,request,5)["success"] and authority.character(B).snapshot() == before_stale,"stale survival mutation revision rejects")
	for field: String in ["damage","health","alive","sheltered","resting"]:
		var spoof: Dictionary = request.duplicate(true); spoof["args"][field] = 100
		check(not LfeResourceProtocol.request_valid(spoof,catalog),"no client biology mutation: "+field)
	var saved: Dictionary = authority.character(B).snapshot()
	var restored: LfePlayerCharacter = LfePlayerCharacter.new(B,catalog)
	check(restored.restore(saved) and restored.snapshot() == saved,"save-v4 biology timing exact restore")
	var remote_body: LeyforgeAuthoritativePlayerBody = LeyforgeAuthoritativePlayerBody.new()
	var intent: Dictionary = LfeMovementProtocol.input(1,{"move":Vector2(0,-1),"jump":true,"sprint":true,"yaw":0.0,"pitch":0.0})
	check(remote_body.accept_input(intent),"bound remote input initially accepted")
	remote_body.reset_input(); intent["sequence"] = 2
	check(not remote_body.accept_input(intent) and remote_body.intent.is_empty() and not remote_body.jump_pending,"old input epoch cannot cross recovery fence")
	intent["input_epoch"] = 2
	check(remote_body.accept_input(intent),"fresh recovery epoch resumes normal play")
	remote_body.free()
	var equal_a: LfeCharacterSurvival = LfeCharacterSurvival.new()
	var equal_b: LfeCharacterSurvival = LfeCharacterSurvival.new()
	for step: int in 40:
		equal_a.advance(0.1,false,false,true); equal_b.advance(0.1,false,false,true)
	check(equal_a.snapshot() == equal_b.snapshot(),"identical active biology advances identically")
	var still: LfeCharacterSurvival = LfeCharacterSurvival.new(); still.advance(4,false,false,false)
	check(still.snapshot()["stamina"] == 100 and equal_a.snapshot()["stamina"] < 53,"activity-specific stamina divergence")
	authority.character(B).survival.damage(100); authority.execute(B,"recover",{"spawn":Vector3.ONE})
	check(authority.character(B).survival.snapshot()["health"] == 50 and authority.character(B).survival.snapshot()["stamina"] == 50 and authority.character(B).resources.snapshot() == saved["resources"],"recovery 50/50 without inventory loss")
	for count: int in [1,2,3]:
		var world: LfeCreationState = LfeCreationState.new(catalog)
		for step: int in 100:
			world.advance(0.1)
			for actor: int in count: LfeCharacterSurvival.new().advance(0.1,false,false,false)
		check(is_equal_approx(float(world.snapshot()["elapsed"]),10),"world clock once with "+str(count))
	check(LfeCompatibilityManifest.PROTOCOL == 5 and LfeWorldSave.SAVE_VERSION == 4 and LfeWorldSave.CONTENT_VERSION == 1 and LfeWorldSave.WORLDGEN_VERSION == 2,"version boundary")
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"packet_bytes":LfeSurvivalProtocol.encode(packet).size()},"\t")); file = null
	for failure: String in failures: push_error(failure)
	print("W5_6_FOCUSED checks=%d failures=%d" % [checks,failures.size()]); quit(0 if failures.is_empty() else 1)
