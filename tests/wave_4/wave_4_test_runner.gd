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
	var report: Dictionary = {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures,"runner":Engine.get_version_info()["string"],"property_seed":928143,"property_steps":300}
	_write(_out.path_join("focused.json"),JSON.stringify(report,"\t",true,true))
	for failure: String in _failures:
		push_error("Wave 4: " + failure)
	print("WAVE_4_TEST_%s checks=%d" % ["PASS" if _failures.is_empty() else "FAIL",_checks])
	quit(0 if _failures.is_empty() else 1)

func _tools() -> void:
	var r: LfeResourceState = LfeResourceState.new(_catalog)
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
			_check(LfeHarvestRules.wear(r,stack["instance"]),"Durability authorized use %d" % use)
		_check(int(r.equipment.stack_at(0)["durability"])==0 and not LfeHarvestRules.wear(r,stack["instance"]),"Broken state bounded and unusable")
		_check(LfeHarvestRules.evaluate(rule,r.equipment.stack_at(0),_catalog).is_empty(),"Broken tool cannot meet capability")
		_check(LfeItemTransactions.transfer(r.equipment,0,r.inventory,1)==1,"Broken instance moves intact")
		slot = _slot(r.inventory,id)
		var drop: String = r.drop_from_inventory(slot,1,Vector3(1,20,1))
		var restored: LfeResourceState = LfeResourceState.new(_catalog)
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
	_check(s.profile_name=="Standard" and not s.thirst_enabled(),"Normal gameplay Standard, thirst disabled")
	for minute: int in 60:s.advance(60,false,false,false)
	_check(is_equal_approx(float(s.snapshot()["hunger"]),96) and s.snapshot()["thirst"]==100 and s.snapshot()["fatigue"]==0 and s.snapshot()["exposure"]==0,"Canonical Standard hour: hunger 4, benign exposure zero, routine fatigue zero, thirst unchanged")
	_check(not s.consume(i,1) and i.total(&"leyforge:drinking_water")==2,"Disabled thirst has no consumption maintenance")
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
	_check(is_equal_approx(float(s.snapshot()["fatigue"]),fatigue-0.05/60),"Awake rest canonical fatigue reduction 0.05/min")
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
	var r: LfeResourceState = LfeResourceState.new(_catalog)
	var state: LfeCreationState = LfeCreationState.new(_catalog);state.initialize_sources(184552221)
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
	var r: LfeResourceState = LfeResourceState.new(_catalog)
	LfeItemTransactions.add(r.inventory,&"leyforge:stone",67)
	var a: String=r.drop_from_inventory(0,63,Vector3(0,20,0))
	var b: String=r.drop_from_inventory(0,1,Vector3(0.2,20,0))
	var c: String=r.drop_from_inventory(1,3,Vector3(1.2,20,0))
	var before: Dictionary=r.snapshot()
	_check(not r.advance_drop_clusters(0.5,func(_p:Vector3)->bool:return false,func(_a:Vector3,_b:Vector3)->bool:return true) and r.snapshot()==before,"Unloaded drops never attract")
	_check(not r.advance_drop_clusters(0.5,func(_p:Vector3)->bool:return true,func(_a:Vector3,_b:Vector3)->bool:return false) and r.snapshot()==before,"Walls block attraction")
	for n: int in 80:r.advance_drop_clusters(0.5,func(_p:Vector3)->bool:return true,func(_a:Vector3,_b:Vector3)->bool:return true)
	_check(r.total(&"leyforge:stone")==67 and r.drops().size()==2 and r.drops().all(func(v:Dictionary)->bool:return int(v["stack"]["quantity"])<=64),"Convergence/partial merge preserves all 67 units and maxima")
	var restored: LfeResourceState=LfeResourceState.new(_catalog)
	_check(restored.restore(r.snapshot()) and restored.snapshot()==r.snapshot(),"Final logical positions/quantities persist exactly")
	LfeItemTransactions.add(r.inventory,&"leyforge:wooden_pickaxe",2)
	r.drop_from_inventory(_slot(r.inventory,&"leyforge:wooden_pickaxe"),1,Vector3(0,20,0))
	r.drop_from_inventory(_slot(r.inventory,&"leyforge:wooden_pickaxe"),1,Vector3(0.1,20,0))
	before=r.snapshot()
	r.advance_drop_clusters(1,func(_p:Vector3)->bool:return true,func(_a:Vector3,_b:Vector3)->bool:return true)
	_check(r.drops().filter(func(v:Dictionary)->bool:return v["stack"].has("instance")).size()==2 and r.total(&"leyforge:wooden_pickaxe")==2,"Different durable instances never merge")

