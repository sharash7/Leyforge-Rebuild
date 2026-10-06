extends SceneTree

var _checks: int = 0
var _failures: Array[String] = []
var _out: String = ""
var _root: String = ""
var _catalog: LfeBlockCatalog
var _recipes: LfeRecipeCatalog

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--wave4-test-root="):
			_root = argument.trim_prefix("--wave4-test-root=")
		if argument.begins_with("--wave4-test-out="):
			_out = argument.trim_prefix("--wave4-test-out=")
	if not _root.is_absolute_path() or not _out.is_absolute_path():
		quit(1)
		return
	_catalog = LfeBlockCatalog.new()
	_check(_catalog.load_default() == OK,"Production canonical catalog validates")
	_recipes = LfeRecipeCatalog.new()
	_check(_recipes.load_default(_catalog),"Every canonical recipe/reference validates")
	_tools()
	_crafting()
	_grid_matching()
	_processing()
	_starter_progression()
	_drop_clustering()
	_survival()
	_state()
	_persistence()
	_voxel_trees()
	_grounded_drops()
	_dense_stone_presentation()
	await _held_gathering()
	var report: Dictionary = {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures,"runner":Engine.get_version_info()["string"],"property_seed":928143,"property_steps":300}
	_write(_out.path_join("focused.json"),JSON.stringify(report,"\t",true,true))
	for failure: String in _failures:
		push_error("Wave 4: " + failure)
	print("WAVE_4_TEST_%s checks=%d" % ["PASS" if _failures.is_empty() else "FAIL",_checks])
	quit(0 if _failures.is_empty() else 1)

func _tools() -> void:
	var r: LfeTestResourceView = LfeTestResourceView.new(_catalog)
	var manual: Dictionary = {"class":"mining","capability":0,"seconds":1.2}
	var restricted: Dictionary = {"class":"mining","capability":1,"seconds":1.2}
	_check(not LfeHarvestRules.evaluate(manual,{},_catalog).is_empty(),"Manual stone gathering remains possible")
	_check(LfeHarvestRules.evaluate(restricted,{},_catalog).is_empty(),"Capability blocks bare hands")
	for name: String in ["stone_pickaxe","stone_axe","stone_shovel","wooden_pickaxe","wooden_axe","wooden_shovel"]:
		var id: StringName = StringName("leyforge:"+name)
		_check(LfeItemTransactions.add(r.inventory,id,1)==1,"Canonical tool instance created")
		var slot: int = _slot(r.inventory,id)
		var stack: Dictionary = r.inventory.stack_at(slot)
		_check(LfeItemStack.valid(stack,_catalog,false) and int(stack["quantity"])==1,"Nonstackable explicit instance")
		_check(LfeItemTransactions.transfer(r.inventory,slot,r.equipment,1,0)==1,"Equip exact tool instance")
		var spec: Dictionary = _catalog.content_definition(id)["tool"]
		var rule: Dictionary = {"class":spec["class"],"capability":1,"seconds":1.2}
		var effect: Dictionary = LfeHarvestRules.evaluate(rule,r.equipment.stack_at(0),_catalog)
		_check(not effect.is_empty() and is_equal_approx(float(effect["seconds"]),1.2/float(spec["efficiency"])),"Class/capability/efficiency independent")
		var wrong: Dictionary = rule.duplicate();wrong["class"]="manual"
		_check(LfeHarvestRules.evaluate(wrong,stack,_catalog).is_empty(),"Wrong tool fails required capability")
		for use: int in int(spec["durability"]):
			_check(LfeHarvestRules.wear(r.personal,stack["instance"]),"Durability authorized use %d" % use)
		_check(int(r.equipment.stack_at(0)["durability"])==0 and not LfeHarvestRules.wear(r.personal,stack["instance"]),"Broken state bounded and unusable")
		_check(LfeHarvestRules.evaluate(rule,r.equipment.stack_at(0),_catalog).is_empty(),"Broken tool cannot meet capability")
		_check(LfeItemTransactions.transfer(r.equipment,0,r.inventory,1)==1,"Broken instance moves intact")
		slot = _slot(r.inventory,id)
		var drop: String = r.drop_from_inventory(slot,1,Vector3(1,20,1))
		var restored: LfeTestResourceView = LfeTestResourceView.new(_catalog)
		_check(restored.restore(r.snapshot()),"Damaged physical drop reload")
		_check(restored.pickup(drop)==1 and restored.inventory.stack_at(_slot(restored.inventory,id))["instance"]==stack["instance"] and restored.inventory.stack_at(_slot(restored.inventory,id))["durability"]==0,"Pickup preserves durability/identity")
		r = restored
	var valid: Dictionary = r.snapshot()
	var tool_slot: int = _slot(r.inventory,&"leyforge:stone_pickaxe")
	for value: Variant in [-1,25,0.5,"3",INF,NAN]:
		var bad: Dictionary = valid.duplicate(true)
		bad["inventory"][tool_slot]["durability"]=value
		_check(not r.restore(bad) and r.snapshot()==valid,"Malformed durability rollback")
	var duplicate: Dictionary = valid.duplicate(true)
	duplicate["inventory"][26]=duplicate["inventory"][tool_slot].duplicate(true)
	_check(not r.restore(duplicate),"Duplicate durable item identity rejected")
	var before: Dictionary = r.snapshot()
	_check(not r.break_to_drop(&"leyforge:stone",Vector3.ZERO,func() -> Error:return ERR_INVALID_DATA) and r.snapshot()==before,"Failed world action consumes no tool/resource")
	var outputs: Array = [{"content":"leyforge:stone","quantity":2},{"content":"leyforge:sand","quantity":1}]
	_check(r.break_to_drop(&"leyforge:stone",Vector3.ZERO,func() -> Error:return OK,outputs) and r.total(&"leyforge:stone")==2 and r.total(&"leyforge:sand")==1,"Harvest supports explicit multiple outputs and quantities")
	before = r.snapshot()
	_check(r.break_to_drop(&"leyforge:stone",Vector3.ZERO,func() -> Error:return OK,[]) and r.snapshot()==before,"Explicit no-output breaking creates no phantom drops")

func _crafting() -> void:
	var i: LfeInventory = LfeInventory.new(_catalog,4)
	LfeItemTransactions.add(i,&"leyforge:oak_heartwood",3)
	var before: Array = i.snapshot()
	_check(not _craft_test(i,_recipes,"unknown:recipe") and i.snapshot()==before,"Unknown craft rollback")
	_check(not _craft_test(i,_recipes,"leyforge:craft_stone_pickaxe") and i.snapshot()==before,"Insufficient ingredients rollback")
	_check(not _craft_test(i,_recipes,"leyforge:charcoal_burn") and i.snapshot()==before,"Hand context rejects process recipe")
	_check(_craft_test(i,_recipes,"leyforge:saw_planks") and i.total(&"leyforge:oak_heartwood")==2 and i.total(&"leyforge:oak_planks")==4,"Exact hand transformation")
	_check(_craft_test(i,_recipes,"leyforge:split_oak_sticks"),"Early stick transformation in grid")
	LfeItemTransactions.add(i,&"leyforge:stone",3)
	_check(_craft_test(i,_recipes,"leyforge:craft_stone_pickaxe") and i.total(&"leyforge:stone")==0 and i.total(&"leyforge:oak_planks")==3 and i.total(&"leyforge:oak_stick")==2,"Real starter tool chain")
	_check(i.stack_at(_slot(i,&"leyforge:stone_pickaxe")).has("instance"),"Craft creates stateful tool")
	var full: LfeInventory = LfeInventory.new(_catalog,1)
	LfeItemTransactions.add(full,&"leyforge:oak_heartwood",2)
	before=full.snapshot()
	_check(not _craft_test(full,_recipes,"leyforge:saw_planks") and full.snapshot()==before,"Output-capacity craft rollback after detached consumption")
	var random: RandomNumberGenerator = RandomNumberGenerator.new();random.seed=928143
	var inventory: LfeInventory = LfeInventory.new(_catalog,27)
	var storage: LfeInventory = LfeInventory.new(_catalog,9)
	LfeItemTransactions.add(inventory,&"leyforge:oak_heartwood",50)
	for n: int in 300:
		match random.randi_range(0,3):
			0:_craft_test(inventory,_recipes,"leyforge:saw_planks")
			1:LfeItemTransactions.transfer(inventory,random.randi_range(0,26),storage,1,-1,true)
			2:LfeItemTransactions.transfer(storage,random.randi_range(0,8),inventory,1,-1,true)
			3:LfeItemTransactions.transfer(inventory,random.randi_range(0,26),inventory,1,random.randi_range(0,26),true)
		_check(4*(inventory.total(&"leyforge:oak_heartwood")+storage.total(&"leyforge:oak_heartwood"))+inventory.total(&"leyforge:oak_planks")+storage.total(&"leyforge:oak_planks")==200,"Randomized transformation accounting %d" % n)
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/recipes/wave_4_recipes.json"))
	definitions["recipes"][0]["inputs"][0]["content"]="unknown:material"
	_write(_root.path_join("bad_recipes.json"),JSON.stringify(definitions))
	var bad: LfeRecipeCatalog = LfeRecipeCatalog.new()
	_check(not bad.load_path(_root.path_join("bad_recipes.json"),_catalog),"Unknown authoring reference rejected")

