extends Node

var _world: LeyforgeWave1Playground
var _player: LeyforgeFirstPersonPlayer
var _terrain: VoxelTerrain
var _catalog: LfeBlockCatalog
var _tool: VoxelTool
var _phase: String = ""
var _out: String = ""
var _checks: int = 0
var _failures: Array[String] = []
var _report: Dictionary = {}
var _ledger: Dictionary = {}
var _built: Array = []
var _edits: Array = []
var _kiln: String = ""
var _rest: String = ""
var _home: Vector3i

func configure(world: LeyforgeWave1Playground, player: LeyforgeFirstPersonPlayer, terrain: VoxelTerrain, catalog: LfeBlockCatalog, _seed: int) -> void:
	_world=world;_player=player;_terrain=terrain;_catalog=catalog
	_tool=terrain.get_voxel_tool();_tool.set_channel(VoxelBuffer.CHANNEL_TYPE)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--wave4-run="):_phase=argument.trim_prefix("--wave4-run=")
		if argument.begins_with("--wave4-playtest-out="):_out=argument.trim_prefix("--wave4-playtest-out=")
	call_deferred("_run")

func _run() -> void:
	if not _world.is_runtime_ready():await _world.runtime_ready
	_player.set_runtime_ready(false)
	_check(DisplayServer.get_name()!="headless","Real rendered process/display")
	match _phase:
		"A":await _new_loop()
		"B":await _resume()
		"C":await _second_restart()
		"D":await _isolation()
		"M1","M2":await _migration()
		"N1","N2":await _migration_restart()
		_:_check(false,"Unknown acceptance phase")
	_report.merge({"phase":_phase,"checks":_checks,"passed":_failures.is_empty(),"failures":_failures,"world_id":_world.world_save.world_id,"seed":_world.active_seed,"runner":Engine.get_version_info()["string"],"setup_only":["Camera/viewer and player positioning at test interaction cells","Controlled environmental health damage command","Fixed-duration calls to the production simulation seam"],"state_injection":false})
	_write_report()
	for failure: String in _failures:push_error("Wave 4 rendered %s: %s" % [_phase,failure])
	print("WAVE_4_RENDERED_%s_%s checks=%d" % [_phase,"PASS" if _failures.is_empty() else "FAIL",_checks])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _new_loop() -> void:
	var r: LfeResourceState=_world.resources
	_check(r.inventory.snapshot().all(func(v: Variant)->bool:return v==null),"Normal world begins with empty inventory")
	var origin: Vector3=_player.global_position
	_player.set_runtime_ready(true)
	Input.action_press("move_forward");Input.action_press("sprint")
	await _frames(25)
	_world.advance_creation(1.0)
	Input.action_release("move_forward");Input.action_release("sprint")
	await _frames(4);_player.set_runtime_ready(false)
	_check(_player.global_position.distance_to(origin)>0.5 and float(_world.creation.survival.snapshot()["stamina"])<100,"Production movement and stamina exertion")
	await _gather(0)
	_world.toggle_crafting()
	await _capture("02_crafting.png")
	_world.close_inventory()
	_craft("saw_planks")
	# Open a narrow real terrain shaft; all material enters conserved drops.
	var height: int=LfeWave1TerrainRules.height_at(_world.active_seed,3,2)
	for y: int in range(height,height-6,-1):await _mine(Vector3i(3,y,2))
	_check(r.inventory.total(&"leyforge:stone")>=2,"Bare-hand early stone substrate")
	_craft("craft_stone_pickaxe")
	_equip("stone_pickaxe")
	var pick: Dictionary=r.equipment.stack_at(0)
	await _gather(12)
	await _gather(13)
	_check(int(r.equipment.stack_at(0)["durability"])==int(pick["durability"])-2,"Mining capability and exact durability loss")
	_craft("craft_stone_axe")
	_equip("stone_axe")
	await _gather(1);await _gather(2);await _gather(3)
	await _capture("01_gathering.png")
	for n: int in 12:_craft("saw_planks")
	_craft("craft_stone_shovel")
	_equip("stone_shovel")
	await _mine(Vector3i(4,LfeWave1TerrainRules.height_at(_world.active_seed,4,2),2))
	_craft("build_kiln");_craft("weave_rest_mat");_craft("build_storage_box")
	# A small built work area at the origin, using only gathered/crafted blocks.
	var base: int=0
	for x: int in range(-1,2):
		for z: int in range(-1,2):base=maxi(base,LfeWave1TerrainRules.height_at(_world.active_seed,x,z)+1)
	_home=Vector3i(0,base,0)
	_player.global_position=Vector3(5.5,base+1.05,0.5)
	for x: int in range(-1,2):
		for z: int in range(-1,2):await _place("oak_planks",_home+Vector3i(x,0,z))
	for y: int in [2,3]:
		for x: int in range(-1,2):
			for z: int in range(-1,2):
				if (abs(x)==1 or abs(z)==1) and not (x==0 and z==-1):await _place("oak_planks",_home+Vector3i(x,y,z))
	for x: int in range(-1,2):
		for z: int in range(-1,2):await _place("oak_planks",_home+Vector3i(x,4,z))
	await _place("rest_mat",_home+Vector3i.UP)
	await _place("kiln",_home+Vector3i(2,1,0))
	await _place("storage_box",_home+Vector3i(2,1,1))
	_kiln=_world.creation.object_at(_home+Vector3i(2,1,0))
	_rest=_world.creation.object_at(_home+Vector3i.UP)
	_player.global_position=Vector3(_home)+Vector3(0.5,2.05,0.5)
	_start_process()
	_world.creation_panel.open(_kiln)
	await _capture("03_workstation.png")
	_world.close_inventory()
	_world.advance_creation(8.0)
	_completed()
	_check(_world.transfer_object(_kiln,"output",0,2,true)==2,"Withdraw completed charcoal through authority")
	_craft("craft_lamp")
	await _place("lamp",_home+Vector3i(2,1,-1))
	await _recover_function(_home+Vector3i(2,1,-1))
	await _place("lamp",_home+Vector3i(2,1,-1))
	var storage_id: String=_world.creation.object_at(_home+Vector3i(2,1,1))
	_select("oak_planks")
	_check(_world.transfer_object(storage_id,"storage",r.selected_slot(),1,false)==1,"Actual constructed storage transfer")
	var previous: Dictionary=r.snapshot()
	await _aim(_home+Vector3i(2,1,1))
	_check(not _world.begin_harvest(_home+Vector3i(2,1,1)) and r.snapshot()==previous,"Filled storage cannot be broken into lost contents")
	_player.global_position=Vector3(_home)+Vector3(0.5,2.05,0.5)
	_check(_world.detect_shelter(),"Inventory-built enclosure provides real shelter")
	await _view_home()
	await _capture("04_shelter.png")
	await _gather(16);await _gather(18)
	_check(_world.damage_player(20),"Controlled environmental damage through authority")
	_world.advance_creation(5.0)
	_select("provisions")
	_check(_world.consume_selected(),"Production food/healing consumption")
	_adjust("leyforge:provisions",-1)
	_select("drinking_water")
	_check(_world.consume_selected(),"Production drink consumption")
	_adjust("leyforge:drinking_water",-1)
	_player.global_position=Vector3(_home)+Vector3(0.5,2.05,0.5)
	var fatigue: float=float(_world.creation.survival.snapshot()["fatigue"])
	_check(_world.begin_rest(_rest),"Constructed covered rest point starts recovery")
	_world.advance_creation(1.0)
	_check(float(_world.creation.survival.snapshot()["fatigue"])<fatigue and float(_world.creation.survival.snapshot()["health"])>85,"Rest recovers fatigue and health in real shelter")
	var retained: Dictionary = r.snapshot()
	_check(_world.damage_player(100) and not _world.creation.survival.alive(),"Environmental zero-health consequence")
	_world.advance_creation(0)
	_check(_world.creation.survival.alive() and r.snapshot()==retained,"Safe spawn recovery preserves every resource and tool instance")
	_player.global_position=Vector3(_home)+Vector3(0.5,2.05,0.5)
	await _capture("05_survival.png")
	_world._resting=false
	_start_process();_world.advance_creation(3.0)
	_check(float(_world.creation.station(_kiln).snapshot()["progress"])==3 and not _world.creation.can_remove(_home+Vector3i(2,1,0)),"Meaningful active process retained; active station protected")
	_equip("stone_pickaxe")
	_verify_accounting()
	await _stream()
	_player.global_position=Vector3(_home)+Vector3(0.5,2.05,0.5)
	await _view_home()
	_check(_world.request_save(),"Integrated Wave 4 explicit save")
	_snapshot_report()
	await _capture("06_saved.png")