func _state() -> void:
	var state: LfeCreationState=LfeCreationState.new(_catalog)
	var r: LfeResourceState=LfeResourceState.new(_catalog)
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
	var restored: LfeCreationState=LfeCreationState.new(_catalog)
	_check(restored.restore(state.snapshot(),r.snapshot()) and restored.snapshot()==state.snapshot(),"Sources/functional inventories/orientation exact restore")
	var bad: Dictionary=state.snapshot();bad["objects"].append(bad["objects"][0].duplicate(true))
	_check(not restored.restore(bad,r.snapshot()),"Duplicate world object identities rejected")
	bad=state.snapshot();bad["objects"][0]["orientation"]=4
	_check(not restored.restore(bad,r.snapshot()),"Malformed orientation rejected")

func _persistence() -> void:
	var seed: int=184552221
	var player: Dictionary={"position":[0.5,float(LfeWave1TerrainRules.height_at(seed,0,0))+1.05,0.5],"yaw":0.4,"pitch":-0.2,"selected_block":"leyforge:stone"}
	var r: LfeResourceState=LfeResourceState.new(_catalog)
	LfeItemTransactions.add(r.inventory,&"leyforge:stone_pickaxe",1)
	LfeHarvestRules.wear(r,r.inventory.stack_at(0)["instance"])
	LfeItemTransactions.add(r.inventory,&"leyforge:oak_heartwood",5)
	var state: LfeCreationState=LfeCreationState.new(_catalog)
	state.initialize_sources(seed);state.survival.damage(12)
	var cell: Vector3i=Vector3i(3,21,3)
	state.add_object(&"leyforge:kiln",cell,3)
	var station: LfeWorkstation=state.station(state.object_at(cell))
	LfeItemTransactions.add(station.input,&"leyforge:oak_heartwood",2)
	LfeItemTransactions.add(station.fuel,&"leyforge:oak_heartwood",1)
	station.start("leyforge:charcoal_burn");station.advance(3)
	var world: LfeWorldSave=LfeWorldSave.new()
	_check(world.open_world("current",seed,true,_catalog,_root)==OK,"Current world opens")
	world.record_voxel_edit(cell,_catalog.get_voxel_id(&"leyforge:kiln"),0)
	_check(world.save(player,r.snapshot(),state.snapshot())==OK,"Current complete state atomic save")
	var loaded: LfeWorldSave=LfeWorldSave.new()
	_check(loaded.open_world("current",seed,true,_catalog,_root)==OK and loaded.creation_state==state.snapshot() and loaded.resource_state==r.snapshot(),"Complete save v3 exact reload")
	var original: String=FileAccess.get_file_as_string(world.get_primary_path())
	var envelope: Dictionary=JSON.parse_string(original)
	var payload: Dictionary=JSON.parse_string(envelope["payload_json"])
	for version: int in [1,2]:
		var id: String="migration_v%d" % version
		var old: Dictionary=payload.duplicate(true)
		old["metadata"]["world_id"]=id;old["metadata"]["save_version"]=version
		old.erase("creation");old["voxel_overrides"]=[]
		# Genuine historical fields: v1 has no resources; v2 stacks have no instance state.
		if version==1:old.erase("resources")
		else:
			var historical: LfeResourceState=LfeResourceState.new(_catalog)
			LfeItemTransactions.add(historical.inventory,&"leyforge:stone",7)
			historical.select(5)
			old["resources"]=historical.snapshot()
		var directory: String=_root.path_join(id);DirAccess.make_dir_recursive_absolute(directory)
		_write_envelope(directory.path_join("world.json"),old,version)
		var bytes: String=FileAccess.get_file_as_string(directory.path_join("world.json"))
		var migration: LfeWorldSave=LfeWorldSave.new()
		_check(migration.open_world(id,seed,true,_catalog,_root)==OK and migration.load_status.contains("migrated v%d" % version),"Historical v%d migrates" % version)
		_check(FileAccess.get_file_as_string(directory.path_join("world.json"))==bytes and migration.player_state==player,"Migration preserves historical bytes/player")
		if version==2:_check(migration.resource_state==old["resources"],"v2 resources/hotbar preserved")
		_check(migration.creation_state["survival"]["health"]==100 and migration.creation_state["objects"].is_empty(),"Migration safe Wave 4 defaults")
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
	var existing: LfeWorldSave=LfeWorldSave.new()
	_check(existing.open_world("existing_wave4",seed,true,_catalog,_root)==OK and existing.resource_state==r.snapshot(),"Existing Wave 4 v3 retains damaged tool/resources")
	var old_survival: Dictionary=existing.creation_state["survival"].duplicate(true);old_survival.erase("timing")
	var legacy_expected: LfeCreationState=LfeCreationState.new(_catalog);legacy_expected.restore(old_v3["creation"],r.snapshot())
	_check(old_survival==old_v3["creation"]["survival"] and existing.creation_state==legacy_expected.snapshot(),"Existing v3 preserves survival/construction/processing/source depletion")
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
		var corrupt: LfeWorldSave=LfeWorldSave.new()
		_check(corrupt.open_world("current",seed,true,_catalog,_root)!=OK and corrupt.save(player)!=OK,"Corrupt state fails closed: "+mutation)
	_write(world.get_primary_path(),original)
	_check(loaded.save(player,r.snapshot(),state.snapshot())==OK,"Valid save rotates previous copy")
	DirAccess.remove_absolute(world.get_primary_path())
	var recovered: LfeWorldSave=LfeWorldSave.new()
	_check(recovered.open_world("current",seed,true,_catalog,_root)==OK and recovered.load_status.contains("Recovered") and recovered.creation_state==state.snapshot(),"Previous copy recovers exact Wave 4 state")
	var isolated: LfeWorldSave=LfeWorldSave.new()
	_check(isolated.open_world("isolated",seed,true,_catalog,_root)==OK and isolated.creation_state["objects"].is_empty() and isolated.resource_state["inventory"].all(func(v: Variant)->bool:return v==null),"Same-seed world state independent")

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
	var state: LfeCreationState = LfeCreationState.new(_catalog);state.initialize_sources(184552221)
	var sources: Array = state.sources()
	_check(state.validate_source_layout(184552221),"Tree source identities/layout remain unchanged")
	var bare: Dictionary = LfeHarvestRules.evaluate(state.source_definition("fallen_oak"),{},_catalog)
	var wooden: Dictionary = LfeHarvestRules.evaluate(state.source_definition("fallen_oak"),LfeItemInstance.create(&"leyforge:wooden_axe",_catalog),_catalog)
	var stone: Dictionary = LfeHarvestRules.evaluate(state.source_definition("fallen_oak"),LfeItemInstance.create(&"leyforge:stone_axe",_catalog),_catalog)
	_check(float(bare["seconds"])>float(wooden["seconds"]) and float(wooden["seconds"])>float(stone["seconds"]),"Tree timing: manual slower than Wooden Axe, slower than Stone Axe")
	_check(state.add_object(&"leyforge:workbench",Vector3i(2,30,2),0) and state.can_remove(Vector3i(2,30,2)),"Workbench has no persistent hidden staging inventory")
	var restored: LfeCreationState = LfeCreationState.new(_catalog)
	_check(restored.restore(state.snapshot()) and restored.snapshot()==state.snapshot(),"Workbench persists identity/orientation without new save version")