func _processing() -> void:
	var p: LfeWorkstation = LfeWorkstation.new(_catalog,_recipes)
	var before: Dictionary = p.snapshot()
	_check(not p.start("unknown:process") and p.snapshot()==before,"Invalid process rejected")
	LfeItemTransactions.add(p.input,&"leyforge:oak_heartwood",4)
	before=p.snapshot()
	_check(not p.start("leyforge:charcoal_burn") and p.snapshot()==before,"Insufficient fuel consumes zero input")
	LfeItemTransactions.add(p.fuel,&"leyforge:stone",1)
	before=p.snapshot()
	_check(not p.start("leyforge:charcoal_burn") and p.snapshot()==before,"Invalid fuel consumes nothing")
	LfeItemTransactions.remove(p.fuel,0,1)
	LfeItemTransactions.add(p.fuel,&"leyforge:oak_heartwood",2)
	_check(p.start("leyforge:charcoal_burn") and p.input.total(&"leyforge:oak_heartwood")==2 and p.fuel.total(&"leyforge:oak_heartwood")==1,"Start reserves exactly 2 input + 1 fuel")
	before=p.snapshot()
	_check(not p.start("leyforge:charcoal_burn") and p.snapshot()==before,"No double-start reservation")
	p.advance(3.25)
	var q: LfeWorkstation = LfeWorkstation.new(_catalog,_recipes)
	_check(q.restore(p.snapshot()) and q.snapshot()==p.snapshot(),"In-progress process roundtrip exact")
	_check(not q.advance(-1) and not q.advance(INF) and q.snapshot()==p.snapshot(),"Invalid simulation duration rollback")
	LfeItemTransactions.add(q.output,&"leyforge:stone",192)
	q.advance(8)
	_check(q.status()=="Output blocked" and q.snapshot()["active"]=="leyforge:charcoal_burn" and float(q.snapshot()["progress"])==8,"Blocked completion retains reserved output")
	LfeItemTransactions.remove(q.output,0,64)
	q.advance(0)
	_check(q.output.total(&"leyforge:charcoal")==2 and q.status()=="Idle","Unblocking publishes exact outputs once")
	q.advance(30)
	_check(q.output.total(&"leyforge:charcoal")==2,"No repeated completion duplication")
	var bad: Dictionary = p.snapshot();bad["progress"]=8.1
	_check(not q.restore(bad),"Impossible progress rejected")
	bad=p.snapshot();bad["active"]="unknown:process"
	_check(not q.restore(bad),"Unknown active process rejected")
	var partitioned: LfeWorkstation = LfeWorkstation.new(_catalog,_recipes)
	partitioned.restore(p.snapshot())
	for n: int in 19:partitioned.advance(0.25)
	p.advance(4.75)
	_check(p.snapshot()==partitioned.snapshot(),"Processing independent of time partition/frame rate")
	var full: LfeWorkstation = LfeWorkstation.new(_catalog,_recipes)
	LfeItemTransactions.add(full.input,&"leyforge:oak_heartwood",2)
	LfeItemTransactions.add(full.fuel,&"leyforge:oak_heartwood",1)
	LfeItemTransactions.add(full.output,&"leyforge:stone",192)
	before=full.snapshot()
	_check(not full.start("leyforge:charcoal_burn") and full.snapshot()==before,"Blocked start consumes zero input/fuel")

func _survival() -> void:
	var s: LfeCharacterSurvival = LfeCharacterSurvival.new()
	var i: LfeInventory = LfeInventory.new(_catalog,3)
	LfeItemTransactions.add(i,&"leyforge:provisions",2)
	LfeItemTransactions.add(i,&"leyforge:drinking_water",2)
	var initial: Dictionary = s.snapshot();var slots: Array = i.snapshot()
	_check(not s.consume(i,0) and i.snapshot()==slots and s.snapshot()==initial,"No-op food consumes zero")
	_check(s.profile_name=="Standard" and s.thirst_enabled(),"Owner repair: normal Standard hydration enabled")
	for minute: int in 60:s.advance(60,false,false,false)
	_check(is_equal_approx(float(s.snapshot()["hunger"]),96) and is_equal_approx(float(s.snapshot()["thirst"]),95) and s.snapshot()["fatigue"]==0 and is_equal_approx(float(s.snapshot()["exposure"]),30),"Owner repair Standard hour: hunger 4, thirst 5, exposure 30, routine fatigue zero")
	_check(s.consume(i,1) and i.total(&"leyforge:drinking_water")==1 and s.snapshot()["thirst"]==100,"Standard hydration consumes one and clamps at 100")
	LfeItemTransactions.add(i,&"leyforge:drinking_water",1)
	s.configure_profile("Peaceful")
	_check(not s.consume(i,1) and i.total(&"leyforge:drinking_water")==2,"Disabled Peaceful thirst retains water")
	s.configure_profile("Standard")
	_check(s.damage(20) and s.snapshot()["health"]==80,"Authoritative health damage")
	_check(not s.damage(-1) and not s.damage(INF),"Invalid damage rejected")
	s.advance(19,true,true,false)
	_check(s.snapshot()["health"]==80,"Standard health recovery waits 20 seconds")
	s.advance(2,true,true,false)
	_check(is_equal_approx(float(s.snapshot()["health"]),80.1),"Standard safe recovery 0.1 health/sec after delay")
	_check(s.exert(100) and not s.exert(1),"Stamina limits strenuous actions")
	s.advance(2,false,false,false)
	_check(s.snapshot()["stamina"]==0,"Depletion waits 2.25 seconds")
	s.advance(1,false,false,false)
	_check(is_equal_approx(float(s.snapshot()["stamina"]),12),"Stamina regen 16/sec after remaining delay")
	s.advance(1,false,false,true)
	_check(s.snapshot()["stamina"]==0 and float(s.snapshot()["fatigue"])>0,"Sprint costs representative 12/sec and strenuous fatigue")
	var fatigue: float = float(s.snapshot()["fatigue"])
	s.advance(1,true,true,false)
	_check(is_equal_approx(float(s.snapshot()["fatigue"]),maxf(0,fatigue-2.0/60)),"Owner repair sheltered rest reduction 2/min, bounded at zero")
	var before_health: float=float(s.snapshot()["health"])
	s.advance(1,false,false,false)
	_check(float(s.snapshot()["health"])>before_health,"Benign outdoor natural recovery does not require shelter")
	var health_before_food: float=float(s.snapshot()["health"])
	_check(s.consume(i,0) and s.snapshot()["health"]==health_before_food and s.snapshot()["hunger"]==100 and i.total(&"leyforge:provisions")==1,"Food transforms exactly one serving")
	var next: LfeCharacterSurvival = LfeCharacterSurvival.new()
	_check(next.restore(s.snapshot()) and next.snapshot()==s.snapshot(),"Values plus debt/delay persist exactly")
	var legacy: Dictionary = s.snapshot();legacy.erase("timing")
	_check(next.restore(legacy),"Existing six-field v3 survival remains readable")
	var unknown: Dictionary = legacy.duplicate(true);unknown["unexpected"] = 1
	var legacy_before: Dictionary = next.snapshot()
	_check(not next.restore(unknown) and next.snapshot()==legacy_before,"Unknown legacy survival field rejects atomically")
	for key: String in LfeCharacterSurvival.KEYS:
		for value: Variant in [-1,101,INF,NAN,"50"]:
			var before: Dictionary = next.snapshot();var bad: Dictionary = before.duplicate(true);bad[key]=value
			_check(not next.restore(bad) and next.snapshot()==before,"Malformed survival rollback "+key)
	var bad: Dictionary = next.snapshot();bad["timing"]["starvation"]=-1
	_check(not next.restore(bad),"Persistent debt cannot be malformed")
	var accelerated: LfeCharacterSurvival = LfeCharacterSurvival.new()
	_check(accelerated.configure_profile("Harsh") and accelerated.configure_test_rate(3600),"Explicit focused-only biological acceleration")
	accelerated.advance(1,false,false,false)
	_check(is_equal_approx(float(accelerated.snapshot()["hunger"]),94.6) and is_equal_approx(float(accelerated.snapshot()["thirst"]),94.5),"Accelerated hour keeps canonical profile rates")
	_check(accelerated.consume(i,1) and i.total(&"leyforge:drinking_water")==1,"Enabled hydration consumes exactly one")
	var starved: Dictionary = accelerated.snapshot();starved["health"]=1;starved["hunger"]=0;starved["thirst"]=100
	accelerated.restore(starved)
	accelerated.advance(6,false,false,false)
	_check(accelerated.snapshot()["health"]==1,"First six starvation hours have no direct damage")
	accelerated.advance(1,false,false,false)
	_check(is_equal_approx(float(accelerated.snapshot()["health"]),0.5),"Standard debt loss reference 0.5 health/hour after grace")
	accelerated.advance(2,false,false,false)
	_check(not accelerated.alive() and not accelerated.consume(i,0),"Prolonged debt eventually reaches zero health safely")
	accelerated.respawn()
	_check(accelerated.snapshot()["health"]==50,"Recovery retains existing no-resource-loss rule")
	for profile: String in ["Peaceful","Relaxed"]:
		var gentle: LfeCharacterSurvival = LfeCharacterSurvival.new();gentle.configure_profile(profile)
		var value: Dictionary=gentle.snapshot();value["hunger"]=0;value["timing"]["starvation"]=100000
		gentle.restore(value);gentle.advance(60,false,false,false)
		_check(gentle.snapshot()["health"]==100 and not gentle.thirst_enabled(),"Gentle preset has no starvation damage: "+profile)