func _resume() -> void:
	_restore_report(_read("A"))
	_verify_restored(_read("A"))
	await _capture("07_restart.png")
	_verify_accounting()
	_world.advance_creation(5.0)
	_completed()
	_check(_world.creation.station(_kiln).status()=="Idle","Restart resumes stored progress; completes once")
	_check(_world.transfer_object(_kiln,"output",0,2,true)==2,"Restored process outputs transferable")
	var durability: int=int(_world.resources.equipment.stack_at(0)["durability"])
	await _gather(14)
	_check(int(_world.resources.equipment.stack_at(0)["durability"])==durability-1,"Restored tool works with exact retained durability")
	_craft("saw_planks")
	_player.global_position=Vector3(_home)+Vector3(0.5,2.05,0.5)
	await _place("oak_planks",_home+Vector3i(0,0,-2))
	_verify_accounting()
	await _stream()
	_player.global_position=Vector3(_home)+Vector3(0.5,2.05,0.5)
	await _view_home()
	_check(_world.request_save(),"Post-restart transformations saved again")
	_snapshot_report()
	await _capture("08_completed.png")

func _second_restart() -> void:
	_restore_report(_read("B"));_verify_restored(_read("B"));_verify_accounting()
	_check(_world.creation.station(_kiln).status()=="Idle","Second restart retains completed process")
	_check(_world.request_save(),"Second restart save remains valid")