func _starter_progression() -> void:
	var r: LfeTestResourceView = LfeTestResourceView.new(_catalog)
	var state: LfeTestCreationView = LfeTestCreationView.new(_catalog);state.initialize_sources(184552221)
	_check(r.inventory.snapshot().all(func(v: Variant)->bool:return v==null),"Starter fixture has no granted stone or tools")
	_check(state.harvest_source(state.sources()[0]["instance"],r),"Manual timber begins starter chain")
	_check(_craft_test(r.inventory,_recipes,"leyforge:saw_planks") and _craft_test(r.inventory,_recipes,"leyforge:split_oak_sticks"),"Timber components from canonical recipes")
	_check(_craft_test(r.inventory,_recipes,"leyforge:saw_planks"),"Enough planks for wooden tool")
	_check(_craft_test(r.inventory,_recipes,"leyforge:craft_wooden_pickaxe"),"Wood-only mining tool")
	LfeItemTransactions.transfer(r.inventory,_slot(r.inventory,&"leyforge:wooden_pickaxe"),r.equipment,1,0)
	var ordinary: Dictionary = _catalog.definition_for_id(&"leyforge:stone")["harvest"]
	_check(LfeHarvestRules.evaluate(ordinary,{},_catalog).is_empty(),"Manual action cannot mine ordinary stone")
	_check(not LfeHarvestRules.evaluate(ordinary,r.equipment.stack_at(0),_catalog).is_empty(),"Wooden capability mines ordinary stone")
	_check(not state.harvest_source(state.sources()[12]["instance"],r),"Wooden mining cannot access dense stone")
	_check(r.break_to_drop(&"leyforge:stone",Vector3.ZERO,func()->Error:return OK,ordinary["outputs"]),"Ordinary stone production conversion")
	r.pickup(r.drops()[0]["instance"])
	r.break_to_drop(&"leyforge:stone",Vector3.ZERO,func()->Error:return OK,ordinary["outputs"]);r.pickup(r.drops()[0]["instance"])
	r.break_to_drop(&"leyforge:stone",Vector3.ZERO,func()->Error:return OK,ordinary["outputs"]);r.pickup(r.drops()[0]["instance"])
	_check(_craft_test(r.inventory,_recipes,"leyforge:craft_stone_pickaxe"),"Ordinary stone enables stone pickaxe")
	LfeItemTransactions.transfer(r.equipment,0,r.inventory,1)
	LfeItemTransactions.transfer(r.inventory,_slot(r.inventory,&"leyforge:stone_pickaxe"),r.equipment,1,0)
	_check(state.harvest_source(state.sources()[12]["instance"],r),"Stone capability unlocks dense stone")
	for name: String in ["wooden_axe","wooden_shovel"]:
		_check(_catalog.content_definition(StringName("leyforge:"+name))["tool"]["capability"]==1,"Representative starter class "+name)

func _drop_clustering() -> void:
	var r: LfeTestResourceView = LfeTestResourceView.new(_catalog)
	LfeItemTransactions.add(r.inventory,&"leyforge:stone",67)
	var a: String=r.drop_from_inventory(0,63,Vector3(0,20,0))
	var b: String=r.drop_from_inventory(0,1,Vector3(0.2,20,0))
	var c: String=r.drop_from_inventory(1,3,Vector3(1.2,20,0))
	var before: Dictionary=r.snapshot()
	_check(not r.advance_drop_clusters(0.5,func(_p:Vector3)->bool:return false,func(_a:Vector3,_b:Vector3)->bool:return true) and r.snapshot()==before,"Unloaded drops never attract")
	_check(not r.advance_drop_clusters(0.5,func(_p:Vector3)->bool:return true,func(_a:Vector3,_b:Vector3)->bool:return false) and r.snapshot()==before,"Walls block attraction")
	for n: int in 80:r.advance_drop_clusters(0.5,func(_p:Vector3)->bool:return true,func(_a:Vector3,_b:Vector3)->bool:return true)
	_check(r.total(&"leyforge:stone")==67 and r.drops().size()==2 and r.drops().all(func(v:Dictionary)->bool:return int(v["stack"]["quantity"])<=64),"Convergence/partial merge preserves all 67 units and maxima")
	var restored: LfeTestResourceView=LfeTestResourceView.new(_catalog)
	_check(restored.restore(r.snapshot()) and restored.snapshot()==r.snapshot(),"Final logical positions/quantities persist exactly")
	LfeItemTransactions.add(r.inventory,&"leyforge:wooden_pickaxe",2)
	r.drop_from_inventory(_slot(r.inventory,&"leyforge:wooden_pickaxe"),1,Vector3(0,20,0))
	r.drop_from_inventory(_slot(r.inventory,&"leyforge:wooden_pickaxe"),1,Vector3(0.1,20,0))
	before=r.snapshot()
	r.advance_drop_clusters(1,func(_p:Vector3)->bool:return true,func(_a:Vector3,_b:Vector3)->bool:return true)
	_check(r.drops().filter(func(v:Dictionary)->bool:return v["stack"].has("instance")).size()==2 and r.total(&"leyforge:wooden_pickaxe")==2,"Different durable instances never merge")

func _state() -> void:
	var state: LfeTestCreationView=LfeTestCreationView.new(_catalog)
	var r: LfeTestResourceView=LfeTestResourceView.new(_catalog)
	_check(state.initialize_sources(184552221) and state.validate_source_layout(184552221),"Bounded deterministic production resource sources")
	var timber: Dictionary=state.sources()[0]
	_check(state.harvest_source(timber["instance"],r) and r.inventory.total(&"leyforge:oak_heartwood")==6,"Manual timber gathering exact outputs")
	var before: Dictionary=state.snapshot();var resources: Dictionary=r.snapshot()
	_check(not state.harvest_source(timber["instance"],r) and state.snapshot()==before and r.snapshot()==resources,"Depleted source cannot duplicate")
	var dense: Dictionary=state.sources()[12]
	_check(not state.harvest_source(dense["instance"],r),"Dense resource inaccessible before tool")
	LfeItemTransactions.add(r.inventory,&"leyforge:stone_pickaxe",1)
	LfeItemTransactions.transfer(r.inventory,_slot(r.inventory,&"leyforge:stone_pickaxe"),r.equipment,1,0)
	_check(state.survival.exert(100),"Prepare genuinely depleted stamina")
	_check(state.harvest_source(dense["instance"],r) and state.survival.snapshot()["stamina"]==0 and r.inventory.total(&"leyforge:stone")==6 and r.equipment.stack_at(0)["durability"]==23,"Tool enables real resource capability")
	_check(state.add_object(&"leyforge:kiln",Vector3i(3,20,3),2),"Persistent station identity/orientation")
	var id: String=state.object_at(Vector3i(3,20,3))
	LfeItemTransactions.add(state.station(id).input,&"leyforge:oak_heartwood",2)
	_check(not state.can_remove(Vector3i(3,20,3)),"Occupied station cannot destroy resources")
	_check(state.add_object(&"leyforge:storage_box",Vector3i(4,20,3),1),"Player-built storage foundation")
	var storage: LfeInventory=state.storage(state.object_at(Vector3i(4,20,3)))
	LfeItemTransactions.transfer(r.inventory,0,storage,1)
	_check(not state.can_remove(Vector3i(4,20,3)),"Filled construction storage cannot lose matter")
	var restored: LfeTestCreationView=LfeTestCreationView.new(_catalog)
	_check(restored.restore(state.snapshot(),r.snapshot()) and restored.snapshot()==state.snapshot(),"Sources/functional inventories/orientation exact restore")
	var bad: Dictionary=state.snapshot();bad["objects"].append(bad["objects"][0].duplicate(true))
	_check(not restored.restore(bad,r.snapshot()),"Duplicate world object identities rejected")
	bad=state.snapshot();bad["objects"][0]["orientation"]=4
	_check(not restored.restore(bad,r.snapshot()),"Malformed orientation rejected")

func _persistence() -> void:
	var seed: int=184552221
	var player: Dictionary={"position":[0.5,float(LfeWave1TerrainRules.height_at(seed,0,0))+1.05,0.5],"yaw":0.4,"pitch":-0.2,"selected_block":"leyforge:stone"}
	var r: LfeTestResourceView=LfeTestResourceView.new(_catalog)
	LfeItemTransactions.add(r.inventory,&"leyforge:stone_pickaxe",1)
	LfeHarvestRules.wear(r.personal,r.inventory.stack_at(0)["instance"])
	LfeItemTransactions.add(r.inventory,&"leyforge:oak_heartwood",5)
	var state: LfeTestCreationView=LfeTestCreationView.new(_catalog)
	state.initialize_sources(seed);state.survival.damage(12)
	_check(state.harvest_source(state.sources()[0]["instance"],r),"Legacy v1 depletion is included in the saved compatibility fixture")
	var cell: Vector3i=Vector3i(3,21,3)
	state.add_object(&"leyforge:kiln",cell,3)
	var station: LfeWorkstation=state.station(state.object_at(cell))
	LfeItemTransactions.add(station.input,&"leyforge:oak_heartwood",2)
	LfeItemTransactions.add(station.fuel,&"leyforge:oak_heartwood",1)
	station.start("leyforge:charcoal_burn");station.advance(3)
	var world: LfeTestWorldSave=LfeTestWorldSave.new()
	_check(world.open_world("current",seed,true,_catalog,_root)==OK,"Current world opens")
	world.worldgen_version=1 # This fixture represents existing worldgen-v1 Wave 4 state.
	world.record_voxel_edit(cell,_catalog.get_voxel_id(&"leyforge:kiln"),0)
	_check(world.save(player,r.snapshot(),state.snapshot())==OK,"Current complete state atomic save")
	var loaded: LfeTestWorldSave=LfeTestWorldSave.new()
	_check(loaded.open_world("current",seed,true,_catalog,_root)==OK and loaded.legacy_creation_state==state.snapshot() and loaded.resource_state==r.snapshot() and loaded.worldgen_version==1,"Complete historical worldgen-v1 save v3 exact reload")
	var original: String=FileAccess.get_file_as_string(world.get_primary_path())
	var envelope: Dictionary=JSON.parse_string(original)
	var payload: Dictionary=LfeTestWorldSave.legacy_payload(JSON.parse_string(envelope["payload_json"]),3)
	for version: int in [1,2]:
		var id: String="migration_v%d" % version
		var old: Dictionary=payload.duplicate(true)
		old["metadata"]["world_id"]=id;old["metadata"]["save_version"]=version
		old.erase("creation");old["voxel_overrides"]=[]
		# Genuine historical fields: v1 has no resources; v2 stacks have no instance state.
		if version==1:old.erase("resources")
		else:
			var historical: LfeTestResourceView=LfeTestResourceView.new(_catalog)
			LfeItemTransactions.add(historical.inventory,&"leyforge:stone",7)
			historical.select(5)
			old["resources"]=historical.snapshot()
		var directory: String=_root.path_join(id);DirAccess.make_dir_recursive_absolute(directory)
		_write_envelope(directory.path_join("world.json"),old,version)
		var bytes: String=FileAccess.get_file_as_string(directory.path_join("world.json"))
		var migration: LfeTestWorldSave=LfeTestWorldSave.new()
		_check(migration.open_world(id,seed,true,_catalog,_root)==OK and migration.load_status.contains("migrated v%d" % version),"Historical v%d migrates" % version)
		_check(FileAccess.get_file_as_string(directory.path_join("world.json"))==bytes and migration.player_state==player,"Migration preserves historical bytes/player")
		if version==2:_check(migration.resource_state==old["resources"],"v2 resources/hotbar preserved")
		_check(migration.legacy_creation_state["survival"]["health"]==100 and migration.legacy_creation_state["objects"].is_empty(),"Migration safe Wave 4 defaults")
		_check(migration.save(player)==OK and FileAccess.get_file_as_string(directory.path_join("world.json.previous"))==bytes,"Explicit current save retains historical previous copy")
		# Leave legitimate old fixture for separate rendered migration process.
		var rendered: String=_root.path_join("rendered_v%d" % version)
		DirAccess.make_dir_recursive_absolute(rendered)
		old["metadata"]["world_id"]="rendered_v%d" % version
		_write_envelope(rendered.path_join("world.json"),old,version)
	var old_v3: Dictionary=payload.duplicate(true)
	old_v3["metadata"]["world_id"]="existing_wave4"
	old_v3["creation"]["survival"].erase("timing")
	var legacy_dir: String=_root.path_join("existing_wave4");DirAccess.make_dir_recursive_absolute(legacy_dir)
	_write_envelope(legacy_dir.path_join("world.json"),old_v3,3)
	var old_bytes: String=FileAccess.get_file_as_string(legacy_dir.path_join("world.json"))
	var existing: LfeTestWorldSave=LfeTestWorldSave.new()
	_check(existing.open_world("existing_wave4",seed,true,_catalog,_root)==OK and existing.resource_state==r.snapshot(),"Existing Wave 4 v3 retains damaged tool/resources")
	var old_survival: Dictionary=existing.legacy_creation_state["survival"].duplicate(true);old_survival.erase("timing")
	var legacy_expected: LfeTestCreationView=LfeTestCreationView.new(_catalog);legacy_expected.restore(old_v3["creation"],r.snapshot())
	_check(old_survival==old_v3["creation"]["survival"] and existing.legacy_creation_state==legacy_expected.snapshot(),"Existing v3 preserves survival/construction/processing/source depletion")
	_check(FileAccess.get_file_as_string(legacy_dir.path_join("world.json"))==old_bytes and existing.save(player)==OK,"Existing v3 open nondestructive and compatible save")
	for mutation: String in ["survival","recipe","progress","object","instance","source","missing_object","replenish"]:
		var bad: Dictionary=payload.duplicate(true)
		match mutation:
			"survival":bad["creation"]["survival"]["health"]=-1
			"recipe":bad["creation"]["objects"][0]["station"]["active"]="unknown:recipe"
			"progress":bad["creation"]["objects"][0]["station"]["progress"]=100
			"object":bad["creation"]["objects"].append(bad["creation"]["objects"][0].duplicate(true))
			"instance":bad["resources"]["inventory"][2]=bad["resources"]["inventory"][0].duplicate(true)
			"source":bad["creation"]["sources"].pop_back()
			"missing_object":bad["creation"]["objects"]=[]
			"replenish":bad["creation"]["initialized"]=false;bad["creation"]["sources"]=[]
		_write_envelope(world.get_primary_path(),bad,3)
		var corrupt: LfeTestWorldSave=LfeTestWorldSave.new()
		_check(corrupt.open_world("current",seed,true,_catalog,_root)!=OK and corrupt.save(player)!=OK,"Corrupt state fails closed: "+mutation)
	_write(world.get_primary_path(),original)
	_check(loaded.save(player,r.snapshot(),state.snapshot())==OK,"Valid save rotates previous copy")
	DirAccess.remove_absolute(world.get_primary_path())
	var recovered: LfeTestWorldSave=LfeTestWorldSave.new()
	_check(recovered.open_world("current",seed,true,_catalog,_root)==OK and recovered.load_status.contains("Recovered") and recovered.legacy_creation_state==state.snapshot(),"Previous copy recovers exact Wave 4 state")
	var isolated: LfeTestWorldSave=LfeTestWorldSave.new()
	_check(isolated.open_world("isolated",seed,true,_catalog,_root)==OK and isolated.legacy_creation_state["objects"].is_empty() and isolated.resource_state["inventory"].all(func(v: Variant)->bool:return v==null),"Same-seed world state independent")

func _slot(inventory: LfeInventory,id: StringName) -> int:
	for slot: int in inventory.capacity():
		if inventory.stack_at(slot).get("content")==String(id):return slot
	return -1

func _write(path: String,text: String) -> void:
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		_check(false,"Cannot write disposable fixture/report")
		return
	file.store_string(text);file.flush()

func _write_envelope(path: String,payload: Dictionary,version: int) -> void:
	var text: String=JSON.stringify(payload,"",true,true)
	_write(path,JSON.stringify({"save_version":version,"payload_json":text,"sha256":text.sha256_text()},"\t"))

func _check(condition: bool,message: String) -> void:
	_checks += 1
	if not condition:_failures.append(message)