func _isolation() -> void:
	var a: Dictionary=_read("A")
	var r: LfeResourceState=_world.resources
	_check(_world.active_seed==int(a["seed"]) and _world.world_save.world_id!=a["world_id"],"Same seed independent world ID")
	_check(r.inventory.snapshot().all(func(v: Variant)->bool:return v==null) and r.equipment.snapshot()==[null,null] and r.drops().is_empty(),"Inventory/tools/durability/drops isolated")
	_check(_world.creation.objects().is_empty() and _world.world_save.overrides.count()==0 and _world.world_save.player_state.is_empty(),"Construction/stations/storage/processing isolated")
	_check(_world.creation.sources().all(func(v: Dictionary)->bool:return int(v["remaining"])>0) and _world.creation.survival.snapshot()["health"]==100,"Sources and survival isolated")
	await _capture("09_isolation.png")

func _migration() -> void:
	var version: int=int(_phase.right(1))
	_check(_world.world_save.load_status.contains("migrated v%d" % version),"Real process loads historical schema")
	var primary: String=_world.world_save.get_primary_path()
	var original: String=FileAccess.get_file_as_string(primary)
	var envelope: Dictionary=JSON.parse_string(original)
	_check(int(envelope["save_version"])==version,"Historical authority untouched on open")
	var old: Dictionary=JSON.parse_string(envelope["payload_json"])
	_check(_world.world_save.player_state==old["player"],"Historical player preserved")
	if version==2:
		_check(_world.resources.inventory.total(&"leyforge:stone")==7 and _world.resources.selected_slot()==5,"Historical v2 inventory/hotbar survives")
	_check(_world.creation.objects().is_empty() and _world.creation.survival.snapshot()["health"]==100,"Safe survival/workstation defaults")
	_check(_world.request_save(),"Explicit migration save writes v3")
	_check(FileAccess.get_file_as_string(_world.world_save.get_world_directory().path_join("world.json.previous"))==original,"Original historical authority retained")
	_snapshot_report()
	await _capture("10_migration_v1.png" if version==1 else "11_migration_v2.png")

func _migration_restart() -> void:
	var phase: String="M"+_phase.right(1)
	_verify_restored(_read(phase))
	_check(not _world.world_save.load_status.contains("migrated"),"Migrated current schema reload without repeated migration")

func _gather(index: int) -> void:
	var entry: Dictionary=_world.creation.sources()[index]
	var p: Array=entry["position"]
	_player.global_position=Vector3(float(p[0]),float(p[1])+0.65,float(p[2])-1.0)
	await _aim(Vector3i(Vector3(float(p[0]),float(p[1]),float(p[2])).floor()))
	var spec: Dictionary=_world.creation.source_definition(entry["source"])
	_check(_world.begin_source_harvest(entry["instance"]),"Begin production resource gathering: "+entry["source"])
	_check(_world.advance_harvest(2.0),"Complete authorized timed source gathering")
	_adjust(spec["content"],int(entry["remaining"]))

func _mine(cell: Vector3i) -> void:
	await _aim(cell)
	_player.global_position=Vector3(cell)+Vector3(2.5,2.05,0.5)
	var id: StringName=_catalog.canonical_id_for_voxel_id(_tool.get_voxel(cell))
	_check(_player.try_break_target(),"Player target starts timed voxel harvest")
	_check(_world.advance_harvest(2.0),"Voxel harvest commits after work")
	var drops: Array=_world.resources.drops()
	_check(not drops.is_empty(),"Harvest physically represents its output")
	for entry: Dictionary in drops:
		var stack: Dictionary=entry["stack"]
		_adjust(stack["content"],int(stack["quantity"]))
		_check(_world.resources.pickup(entry["instance"])==int(stack["quantity"]),"Production pickup exact")
	_edits.append({"position":[cell.x,cell.y,cell.z],"block":"leyforge:air"})
	_check(id!=&"leyforge:air","Gathered actual terrain resource")