# Focused fixture staging uses the canonical pattern and production grid transaction.
# It prepares a detached player inventory so failed fixture setup is atomic too.
func _craft_test(inventory: LfeInventory, recipes: LfeRecipeCatalog, id: String) -> bool:
	var recipe: Dictionary = recipes.definition(id)
	if recipe.is_empty() or not recipe.has("grid"):return false
	var next: LfeInventory = LfeInventory.new(inventory._catalog,inventory.capacity())
	next.restore(inventory.snapshot())
	var grid: LfeCraftingGrid = LfeCraftingGrid.new(inventory._catalog,recipes,int(recipe["grid"]["size"]))
	if recipe["grid"]["type"]=="shaped":
		for y: int in recipe["grid"]["pattern"].size():
			var row: String = recipe["grid"]["pattern"][y]
			for x: int in row.length():
				if row[x]==" ":continue
				var content: StringName = StringName(recipe["grid"]["keys"][row[x]])
				if LfeItemTransactions.transfer(next,_slot(next,content),grid.inventory,1,y*grid.size+x)!=1:return false
	else:
		for index: int in recipe["inputs"].size():
			var entry: Dictionary = recipe["inputs"][index]
			if LfeItemTransactions.transfer(next,_slot(next,StringName(entry["content"])),grid.inventory,int(entry["quantity"]),index)!=int(entry["quantity"]):return false
	if not grid.take(next,id) or not grid.release(next):return false
	return inventory.restore(next.snapshot())

func _grid_matching() -> void:
	var output: LfeInventory = LfeInventory.new(_catalog,27)
	var personal: LfeCraftingGrid = LfeCraftingGrid.new(_catalog,_recipes,2)
	LfeItemTransactions.add(personal.inventory,&"leyforge:oak_planks",4)
	_check(personal.preview().get("recipe")!="leyforge:build_workbench","A stacked pile is not the four-cell Workbench pattern")
	for slot: int in range(1,4):LfeItemTransactions.transfer(personal.inventory,0,personal.inventory,1,slot)
	_check(personal.preview().get("recipe")=="leyforge:build_workbench","Full 2x2 matches the Workbench")
	_check(personal.take(output) and personal.preview().is_empty() and output.total(&"leyforge:workbench")==1,"Output takes exactly four cells, once")
	_check(not personal.take(output),"Empty grid cannot double-create output")
	LfeItemTransactions.add(personal.inventory,&"leyforge:oak_heartwood",2)
	LfeItemTransactions.transfer(personal.inventory,0,personal.inventory,2,3)
	_check(personal.preview().get("recipe")=="leyforge:saw_planks" and personal.take(output),"Shapeless recipe accepts translated stack and consumes one")
	_check(personal.inventory.total(&"leyforge:oak_heartwood")==1,"Shapeless extra stack quantity retained")
	_check(not personal.take(output,"leyforge:build_workbench") and personal.inventory.total(&"leyforge:oak_heartwood")==1,"Stale preview request rejects without consumption")
	_check(personal.release(output) and personal.inventory.snapshot().all(func(v:Variant)->bool:return v==null),"Closing returns staged resources exactly")
	LfeItemTransactions.add(personal.inventory,&"leyforge:oak_planks",3);LfeItemTransactions.add(personal.inventory,&"leyforge:oak_stick",2)
	_check(personal.preview().is_empty(),"Workbench tool cannot match personal 2x2")
	personal.release(output)
	var bench: LfeCraftingGrid = LfeCraftingGrid.new(_catalog,_recipes,3)
	var pick: Array = [{"content":"leyforge:oak_planks","quantity":1},{"content":"leyforge:oak_planks","quantity":1},{"content":"leyforge:oak_planks","quantity":1},null,{"content":"leyforge:oak_stick","quantity":1},null,null,{"content":"leyforge:oak_stick","quantity":1},null]
	bench.inventory.restore(pick)
	_check(bench.preview().get("recipe")=="leyforge:craft_wooden_pickaxe","Readable pickaxe silhouette matches")
	var before: Array = bench.inventory.snapshot()
	_check(not LfeRecipeTransactions.craft(output,_recipes,"leyforge:craft_wooden_pickaxe"),"Legacy recipe-ID API cannot bypass a grid")
	var full: LfeInventory = LfeInventory.new(_catalog,1);LfeItemTransactions.add(full,&"leyforge:stone",64)
	var full_before: Array = full.snapshot()
	_check(not bench.take(full) and full.snapshot()==full_before and bench.inventory.snapshot()==before,"Blocked output capacity consumes zero grid inputs")
	_check(not bench.release(full) and full.snapshot()==full_before and bench.inventory.snapshot()==before,"Full backpack close retains all staging atomically")
	_check(bench.take(output) and output.stack_at(_slot(output,&"leyforge:wooden_pickaxe")).has("instance"),"Grid output creates a real durable instance")
	bench.inventory.restore(pick);LfeItemTransactions.transfer(bench.inventory,1,bench.inventory,1,3)
	_check(bench.preview().is_empty(),"Same ingredient totals in wrong shape do not craft")
	bench.inventory.restore(pick);LfeItemTransactions.add(bench.inventory,&"leyforge:dirt",1)
	_check(bench.preview().is_empty(),"Unrelated extra input invalidates shaped output")
	bench.inventory.restore([null,{"content":"leyforge:oak_planks","quantity":1},{"content":"leyforge:oak_planks","quantity":1},null,{"content":"leyforge:oak_stick","quantity":1},{"content":"leyforge:oak_planks","quantity":1},null,{"content":"leyforge:oak_stick","quantity":1},null])
	_check(bench.preview().get("recipe")=="leyforge:craft_wooden_axe","Explicitly allowed mirrored/translated axe matches")
	var recipes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/recipes/wave_4_recipes.json"))
	for mutation: String in ["quantity","symbol","size","context","fuel"]:
		var bad: Dictionary = recipes.duplicate(true)
		var recipe: Dictionary = bad["recipes"][1]
		match mutation:
			"quantity":recipe["inputs"][0]["quantity"]=2
			"symbol":recipe["grid"]["pattern"][0]="XXX"
			"size":recipe["grid"]["size"]=2
			"context":recipe["context"]="kiln"
			"fuel":recipe["fuel"]=[{"content":"leyforge:stone","quantity":1}]
		_write(_root.path_join("invalid_grid.json"),JSON.stringify(bad))
		_check(not LfeRecipeCatalog.new().load_path(_root.path_join("invalid_grid.json"),_catalog),"Malformed pattern authoring rejects: "+mutation)
	for recipe: Dictionary in recipes["recipes"]:recipe.erase("grid")
	_write(_root.path_join("legacy_recipes.json"),JSON.stringify(recipes))
	_check(LfeRecipeCatalog.new().load_path(_root.path_join("legacy_recipes.json"),_catalog),"Six-field canonical recipe schema remains readable")
	var state: LfeTestCreationView = LfeTestCreationView.new(_catalog);state.initialize_sources(184552221)
	var sources: Array = state.sources()
	_check(state.validate_source_layout(184552221),"Tree source identities/layout remain unchanged")
	var bare: Dictionary = LfeHarvestRules.evaluate(state.source_definition("fallen_oak"),{},_catalog)
	var wooden: Dictionary = LfeHarvestRules.evaluate(state.source_definition("fallen_oak"),LfeItemInstance.create(&"leyforge:wooden_axe",_catalog),_catalog)
	var stone: Dictionary = LfeHarvestRules.evaluate(state.source_definition("fallen_oak"),LfeItemInstance.create(&"leyforge:stone_axe",_catalog),_catalog)
	_check(float(bare["seconds"])>float(wooden["seconds"]) and float(wooden["seconds"])>float(stone["seconds"]),"Tree timing: manual slower than Wooden Axe, slower than Stone Axe")
	_check(state.add_object(&"leyforge:workbench",Vector3i(2,30,2),0) and state.can_remove(Vector3i(2,30,2)),"Workbench has no persistent hidden staging inventory")
	var restored: LfeTestCreationView = LfeTestCreationView.new(_catalog)
	_check(restored.restore(state.snapshot()) and restored.snapshot()==state.snapshot(),"Workbench persists identity/orientation without new save version")

func _voxel_trees() -> void:
	var seed: int = 184552221
	var v1: LfeWave1TerrainGenerator = LfeWave1TerrainGenerator.new();v1.configure(seed,_catalog,1)
	var v2: LfeWave1TerrainGenerator = LfeWave1TerrainGenerator.new();v2.configure(seed,_catalog,2)
	_check(_catalog.placeable_voxel(&"leyforge:oak_heartwood")==11 and _catalog.content_definition(&"leyforge:oak_heartwood")["kind"]=="block","Existing Heartwood ID resolves one placeable block projection")
	_check(not _catalog.is_inventory_content(&"leyforge:oak_leaves") and _catalog.definition_for_id(&"leyforge:oak_leaves")["harvest"]["outputs"].is_empty(),"Real leaves have no timber or collectible output")
	# Historical baseline pins, plus base terrain comparisons at signed coordinates.
	for pair: Array in [[Vector3i(0,18,0),0],[Vector3i(0,17,0),1],[Vector3i(0,16,0),2],[Vector3i(0,13,0),3]]:
		_check(v1.sample_voxel_id(pair[0])==pair[1],"Historical v1 voxel pin "+str(pair[0]))
	for x: int in [-129,-17,-1,0,16,127,257]:
		for z: int in [-96,-1,0,31,128]:
			var height: int = LfeWave1TerrainRules.height_at(seed,x,z)
			for y: int in [height-4,height-1,height]:
				_check(v2.sample_voxel_id(Vector3i(x,y,z))==v1.sample_voxel_id(Vector3i(x,y,z)),"v2 preserves the signed-coordinate base terrain")
	var trees: Array[Dictionary] = LfeStarterTreeRules.candidates(seed,Vector2i(-40,-40),Vector2i(40,40))
	_check(trees.size()>15 and trees==LfeStarterTreeRules.candidates(seed,Vector2i(-40,-40),Vector2i(40,40)),"Useful woodland density is repeated deterministically")
	_check(trees!=LfeStarterTreeRules.candidates(seed+1,Vector2i(-40,-40),Vector2i(40,40)),"Different seed changes spatial candidates")
	_check(LfeStarterTreeRules.candidates(seed,Vector2i(300,-350),Vector2i(380,-270)).size()>10,"Trees continue outside starter region at signed distant coordinates")
	var heights: Dictionary = {};var sides: Dictionary = {};var boundaries: Dictionary = {}
	for tree: Dictionary in trees:
		var base: Vector3i = tree["base"];heights[tree["height"]]=true;sides[base.x<0]=true
		_check(v1.sample_voxel_id(base)==0 and v2.sample_voxel_id(base)==11 and v2.sample_voxel_id(base+Vector3i.DOWN)==1,"Grass-supported individual Heartwood trunk")
		var cells: Dictionary = LfeStarterTreeRules.cells(tree);var all_match: bool = true
		for cell: Vector3i in cells:all_match=all_match and v1.sample_voxel_id(cell)==0 and v2.sample_voxel_id(cell)==(11 if cells[cell]==1 else 12)
		_check(all_match,"All generated trunk/canopy cells are real voxels, absent from v1")
	for tree: Dictionary in LfeStarterTreeRules.candidates(seed,Vector2i(-160,-160),Vector2i(160,160)):
		var base: Vector3i = tree["base"]
		if not boundaries.has(base.x<0) and posmod(base.x,16)+int(tree["radius"])>=16:boundaries[base.x<0]=tree
	_check(heights.size()==3 and sides.size()==2,"Deterministic height variants occur on positive and negative coordinates")
	_check(boundaries.size()==2,"Natural canopies cross positive and negative chunk boundaries")
	for boundary: Dictionary in boundaries.values():
		var base: Vector3i = boundary["base"];var bx: int = floori(float(base.x)/16)*16;var bz: int = floori(float(base.z)/16)*16
		var origins: Array[Vector3i] = []
		for z: int in [bz-16,bz,bz+16]:
			for x: int in [bx-16,bx,bx+16]:
				for y: int in [0,16]:origins.append(Vector3i(x,y,z))
		var forward: Dictionary = _generated_tree_cells(v2,origins)
		origins.reverse();var backward: Dictionary = _generated_tree_cells(v2,origins)
		_check(forward==backward,"Opposite chunk generation order yields identical boundary trees")
		var expected: Dictionary = {}
		for tree: Dictionary in LfeStarterTreeRules.candidates(seed,Vector2i(bx-16,bz-16),Vector2i(bx+31,bz+31)):
			var cells: Dictionary = LfeStarterTreeRules.cells(tree)
			for cell: Vector3i in cells:
				if cell.x>=bx-16 and cell.x<bx+32 and cell.y>=0 and cell.y<32 and cell.z>=bz-16 and cell.z<bz+32:expected[cell]=11 if cells[cell]==1 else 12
		_check(forward==expected,"Chunk meshes contain full contributions from neighbouring candidate cells without seams")
	var legacy: LfeTestCreationView = LfeTestCreationView.new(_catalog);legacy.initialize_sources(seed,1)
	var modern: LfeTestCreationView = LfeTestCreationView.new(_catalog);modern.initialize_sources(seed,2)
	_check(legacy.sources().size()==20 and modern.sources().size()==8 and modern.sources().all(func(v:Dictionary)->bool:return v["source"]!="fallen_oak"),"v2 creates no legacy timber sources; v1 retains its exact layout")
	_check(modern.validate_source_layout(seed,2) and not modern.validate_source_layout(seed,1) and legacy.validate_source_layout(seed,1) and not legacy.validate_source_layout(seed,2),"Source validation is bound to stored worldgen version")
	var base: Vector3i = trees[0]["base"]
	var r: LfeTestResourceView = LfeTestResourceView.new(_catalog)
	var world: LfeTestWorldSave = LfeTestWorldSave.new();world.open_world("voxel_trees",seed,true,_catalog,_root)
	_check(world.worldgen_version==2,"New worlds choose worldgen v2")
	var outputs: Array = _catalog.definition_for_id(&"leyforge:oak_heartwood")["harvest"]["outputs"]
	_check(r.break_to_drop(&"leyforge:oak_heartwood",Vector3(base)+Vector3.ONE*0.5,func()->Error:return world.record_voxel_edit(base,0,11),outputs),"One trunk break records one sparse air override")
	_check(r.drops().size()==1 and r.drops()[0]["stack"]=={"content":"leyforge:oak_heartwood","quantity":1} and world.overrides.count()==1,"One trunk voxel yields exactly one Heartwood drop")
	v2.set_override_store(world.overrides)
	var origin: Vector3i = Vector3i(floori(float(base.x)/16)*16,floori(float(base.y)/16)*16,floori(float(base.z)/16)*16)
	var buffer: VoxelBuffer = VoxelBuffer.new();buffer.create(16,16,16);v2._generate_block(buffer,origin,0)
	var local: Vector3i = base-origin
	_check(buffer.get_voxel(local.x,local.y,local.z,VoxelBuffer.CHANNEL_TYPE)==0 and world.overrides.voxel_id_at(base+Vector3i.UP,v2.sample_voxel_id(base+Vector3i.UP))==11,"Mined trunk stays air while its neighbour remains Heartwood")
	r.pickup(r.drops()[0]["instance"])
	var placed: Vector3i = base+Vector3i(4,8,0)
	_check(v2.sample_voxel_id(placed)==0 and r.place_from_inventory(0,func()->Error:return world.record_voxel_edit(placed,11,0)) and r.inventory.total(&"leyforge:oak_heartwood")==0,"Same Heartwood inventory places exactly one voxel")
	var player: Dictionary = {"position":[0.5,18.05,0.5],"yaw":0.0,"pitch":0.0,"selected_block":"leyforge:oak_heartwood"}
	_check(world.save(player,r.snapshot())==OK,"Mined and placed tree overrides save without serialising untouched trees")
	var loaded: LfeTestWorldSave = LfeTestWorldSave.new()
	_check(loaded.open_world("voxel_trees",seed,true,_catalog,_root)==OK and loaded.worldgen_version==2 and loaded.overrides.count()==2 and loaded.overrides.voxel_id_at(base,11)==0 and loaded.overrides.voxel_id_at(placed,0)==11,"Fresh v2 reload preserves mined and placed wood exactly")
	_check(r.break_to_drop(&"leyforge:oak_heartwood",Vector3(placed),func()->Error:return loaded.record_voxel_edit(placed,0,0),outputs) and r.pickup(r.drops()[0]["instance"])==1 and r.inventory.total(&"leyforge:oak_heartwood")==1 and loaded.overrides.count()==1,"Re-mining placed wood returns exactly once and clears the redundant override")
	var rule: Dictionary = _catalog.definition_for_id(&"leyforge:oak_heartwood")["harvest"]
	var manual: Dictionary = LfeHarvestRules.evaluate(rule,{},_catalog)
	var wood: Dictionary = LfeHarvestRules.evaluate(rule,LfeItemInstance.create(&"leyforge:wooden_axe",_catalog),_catalog)
	var stone: Dictionary = LfeHarvestRules.evaluate(rule,LfeItemInstance.create(&"leyforge:stone_axe",_catalog),_catalog)
	_check(manual["seconds"]>wood["seconds"] and wood["seconds"]>stone["seconds"] and not manual["wear"] and wood["wear"] and stone["wear"],"Per-voxel chopping retains manual/wood/Stone speed and durability rules")

func _generated_tree_cells(generator: LfeWave1TerrainGenerator, origins: Array[Vector3i]) -> Dictionary:
	var result: Dictionary = {}
	for origin: Vector3i in origins:
		var buffer: VoxelBuffer = VoxelBuffer.new();buffer.create(16,16,16);generator._generate_block(buffer,origin,0)
		for z: int in 16:
			for y: int in 16:
				for x: int in 16:
					var value: int = buffer.get_voxel(x,y,z,VoxelBuffer.CHANNEL_TYPE)
					if value in [11,12]:result[origin+Vector3i(x,y,z)]=value
	return result