func _craft(name: String) -> void:
	var recipe: Dictionary=_world.creation.recipes.definition("leyforge:"+name)
	_check(_world.craft_recipe("leyforge:"+name),"Production craft "+name)
	for entry: Dictionary in recipe["inputs"]:_adjust(entry["content"],-int(entry["quantity"]))
	for entry: Dictionary in recipe["outputs"]:_adjust(entry["content"],int(entry["quantity"]))

func _equip(name: String) -> void:
	var r: LfeResourceState=_world.resources
	if not r.equipment.stack_at(0).is_empty():
		_check(LfeItemTransactions.transfer(r.equipment,0,r.inventory,1)==1,"Unequip exact prior instance")
	var slot: int=_slot("leyforge:"+name)
	_world.inventory_panel.open()
	_world.inventory_panel._click_slot(r.inventory,slot,false,false)
	_world.inventory_panel._click_slot(r.equipment,0,false,false)
	_check(r.equipment.stack_at(0).get("content")=="leyforge:"+name,"Inventory interface equips tool")
	_world.close_inventory()

func _select(name: String) -> void:
	var r: LfeResourceState=_world.resources
	var slot: int=_slot("leyforge:"+name)
	if slot>=9:
		_check(LfeItemTransactions.swap(r.inventory,slot,r.inventory,8),"Move selected resource into actual hotbar")
		slot=8
	_check(r.select(slot),"Select production hotbar resource")

func _place(name: String,cell: Vector3i) -> void:
	_select(name);await _aim(cell)
	var before: int=_world.resources.inventory.total(StringName("leyforge:"+name))
	_check(_world.place_cell(cell),"Inventory-backed building "+name)
	_check(_world.resources.inventory.total(StringName("leyforge:"+name))==before-1,"Exact construction cost")
	_built.append({"position":[cell.x,cell.y,cell.z],"block":"leyforge:"+name})

func _start_process() -> void:
	_select("oak_heartwood")
	for n: int in 2:_check(_world.transfer_object(_kiln,"input",_world.resources.selected_slot(),1,false)==1,"Deposit actual process input")
	_check(_world.transfer_object(_kiln,"fuel",_world.resources.selected_slot(),1,false)==1,"Deposit actual fuel")
	_check(_world.start_process(_kiln,"leyforge:charcoal_burn"),"Start canonical fuelled process")
	_adjust("leyforge:oak_heartwood",-1) # Fuel transformed to committed process work.

func _completed() -> void:
	_check(_world.creation.station(_kiln).snapshot()["active"]=="","Process completed")
	_adjust("leyforge:oak_heartwood",-2);_adjust("leyforge:charcoal",2)

func _verify_accounting() -> void:
	for content: String in _ledger:
		var total: int=_world.resources.total(StringName(content))
		for entry: Dictionary in _world.creation.objects():
			var station: LfeWorkstation=_world.creation.station(entry["instance"])
			var storage: LfeInventory=_world.creation.storage(entry["instance"])
			if storage!=null:total+=storage.total(StringName(content))
			if station!=null:
				total+=station.input.total(StringName(content))+station.fuel.total(StringName(content))+station.output.total(StringName(content))
				var active: String=station.snapshot()["active"]
				if not active.is_empty():
					for ingredient: Dictionary in _world.creation.recipes.definition(active)["inputs"]:
						if ingredient["content"]==content:total+=int(ingredient["quantity"])
		for entry: Dictionary in _built:
			if entry["block"]==content:total+=1
		_check(total==int(_ledger[content]),"Exact transformation accounting "+content+" actual="+str(total)+" expected="+str(_ledger[content]))

func _stream() -> void:
	var before: Dictionary=_world.creation.snapshot()
	var resources: Dictionary=_world.resources.snapshot()
	var camera: Camera3D=_player.get_camera();camera.top_level=true;camera.global_position=Vector3(340,60,340)
	var unloaded: bool=false
	for frame: int in 360:
		await get_tree().physics_frame
		if not _tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(_home)):
			unloaded=true;break
	_check(unloaded,"Construction area really streams out")
	for entry: Dictionary in _built:
		var p: Array=entry["position"];var cell: Vector3i=Vector3i(int(p[0]),int(p[1]),int(p[2]))
		await _aim(cell)
		_check(_tool.get_voxel(cell)==_catalog.get_voxel_id(StringName(entry["block"])),"Streamed constructed voxel exact")
	_check(_world.creation.snapshot()==before and _world.resources.snapshot()==resources,"Stream-out/back preserves station, survival, storage, tools and drops")
	var expected_nodes: int=_world.creation.objects().size()
	for entry: Dictionary in _world.creation.sources():
		if int(entry["remaining"])>0:expected_nodes+=1
	_check(_world.creation_presenter._nodes.size()==expected_nodes,"Exactly one functional/source node per live identity")