func _grounded_drops() -> void:
	var r: LfeTestResourceView = LfeTestResourceView.new(_catalog)
	LfeItemTransactions.add(r.inventory,&"leyforge:oak_heartwood",3)
	var id: String = r.drop_from_inventory(0,1,Vector3(0,8,0))
	var before: Dictionary = r.drop(id)
	var flat: Callable = func(p:Vector3)->Variant:return Vector3(p.x,1.175,p.z)
	_check(r.ground_drop(id,flat) and is_equal_approx(float(r.drop(id)["position"][1]),1.175) and r.drop(id)["position"][0]==0 and r.drop(id)["position"][2]==0 and r.drop(id)["stack"]==before["stack"] and r.drop(id)["instance"]==id,"Spawn settling changes only logical resting position")
	before=r.snapshot()
	_check(not r.settle_drops(func(_p:Vector3)->bool:return false,flat) and r.snapshot()==before,"Unloaded drops do not settle against unavailable terrain")
	_check(not r.ground_drop(id,func(_p:Vector3)->Variant:return null) and r.snapshot()==before,"Missing loaded support retains safe position for later settling")
	_check(r.ground_drop(id,func(p:Vector3)->Variant:return Vector3(p.x,-0.825,p.z)) and r.drop(id)["stack"]==before["drops"][0]["stack"],"Support removal resettles downward without losing matter")
	var ledges: LfeTestResourceView = LfeTestResourceView.new(_catalog);LfeItemTransactions.add(ledges.inventory,&"leyforge:stone",2)
	ledges.drop_from_inventory(0,1,Vector3(0,3.175,0));ledges.drop_from_inventory(0,1,Vector3(0.5,1.175,0))
	before=ledges.snapshot()
	for tick: int in 20:ledges.advance_drop_clusters(1,func(_p:Vector3)->bool:return true,func(_a:Vector3,_b:Vector3)->bool:return true)
	_check(ledges.snapshot()==before and ledges.total(&"leyforge:stone")==2,"Different ledges do not attract upward or merge through air")
	LfeItemTransactions.add(r.inventory,&"leyforge:wooden_axe",1)
	var slot: int = _slot(r.inventory,&"leyforge:wooden_axe")
	var tool: Dictionary = r.inventory.stack_at(slot)
	var tool_drop: String = r.drop_from_inventory(slot,1,Vector3(2,8,0))
	r.ground_drop(tool_drop,flat)
	_check(r.drop(tool_drop)["stack"]==tool,"Stateful item grounding preserves instance identity and durability")

func _dense_stone_presentation() -> void:
	# Construct actual production geometry for both stored worldgen source layouts.
	for version: int in [1,2]:
		var world: LeyforgeWave1Playground = LeyforgeWave1Playground.new()
		world.block_catalog=_catalog;world.creation=LfeCreationState.new(_catalog)
		_check(world.creation.initialize_sources(184552221,version),"Dense Stone presentation fixture initializes its historical source layout")
		var before: Dictionary = world.creation.snapshot()
		var presenter: LeyforgeCreationPresenter = LeyforgeCreationPresenter.new()
		presenter._world=world;root.add_child(presenter)
		var count: int = 0
		for entry: Dictionary in world.creation.sources():
			if entry["source"]!="dense_stone":continue
			count+=1
			var body: Node3D = presenter._source(entry)
			var meshes: Array[Node] = body.get_children().filter(func(node:Node)->bool:return node is MeshInstance3D)
			var collisions: Array[Node] = body.get_children().filter(func(node:Node)->bool:return node is CollisionShape3D)
			_check(meshes.size()==1 and collisions.size()==1 and body.get_child_count()==2,"Dense Stone has exactly one visible mesh and one collision, with no sub-meshes")
			if meshes.size()!=1 or collisions.size()!=1:continue
			var mesh: MeshInstance3D = meshes[0] as MeshInstance3D
			var collision: CollisionShape3D = collisions[0] as CollisionShape3D
			var centre: Vector3 = Vector3(0,0.5,0)
			_check(mesh.mesh is BoxMesh and mesh.mesh.size==Vector3.ONE and mesh.position==centre and mesh.visible and mesh.scale==Vector3.ONE,"Dense Stone visible BoxMesh is exactly one metre in every dimension")
			_check(collision.shape is BoxShape3D and collision.shape.size==Vector3.ONE and collision.position==centre and not collision.disabled and collision.scale==Vector3.ONE,"Dense Stone collision is exactly the same unit cube")
			_check(body.get_meta("highlight_center")==centre and body.get_meta("highlight_size")==Vector3.ONE,"Dense Stone highlight bounds exactly match mesh and collision")
			var minimum: Vector3 = body.position+centre-Vector3.ONE*0.5
			var saved: Array = entry["position"]
			_check(minimum==minimum.round() and minimum.y==LfeWave1TerrainRules.height_at(184552221,int(minimum.x),int(minimum.z))+1 and body.position==Vector3(float(saved[0]),floorf(float(saved[1])),float(saved[2])) and body.scale==Vector3.ONE,"Unit outcrop rests on terrain and aligns to the voxel grid without moving saved source coordinates")
			_check(body.get_meta("source")==entry["instance"] and body.collision_layer==8,"Existing source identity and targeting collision layer remain unchanged")
		_check(count==4 and world.creation.snapshot()==before,"Both layouts retain exactly four Dense Stone sources and unchanged authoritative state")
		presenter.free();world.free()