func _verify_restored(report: Dictionary) -> void:
	var resources: LfeResourceState=LfeResourceState.new(_catalog)
	_check(resources.restore(report["resources"]),"Saved resource report valid")
	var creation: LfeCreationState=LfeCreationState.new(_catalog)
	_check(creation.restore(report["creation"],resources.snapshot()),"Saved Wave 4 report valid")
	_check(_world.resources.snapshot()==resources.snapshot(),"Fresh process exact inventory/tools/durability/storage/drops")
	_check(_world.creation.snapshot()==creation.snapshot(),"Fresh process exact survival/orientation/process progress/source depletion")
	_check(_world.world_save.player_state==report["player"],"Fresh process player transform exact")
	for entry: Dictionary in report.get("built",[]):
		var p: Array=entry["position"];var cell: Vector3i=Vector3i(int(p[0]),int(p[1]),int(p[2]))
		_check(_world._voxel_id_at(cell)==_catalog.get_voxel_id(StringName(entry["block"])),"Fresh process construction exact")

func _snapshot_report() -> void:
	_report.merge({"resources":_world.resources.snapshot(),"creation":_world.creation.snapshot(),"player":_world.world_save.player_state,"ledger":_ledger,"built":_built,"edits":_edits,"kiln":_kiln,"rest":_rest,"home":[_home.x,_home.y,_home.z]})

func _restore_report(report: Dictionary) -> void:
	_ledger=report["ledger"].duplicate(true);_built=report["built"].duplicate(true);_edits=report["edits"].duplicate(true)
	_kiln=report["kiln"];_rest=report["rest"]
	var p: Array=report["home"];_home=Vector3i(int(p[0]),int(p[1]),int(p[2]))

func _adjust(content: String,quantity: int) -> void:
	_ledger[content]=int(_ledger.get(content,0))+quantity

func _slot(content: String) -> int:
	for slot: int in _world.resources.inventory.capacity():
		if _world.resources.inventory.stack_at(slot).get("content")==content:return slot
	return -1

func _aim(cell: Vector3i) -> void:
	var camera: Camera3D=_player.get_camera();camera.top_level=true
	camera.global_position=Vector3(cell)+Vector3(0.5,3.5,0.5)
	camera.look_at(Vector3(cell)+Vector3.ONE*0.5,Vector3.FORWARD)
	var loaded: bool=false
	for frame: int in 360:
		await get_tree().physics_frame
		if _tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(cell)):
			loaded=true;break
	_check(loaded,"Interaction target streams in")
	await _frames(2)

func _view_home() -> void:
	var camera: Camera3D=_player.get_camera();camera.top_level=true
	camera.global_position=Vector3(_home)+Vector3(6,6,-7)
	camera.look_at(Vector3(_home)+Vector3(0.5,2,0.5),Vector3.UP)
	await _frames(3)

func _frames(count: int) -> void:
	for frame: int in count:await get_tree().physics_frame

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(_out.path_join(name))==OK,"Rendered evidence "+name)

func _read(phase: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_out.path_join("run_%s.json" % phase)))

func _write_report() -> void:
	var file: FileAccess=FileAccess.open(_out.path_join("run_%s.json" % _phase),FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(_report,"\t",true,true)+"\n");file.flush()
	else:push_error("Cannot write rendered report")

func _check(condition: bool,message: String) -> void:
	_checks+=1
	if not condition:_failures.append(message)


func _recover_function(cell: Vector3i) -> void:
	var original: String = _world.creation.object_at(cell)
	await _aim(cell)
	_check(_world.begin_harvest(cell) and _world.advance_harvest(2),"Empty functional block follows production recovery rule")
	_check(_world.creation.object_at(cell).is_empty(),"Breaking removes durable functional identity")
	for entry: Dictionary in _world.resources.drops():
		_check(_world.resources.pickup(entry["instance"])==1 and entry["stack"]["content"]=="leyforge:lamp","Recovery drop returns exactly its crafted object")
	for index: int in range(_built.size()-1,-1,-1):
		if _built[index]["position"]==[cell.x,cell.y,cell.z]:_built.remove_at(index)
	_check(not _world.creation_presenter._nodes.has(original),"Recovered object has no duplicate presentation")