func _held_gathering() -> void:
	# Real production world/voxel/source authority in the gate's isolated profile.
	var world: LeyforgeWave1Playground = LeyforgeWave1Playground.new()
	root.add_child(world);world._playtest_mode=true;world.player._playtest_mode=true;world.set_physics_process(false)
	for frame: int in 900:
		await physics_frame
		if world.is_runtime_ready():break
	_check(world.is_runtime_ready(),"Held-action focused world streams real terrain")
	if not world.is_runtime_ready():world.free();return
	world.player.set_runtime_ready(false)
	var other: LfePlayerCharacter=world.authority.add_character("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",world.spawn_position+Vector3(1,0,0))
	var other_before: Dictionary=other.snapshot()
	for operation: String in ["primary","begin_harvest","begin_source_harvest","advance_harvest","break_cell","place_cell","drop_selected","rest"]:
		var before: Array=world.authority.players_snapshot()
		var edits_before: int=world.world_save.overrides.count()
		_check(world.command("cccccccccccccccccccccccccccccccc",operation,{}).reason_code=="invalid_actor" and world.authority.players_snapshot()==before and world.world_save.overrides.count()==edits_before,"Live voxel authority rejects unknown actor: "+operation)
	var trees: Array[Dictionary] = LfeStarterTreeRules.candidates(world.active_seed,Vector2i(-40,-40),Vector2i(40,40))
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Vector3(a["base"]).length_squared()<Vector3(b["base"]).length_squared())
	var base: Vector3i = trees[0]["base"]
	for family: String in ["voxel","source"]:
		var source: bool = family=="source"
		var tool_id: StringName = &"leyforge:stone_pickaxe" if source else &"leyforge:stone_axe"
		if not LfeTestResourceView.view(world.personal_resources,world.world_resources).equipment.stack_at(0).is_empty():LfeItemTransactions.transfer(LfeTestResourceView.view(world.personal_resources,world.world_resources).equipment,0,LfeTestResourceView.view(world.personal_resources,world.world_resources).inventory,1)
		LfeItemTransactions.add(LfeTestResourceView.view(world.personal_resources,world.world_resources).inventory,tool_id,2)
		var slot: int = _slot(LfeTestResourceView.view(world.personal_resources,world.world_resources).inventory,tool_id)
		LfeItemTransactions.transfer(LfeTestResourceView.view(world.personal_resources,world.world_resources).inventory,slot,LfeTestResourceView.view(world.personal_resources,world.world_resources).equipment,1,0)
		var targets: Array = [{"source":world.creation.sources()[0]["instance"]},{"source":world.creation.sources()[1]["instance"]}] if source else [{"cell":base},{"cell":base+Vector3i.UP}]
		await _hold_aim(world,targets[0])
		var resources: Dictionary = LfeTestResourceView.view(world.personal_resources,world.world_resources).snapshot();var state: Dictionary = world.creation.snapshot();var edits: int = world.world_save.overrides.count()
		_check(not _hold_begin(world,targets[0]),family+": begin without active primary input is rejected")
		# A/B: tap/release, and a longer incomplete hold, both reset immediately.
		for fraction: float in [0.01,0.5]:
			world.set_primary_action(true)
			_check(_hold_begin(world,targets[0]),family+": held press begins validated attempt")
			var seconds: float = float(world._harvest.get("seconds",1))
			_check(not world.advance_harvest(seconds*fraction),family+": incomplete held work cannot mutate")
			world.set_primary_action(false)
			_check(not world.has_active_harvest() and not world.advance_harvest(60) and LfeTestResourceView.view(world.personal_resources,world.world_resources).snapshot()==resources and world.creation.snapshot()==state and world.world_save.overrides.count()==edits,family+": release cancels immediately without output, wear, block edit or depletion")
		# D: switching target discards first-target work and never transfers it.
		world.set_primary_action(true);_hold_begin(world,targets[0]);world.advance_harvest(float(world._harvest["seconds"])*0.75)
		await _hold_aim(world,targets[1])
		_check(not world.advance_harvest(60) and not world.has_active_harvest() and LfeTestResourceView.view(world.personal_resources,world.world_resources).snapshot()==resources and world.creation.snapshot()==state,family+": target switch cancels first attempt")
		_check(_hold_begin(world,targets[1]) and world._harvest.get("work",-1)==0,family+": second target begins from zero")
		_check(not world.advance_harvest(float(world._harvest["seconds"])*0.25) and LfeTestResourceView.view(world.personal_resources,world.world_resources).snapshot()==resources,family+": prior work cannot complete second target")
		world.set_primary_action(false);await _hold_aim(world,targets[0])
		# E: another instance of the same tool cancels, even with identical class.
		world.set_primary_action(true);_hold_begin(world,targets[0]);world.advance_harvest(float(world._harvest["seconds"])*0.5)
		slot=_slot(LfeTestResourceView.view(world.personal_resources,world.world_resources).inventory,tool_id)
		LfeItemTransactions.transfer(LfeTestResourceView.view(world.personal_resources,world.world_resources).equipment,0,LfeTestResourceView.view(world.personal_resources,world.world_resources).inventory,1)
		LfeItemTransactions.transfer(LfeTestResourceView.view(world.personal_resources,world.world_resources).inventory,slot,LfeTestResourceView.view(world.personal_resources,world.world_resources).equipment,1,0)
		var switched: Dictionary = LfeTestResourceView.view(world.personal_resources,world.world_resources).snapshot()
		_check(not world.advance_harvest(60) and not world.has_active_harvest() and LfeTestResourceView.view(world.personal_resources,world.world_resources).snapshot()==switched and world.creation.snapshot()==state,family+": changing equipped instance cancels without extra wear/output")
		# Capability/durability invalidation cannot fall back and keep old work.
		_hold_begin(world,targets[0]);world.advance_harvest(float(world._harvest["seconds"])*0.5)
		var equipment: Array = LfeTestResourceView.view(world.personal_resources,world.world_resources).equipment.snapshot();var broken: Array = equipment.duplicate(true);broken[0]["durability"]=0
		LfeTestResourceView.view(world.personal_resources,world.world_resources).equipment.restore(broken)
		_check(not world.advance_harvest(60) and not world.has_active_harvest(),family+": lost capability cancels accumulated work")
		LfeTestResourceView.view(world.personal_resources,world.world_resources).equipment.restore(equipment)
		# G: menu open cancels immediately; held input cannot advance behind it.
		_hold_begin(world,targets[0]);world.advance_harvest(float(world._harvest["seconds"])*0.5)
		var before_menu: Dictionary = LfeTestResourceView.view(world.personal_resources,world.world_resources).snapshot()
		world.inventory_panel.open();world.set_primary_action(true)
		_check(not world.has_active_harvest() and not _hold_begin(world,targets[0]) and not world.advance_harvest(60) and LfeTestResourceView.view(world.personal_resources,world.world_resources).snapshot()==before_menu,family+": menu captures input and prevents background gathering")
		world.close_inventory();world.set_primary_action(false)
		await _hold_aim(world,targets[0]);world.set_primary_action(true);_hold_begin(world,targets[0])
		world.damage_player(100)
		_check(not world.has_active_harvest() and not world.advance_harvest(60),family+": death immediately cancels harvesting")
		world.active_character.survival.respawn()
		# Range/occlusion checks use actual production targeting, not fixture tokens.
		world.set_primary_action(true);_hold_begin(world,targets[0]);world.advance_harvest(float(world._harvest["seconds"])*0.5)
		var camera: Camera3D = world.player.get_camera();var eye: Vector3 = camera.global_position
		camera.global_position+=Vector3.UP*20;camera.look_at(eye,Vector3.FORWARD)
		_check(not world.advance_harvest(60) and not world.has_active_harvest(),family+": target leaving range cancels")
		await _hold_aim(world,targets[0]);_hold_begin(world,targets[0])
		var point: Vector3 = _hold_point(world,targets[0]);var blocker: Vector3i = Vector3i(camera.global_position.lerp(point,0.5).floor())
		var voxel_tool: VoxelTool = world.terrain.get_voxel_tool();voxel_tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
		var old: int = voxel_tool.get_voxel(blocker);voxel_tool.set_voxel(blocker,11)
		_check(not world.advance_harvest(60) and not world.has_active_harvest(),family+": actual voxel occlusion cancels")
		voxel_tool.set_voxel(blocker,old)
		await _hold_aim(world,targets[0]);_hold_begin(world,targets[0])
		if source:
			var original_source: Dictionary = world.creation._sources[0].duplicate(true)
			world.creation._sources[0]["remaining"]-=1
			_check(not world.advance_harvest(60) and not world.has_active_harvest(),family+": changed source record cancels the stale attempt")
			world.creation._sources[0]=original_source
		else:
			voxel_tool.set_voxel(base,12)
			_check(not world.advance_harvest(60) and not world.has_active_harvest(),family+": changed voxel identity cancels the stale attempt")
			voxel_tool.set_voxel(base,11)
		await _hold_aim(world,targets[0]);_hold_begin(world,targets[0])
		camera.global_position+=Vector3(1000,0,1000);world.player.global_position+=Vector3(1000,0,1000)
		for frame: int in 600:
			await physics_frame
			if not world.region_relevant(point):break
		_check(not world.region_relevant(point) and not world.advance_harvest(60) and not world.has_active_harvest(),family+": actual chunk unloading cancels the attempt")
		# C/F: full held work completes once, then the next target starts at zero.
		await _hold_aim(world,targets[0]);_hold_begin(world,targets[0])
		var content: StringName = &"leyforge:stone" if source else &"leyforge:oak_heartwood"
		var quantity: int = 6 if source else 1;var total: int = LfeTestResourceView.view(world.personal_resources,world.world_resources).total(content)
		var durability: int = int(LfeTestResourceView.view(world.personal_resources,world.world_resources).equipment.stack_at(0)["durability"])
		_check(world.advance_harvest(60) and not world.has_active_harvest() and LfeTestResourceView.view(world.personal_resources,world.world_resources).total(content)==total+quantity and LfeTestResourceView.view(world.personal_resources,world.world_resources).equipment.stack_at(0)["durability"]==durability-1,family+": full hold performs exactly one conserved operation and one wear")
		_check(not world.advance_harvest(60) and LfeTestResourceView.view(world.personal_resources,world.world_resources).total(content)==total+quantity,family+": cleared target cannot complete twice")
		await _hold_aim(world,targets[1])
		_check(_hold_begin(world,targets[1]) and world._harvest.get("work",-1)==0,family+": continuing held action can begin next target without releasing")
		_check(world.advance_harvest(60) and LfeTestResourceView.view(world.personal_resources,world.world_resources).total(content)==total+2*quantity and LfeTestResourceView.view(world.personal_resources,world.world_resources).equipment.stack_at(0)["durability"]==durability-2,family+": consecutive held operations conserve exact output and wear")
		world.set_primary_action(false)
	_check(other.snapshot()==other_before,"Local held harvesting, death and recovery never mutate inactive character B")
	world.free()

func _hold_point(world: LeyforgeWave1Playground, target: Dictionary) -> Vector3:
	if target.has("cell"):return Vector3(target["cell"])+Vector3.ONE*0.5
	var p: Array = world.creation.source(target["source"])["position"]
	return Vector3(float(p[0]),floorf(float(p[1]))+0.5,float(p[2]))

func _hold_aim(world: LeyforgeWave1Playground, target: Dictionary) -> void:
	var point: Vector3 = _hold_point(world,target)
	world.player.global_position=point+Vector3(2.5,-0.45,0)
	var camera: Camera3D = world.player.get_camera();camera.top_level=true
	camera.global_position=point+Vector3(1.7,1 if target.has("source") else 0,0);camera.look_at(point,Vector3.UP)
	for frame: int in 600:
		await physics_frame
		if world.region_relevant(point):break
	world.creation_presenter.sync()
	for frame: int in 4:await physics_frame
	world.player._update_targeting()
	_check(world.player.target_source()==target["source"] if target.has("source") else world.player.has_voxel_target() and world.player.get_target_cell()==target["cell"],"Focused held-action aim resolves actual target")

func _hold_begin(world: LeyforgeWave1Playground, target: Dictionary) -> bool:
	return world.begin_source_harvest(target["source"]) if target.has("source") else world.begin_harvest(target["cell"])
