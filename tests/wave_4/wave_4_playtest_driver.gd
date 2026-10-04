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
var _bench: String = ""
var _tree_times: Array[float] = []
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
	_report.merge({"phase":_phase,"checks":_checks,"passed":_failures.is_empty(),"failures":_failures,"world_id":_world.world_save.world_id,"seed":_world.active_seed,"runner":Engine.get_version_info()["string"],"setup_only":["Camera/viewer and player positioning at test interaction cells","Controlled environmental health damage command","Fixed-duration calls to the production simulation seam"],"state_injection":false,"survival_profile":_world.creation.survival.profile_name,"survival_acceleration":false,"tree_work_seconds":_tree_times,"worldgen_version":_world.world_save.worldgen_version})
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
	await _tree_demonstration()
	await _chop_logs(6)
	_key(KEY_I)
	_check(_world.inventory_panel.crafting!=null and _world.inventory_panel.crafting.size==2 and _world.inventory_panel._panel.visible,"I opens backpack/hotbar/equipment and personal grid in one shell")
	await _capture("02_crafting.png")
	_world.close_inventory()
	await _craft("saw_planks")
	await _craft("build_workbench")
	await _bootstrap_bench()
	await _craft("saw_planks")
	await _craft("saw_planks")
	await _craft("split_oak_sticks")
	await _personal_grid_checks()
	await _craft("craft_wooden_pickaxe")
	await _craft("split_oak_sticks")
	await _craft("craft_wooden_axe")
	_equip("wooden_axe")
	await _chop_logs(6)
	_equip("wooden_pickaxe")
	# Open a narrow real terrain shaft; all material enters conserved drops.
	var height: int=LfeWave1TerrainRules.height_at(_world.active_seed,3,2)
	for y: int in range(height,height-7,-1):await _mine(Vector3i(3,y,2))
	_check(r.inventory.total(&"leyforge:stone")>=3,"Fresh wooden pickaxe obtains ordinary Stone without granted Stone")
	await _craft("saw_planks")
	await _craft("craft_stone_pickaxe")
	_equip("stone_pickaxe")
	var pick: Dictionary=r.equipment.stack_at(0)
	await _hold_source_demo(12)
	await _gather(12)
	await _gather(13)
	_check(int(r.equipment.stack_at(0)["durability"])==int(pick["durability"])-2,"Mining capability and exact durability loss")
	await _craft("craft_stone_axe")
	_equip("stone_axe")
	await _chop_logs(12)
	_check(_tree_times.has(1.0) and _tree_times.has(1.0/1.5) and _tree_times.has(1.0/3.0),"Rendered tree work timing improves manual -> Wooden Axe -> Stone Axe")
	await _resource_view(4)
	await _capture("01_gathering.png")
	await _resource_view(15)
	await _capture("14_resource_scale.png")
	await _dense_stone_demonstration(15)
	for n: int in 13:await _craft("saw_planks")
	await _craft("split_oak_sticks")
	await _craft("craft_wooden_shovel")
	await _craft("split_oak_sticks")
	await _craft("craft_stone_shovel")
	_equip("stone_shovel")
	await _mine(Vector3i(4,LfeWave1TerrainRules.height_at(_world.active_seed,4,2),2))
	await _craft("build_kiln");await _craft("weave_rest_mat");await _craft("build_storage_box")
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
	await _rmb_object(_home+Vector3i(2,1,0),_kiln)
	_world.advance_creation(2.0)
	await _frames(3)
	await _capture("03_workstation.png")
	_world.close_inventory()
	_world.advance_creation(8.0)
	_completed()
	_world.inventory_panel.open_context(_kiln)
	await _capture("13_furnace_completed.png")
	_world.close_inventory()
	_check(_world.transfer_object(_kiln,"output",0,2,true)==2,"Withdraw completed charcoal through authority")
	await _craft("craft_lamp")
	await _place("lamp",_home+Vector3i(2,1,-1))
	await _recover_function(_home+Vector3i(2,1,-1))
	await _place("lamp",_home+Vector3i(2,1,-1))
	var storage_id: String=_world.creation.object_at(_home+Vector3i(2,1,1))
	await _rmb_object(_home+Vector3i(2,1,1),storage_id)
	_select("oak_planks")
	_check(_world.transfer_object(storage_id,"storage",r.selected_slot(),1,false)==1,"Actual constructed storage transfer")
	_world.close_inventory()
	var previous: Dictionary=r.snapshot()
	await _aim(_home+Vector3i(2,1,1))
	var storage_camera: Camera3D = _player.get_camera();storage_camera.global_position=Vector3(_home+Vector3i(2,1,1))+Vector3(0.5,1.4,0.5);storage_camera.look_at(Vector3(_home+Vector3i(2,1,1))+Vector3.ONE*0.5,Vector3.FORWARD)
	_held(true)
	_check(not _world.begin_harvest(_home+Vector3i(2,1,1)) and r.snapshot()==previous,"Filled storage cannot be broken into lost contents")
	_held(false)
	_player.global_position=Vector3(_home)+Vector3(0.5,2.05,0.5)
	_check(_world.detect_shelter(),"Inventory-built enclosure provides real shelter")
	await _view_home()
	await _capture("04_shelter.png")
	await _gather(16);await _gather(18)
	_check(_world.damage_player(20),"Controlled environmental damage through authority")
	_world.advance_creation(5.0)
	_select("provisions")
	_check(_world.consume_selected(),"Production nourishment consumption without instant health bonus")
	_adjust("leyforge:provisions",-1)
	_select("drinking_water")
	_check(not _world.consume_selected(),"Standard thirst is disabled; water serving retained")
	_player.global_position=Vector3(_home)+Vector3(0.5,2.05,0.5)
	var health_before_rest: float=float(_world.creation.survival.snapshot()["health"])
	var fatigue: float=float(_world.creation.survival.snapshot()["fatigue"])
	_check(_world.begin_rest(_rest),"Constructed covered rest point starts recovery")
	_world.advance_creation(30.0)
	_check(float(_world.creation.survival.snapshot()["fatigue"])<fatigue and float(_world.creation.survival.snapshot()["health"])>health_before_rest,"Rest recovers fatigue and health in real shelter")
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
	await _drop_demo()
	await _rmb_place()
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
	await _craft("saw_planks")
	_player.global_position=Vector3(_home)+Vector3(0.5,2.05,0.5)
	await _place("oak_planks",_home+Vector3i(0,0,-4))
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
	var entry: Dictionary=_world.creation.sources()[index-12 if _world.world_save.worldgen_version==2 else index]
	var p: Array=entry["position"]
	_player.global_position=Vector3(float(p[0]),float(p[1])+0.65,float(p[2])-1.0)
	var center: Vector3=Vector3(float(p[0]),floorf(float(p[1]))+0.3,float(p[2]))
	await _aim_point(center)
	if entry["source"]=="fallen_oak":
		var node: Node3D = _world.creation_presenter._nodes[entry["instance"]]
		var camera: Camera3D = _player.get_camera();camera.global_position=center+Vector3.UP*(int(node.get_meta("trunk_height"))+2)
		camera.look_at(center,Vector3.FORWARD);await _frames(2)
	_player._update_targeting()
	_check(_player.target_source()==entry["instance"],"Crosshair/highlight resolves actual physical source")
	var spec: Dictionary=_world.creation.source_definition(entry["source"])
	var before: Dictionary=_world.creation.survival.snapshot()
	_held(true)
	_check(_player.try_break_target(),"LMB production path starts source gather: "+entry["source"])
	if entry["source"]=="fallen_oak":
		var seconds: float = float(_world._harvest.get("seconds",0))
		_tree_times.append(seconds)
		_check(not _world.advance_harvest(seconds/2) and _world.creation.source(entry["instance"])["remaining"]==entry["remaining"],"Tree remains before timed work completes")
	_check(_world.advance_harvest(2.0),"Complete authorized timed source gathering")
	_held(false)
	if entry["source"]=="fallen_oak":
		await _frames(2)
		_check(not _world.creation_presenter._nodes.has(entry["instance"]),"Depleted tree removes trunk and canopy together; no ghost leaves")
	_check(_world.creation.survival.snapshot()["stamina"]==before["stamina"],"Routine source gathering costs no Standard stamina")
	_adjust(spec["content"],int(entry["remaining"]))

func _mine(cell: Vector3i) -> void:
	await _aim(cell)
	var camera: Camera3D = _player.get_camera();camera.global_position=Vector3(cell)+Vector3(0.5,1.4,0.5)
	camera.look_at(Vector3(cell)+Vector3.ONE*0.5,Vector3.FORWARD);await _frames(2)
	_player.global_position=Vector3(cell)+Vector3(2.5,2.05,0.5)
	var id: StringName=_catalog.canonical_id_for_voxel_id(_tool.get_voxel(cell))
	_held(true)
	_check(_player.try_break_target(),"Player target starts timed voxel harvest")
	_check(_world.advance_harvest(2.0),"Voxel harvest commits after work")
	_held(false)
	var drops: Array=_world.resources.drops()
	_check(not drops.is_empty(),"Harvest physically represents its output")
	for entry: Dictionary in drops:
		var stack: Dictionary=entry["stack"]
		_adjust(stack["content"],int(stack["quantity"]))
		_check(_world.resources.pickup(entry["instance"])==int(stack["quantity"]),"Production pickup exact")
	_edits.append({"position":[cell.x,cell.y,cell.z],"block":"leyforge:air"})
	_check(id!=&"leyforge:air","Gathered actual terrain resource")

func _craft(name: String) -> void:
	var recipe: Dictionary = _world.creation.recipes.definition("leyforge:"+name)
	if recipe["context"]=="workbench":
		for entry: Dictionary in _world.creation.objects():
			if entry["content"]=="leyforge:workbench":
				_bench=entry["instance"]
				var p: Array = entry["cell"];var cell: Vector3i = Vector3i(int(p[0]),int(p[1]),int(p[2]))
				_world.close_inventory();_player.global_position=Vector3(cell)+Vector3(1.7,1.05,0.5)
				await _aim(cell)
				_check(_player.try_place_target() and _world.inventory_panel._object==_bench,"RMB opens same shell with Workbench context")
				break
	else:_key(KEY_C)
	var panel: LeyforgeInventoryPanel = _world.inventory_panel
	if panel.crafting==null:_check(false,"Real crafting grid exists for "+name);return
	_check(panel.crafting.size==int(recipe["grid"]["size"]),"Recipe uses its required 2x2/3x3 context: "+name)
	await _stage_recipe(recipe)
	var match: Dictionary = panel.crafting.preview()
	_check(match.get("recipe")==recipe["id"],"Real staged cells match canonical pattern: "+name)
	if name=="craft_wooden_pickaxe":await _capture("16_workbench_grid.png")
	if name=="build_workbench":await _capture("15_personal_grid.png")
	var before: Dictionary = _world.resources.snapshot()
	panel._output.pressed.emit()
	_check(_world.resources.snapshot()!=before and panel.crafting.inventory.snapshot().all(func(v:Variant)->bool:return v==null),"Taking output consumes exact staged ingredients: "+name)
	_check(_world.close_inventory(),"Close safely returns any remaining staging")
	for entry: Dictionary in recipe["inputs"]:_adjust(entry["content"],-int(entry["quantity"]))
	for entry: Dictionary in recipe["outputs"]:_adjust(entry["content"],int(entry["quantity"]))

func _stage_recipe(recipe: Dictionary) -> void:
	var panel: LeyforgeInventoryPanel = _world.inventory_panel
	var placements: Array = []
	if recipe["grid"]["type"]=="shaped":
		for y: int in recipe["grid"]["pattern"].size():
			var row: String = recipe["grid"]["pattern"][y]
			for x: int in row.length():
				if row[x]!=" ":placements.append({"slot":y*panel.crafting.size+x,"content":recipe["grid"]["keys"][row[x]],"quantity":1})
	else:
		for index: int in recipe["inputs"].size():
			var entry: Dictionary = recipe["inputs"][index]
			placements.append({"slot":index,"content":entry["content"],"quantity":int(entry["quantity"])})
	for placement: Dictionary in placements:
		var source: int = _slot(placement["content"])
		if source<0:_check(false,"Gathered ingredients exist: "+placement["content"]);continue
		var exact: int = source
		if int(_world.resources.inventory.stack_at(source)["quantity"])!=int(placement["quantity"]):
			for slot: int in _world.resources.inventory.capacity():
				if _world.resources.inventory.stack_at(slot).is_empty():exact=slot;break
			_check(LfeItemTransactions.transfer(_world.resources.inventory,source,_world.resources.inventory,int(placement["quantity"]),exact)==int(placement["quantity"]),"Conserved exact ingredient stack preparation")
		_ui_slot(_world.resources.inventory,exact);_ui_slot(panel.crafting.inventory,int(placement["slot"]))
		_check(panel.crafting.inventory.stack_at(int(placement["slot"])).get("content")==placement["content"],"Actual ingredient slot click stages content")
	panel._refresh()

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
	_world.inventory_panel.open_context(_kiln)
	var station: LfeWorkstation=_world.creation.station(_kiln)
	for channel: String in ["input","fuel"]:
		var count: int=2 if channel=="input" else 1
		var source: int=_slot("leyforge:oak_heartwood")
		var empty: int=-1
		for slot: int in _world.resources.inventory.capacity():
			if _world.resources.inventory.stack_at(slot).is_empty():empty=slot;break
		_check(LfeItemTransactions.transfer(_world.resources.inventory,source,_world.resources.inventory,count,empty)==count,"Prepare exact units with conserved inventory transfer")
		if channel=="fuel":
			_ui_slot(_world.resources.inventory,empty,false,true) # Actual quick-transfer handler.
		else:
			_ui_slot(_world.resources.inventory,empty)
			_ui_slot(station.input,0)
		_check((station.input if channel=="input" else station.fuel).total(&"leyforge:oak_heartwood")==count,"Actual furnace slot interaction: "+channel)
	_world.inventory_panel._body.find_child("StartProcess",true,false).pressed.emit()
	_check(station.snapshot()["active"]=="leyforge:charcoal_burn","Fire kiln UI starts authoritative reserved process")
	_world.close_inventory()
	_adjust("leyforge:oak_heartwood",-1)

func _ui_slot(inventory: LfeInventory, slot: int, split: bool=false, shift: bool=false) -> void:
	for entry: Dictionary in _world.inventory_panel._buttons:
		if entry["inventory"]==inventory and entry["slot"]==slot:
			var event: InputEventMouseButton=InputEventMouseButton.new()
			event.button_index=MOUSE_BUTTON_RIGHT if split else MOUSE_BUTTON_LEFT
			event.pressed=true;event.shift_pressed=shift
			entry["button"].gui_input.emit(event)
			return
	_check(false,"Requested real UI slot exists")

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
	var original_player: Vector3=_player.global_position
	_player.global_position=Vector3(340,60,340)
	var camera: Camera3D=_player.get_camera();camera.top_level=true;camera.global_position=Vector3(340,60,340)
	var unloaded: bool=false
	for frame: int in 360:
		await get_tree().physics_frame
		if not _tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(_home)):
			unloaded=true;break
	_check(unloaded,"Construction area really streams out")
	await _frames(8)
	_world.creation_presenter.sync();_world.resource_presenter.sync()
	await _frames(2)
	_check(_world.creation_presenter.get_child_count()==0 and _world.resource_presenter.get_child_count()==0,"No physical child Nodes remain after dematerialisation")
	_check(_world.creation_presenter._nodes.is_empty() and _world.resource_presenter._nodes.is_empty() and _world.resource_presenter._crates.is_empty(),"All source/drop/functional/crate Nodes dematerialise with unloaded terrain")
	_check(_world.creation.snapshot()==before and _world.resources.snapshot()==resources,"Unloading presentation retains authoritative records exactly")

	var distant: Array[Dictionary] = LfeStarterTreeRules.candidates(_world.active_seed,Vector2i(320,320),Vector2i(360,360))
	_check(not distant.is_empty(),"Coordinate generation supplies trees beyond the origin source region")
	if not distant.is_empty():
		var base: Vector3i = distant[0]["base"];await _aim(base)
		_check(_tool.get_voxel(base)==11 and _tool.get_voxel(base+Vector3i.UP)==11,"Real distant chunk contains naturally generated trunk voxels")
		await _voxel_tree_view(distant[0]);await _capture("21_distant_woodland.png")
	_player.global_position=original_player
	for entry: Dictionary in _built:
		var p: Array=entry["position"];var cell: Vector3i=Vector3i(int(p[0]),int(p[1]),int(p[2]))
		await _aim(cell)
		_check(_tool.get_voxel(cell)==_catalog.get_voxel_id(StringName(entry["block"])),"Streamed constructed voxel exact at "+str(cell))
	_verify_tree_cells(true)
	_check(_world.creation.snapshot()==before and _world.resources.snapshot()==resources,"Stream-out/back preserves station, survival, storage, tools and drops")
	var expected_nodes: int=_world.creation.objects().size()
	for entry: Dictionary in _world.creation.sources():
		if int(entry["remaining"])>0:expected_nodes+=1
	_world.creation_presenter.sync();_world.resource_presenter.sync()
	_check(_world.creation_presenter._nodes.size()==expected_nodes,"Exactly one relevant functional/source node per live identity")
	_check(_world.resource_presenter._nodes.size()==_world.resources.drops().size(),"Drops rematerialise exactly once from retained logical records")

func _verify_restored(report: Dictionary) -> void:
	_tree_kept=report.get("tree_kept",[]).duplicate(true)
	_edits=report.get("edits",[]).duplicate(true)
	_verify_tree_cells(false)
	_check(_world.world_save.worldgen_version==report.get("worldgen_version",1),"Fresh process retains stored generator version")
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
	_report.merge({"resources":_world.resources.snapshot(),"creation":_world.creation.snapshot(),"player":_world.world_save.player_state,"ledger":_ledger,"built":_built,"edits":_edits,"kiln":_kiln,"rest":_rest,"home":[_home.x,_home.y,_home.z],"tree_kept":_tree_kept,"tree_mined":_tree_mined})

func _restore_report(report: Dictionary) -> void:
	_tree_kept=report.get("tree_kept",[]).duplicate(true);_tree_mined=report.get("tree_mined",[]).duplicate(true)
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
	var camera: Camera3D = _player.get_camera();camera.global_position=Vector3(cell)+Vector3(0.5,1.4,0.5);camera.look_at(Vector3(cell)+Vector3.ONE*0.5,Vector3.FORWARD)
	_held(true)
	_check(_world.begin_harvest(cell) and _world.advance_harvest(2),"Empty functional block follows production recovery rule")
	_held(false)
	_check(_world.creation.object_at(cell).is_empty(),"Breaking removes durable functional identity")
	for entry: Dictionary in _world.resources.drops():
		_check(_world.resources.pickup(entry["instance"])==1 and entry["stack"]["content"]=="leyforge:lamp","Recovery drop returns exactly its crafted object")
	for index: int in range(_built.size()-1,-1,-1):
		if _built[index]["position"]==[cell.x,cell.y,cell.z]:_built.remove_at(index)
	_check(not _world.creation_presenter._nodes.has(original),"Recovered object has no duplicate presentation")


func _aim_point(point: Vector3) -> void:
	var camera: Camera3D=_player.get_camera();camera.top_level=true
	camera.global_position=point+Vector3(0,3.0,0)
	camera.look_at(point,Vector3.FORWARD)
	var cell: Vector3i=Vector3i(point.floor())
	for frame: int in 360:
		await get_tree().physics_frame
		if _tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(cell)):break
	_world.creation_presenter.sync();_world.resource_presenter.sync()
	await _frames(4)

func _rmb_object(cell: Vector3i,id: String) -> void:
	await _aim(cell)
	var before: Dictionary=_world.resources.snapshot()
	var overrides: int=_world.world_save.overrides.count()
	_check(_player.try_place_target() and _world.inventory_panel._object==id and _player.inventory_open,"RMB highlighted functional object opens slot UI")
	_check(_world.resources.snapshot()==before and _world.world_save.overrides.count()==overrides,"RMB interaction wins over selected block placement")
	_world.close_inventory()
	# Reopen for the next screenshot/action using the same player-facing path.
	_check(_player.try_place_target(),"Repeated RMB remains usable")

func _rmb_place() -> void:
	_world.close_inventory()
	_select("oak_planks")
	_player.global_position=Vector3(_home)+Vector3(0.5,2.05,0.5)
	await _aim(_home+Vector3i(0,0,-2))
	_player._update_targeting()
	var cell: Vector3i=_player.get_placement_cell()
	var before: int=_world.resources.inventory.total(&"leyforge:oak_planks")
	_check(_player.try_place_target() and _world.resources.inventory.total(&"leyforge:oak_planks")==before-1,"RMB still places when no highlighted interactable has priority")
	_built.append({"position":[cell.x,cell.y,cell.z],"block":"leyforge:oak_planks"})

func _drop_demo() -> void:
	_world.close_inventory()
	_select("oak_planks")
	_player.global_position=Vector3(_home)+Vector3(4,2,3)
	_check(_world.drop_selected(),"Production drop command creates first conserved drop")
	_player.global_position.x+=0.8
	_check(_world.drop_selected(),"Production drop command creates nearby compatible drop")
	_world.resource_presenter.sync()
	var records: Dictionary=_world.resources.snapshot()
	var id: String=_world.resources.drops()[0]["instance"]
	var visual: MeshInstance3D=_world.resource_presenter._nodes[id].get_node("Visual")
	var camera: Camera3D=_player.get_camera();camera.top_level=true
	camera.global_position=_world.resource_presenter._nodes[id].global_position+Vector3(1.8,1.6,-1.8)
	camera.look_at(_world.resource_presenter._nodes[id].global_position+Vector3.UP*0.12,Vector3.UP)
	_player._update_targeting()
	await _drop_view(_world.resource_presenter._nodes[id].global_position)
	await _capture("12_drop_before.png")
	var transform: Transform3D=visual.transform
	await _frames(35)
	_check(visual.transform!=transform and _world.resources.snapshot()==records,"Visible bob/rotation leave logical position and dirty state unchanged")
	var positions: Array=_world.resources.drops().map(func(v:Dictionary)->Array:return v["position"])
	_world.resources.advance_drop_clusters(1,_world.region_relevant,_world.drop_path_clear,_world.drop_rest_position)
	_check(_world.resources.drops().map(func(v:Dictionary)->Array:return v["position"])!=positions,"Nearby drops drift slowly through clear local space")
	for tick: int in 60:_world.resources.advance_drop_clusters(0.5,_world.region_relevant,_world.drop_path_clear,_world.drop_rest_position)
	_world.resource_presenter.sync()
	_check(_world.resources.drops().size()==1 and _world.resources.drops()[0]["stack"]["quantity"]==2,"Compatible drop convergence merges without losing quantity")
	var shown: Array = _world.resources.drops()[0]["position"]
	await _drop_view(Vector3(float(shown[0]),float(shown[1]),float(shown[2])))
	await _capture("12_drop_motion.png")
	# Remove the real loaded support through LMB, retaining the conserved planks.
	var merged: Dictionary = _world.resources.drops()[0]
	var resting: Array = merged["position"]
	var old_position: Vector3 = Vector3(float(resting[0]),float(resting[1]),float(resting[2]))
	var support: Vector3i = Vector3i(old_position.floor())+Vector3i.DOWN
	var prior: Array = _world.resources.drops().map(func(v:Dictionary)->String:return v["instance"])
	await _aim(support)
	camera.global_position=Vector3(support)+Vector3(0.5,1.4,0.5)
	camera.look_at(Vector3(support)+Vector3.ONE*0.5,Vector3.FORWARD)
	_player.global_position=Vector3(support)+Vector3(2.5,2.05,0.5);await _frames(2)
	_held(true)
	_check(_player.try_break_target() and _world.advance_harvest(2) and _tool.get_voxel(support)==0,"LMB removes the actual terrain supporting a drop")
	_held(false)
	for entry: Dictionary in _world.resources.drops():
		if prior.has(entry["instance"]):continue
		var stack: Dictionary = entry["stack"]
		_adjust(stack["content"],int(stack["quantity"]))
		_check(_world.resources.pickup(entry["instance"])==int(stack["quantity"]),"Support harvest produces and conserves only its own output")
	_edits.append({"position":[support.x,support.y,support.z],"block":"leyforge:air"})
	_world.resources.advance_drop_clusters(0.1,_world.region_relevant,_world.drop_path_clear,_world.drop_rest_position)
	var lowered: Dictionary = _world.resources.drop(merged["instance"])
	var lp: Array = lowered.get("position",resting)
	var position: Vector3 = Vector3(float(lp[0]),float(lp[1]),float(lp[2]))
	_check(position.y<old_position.y and position==_world.drop_rest_position(position),"Removing support resettles the same drop downward onto actual terrain")
	_check(lowered.get("stack",{})==merged["stack"] and _world.resources.drops().size()==1,"Ground correction retains exact drop identity and two-unit quantity")
	_world.resource_presenter.sync();await _drop_view(position)
	await _capture("22_drop_resettled.png")
	_verify_accounting()


func _resource_view(index: int) -> void:
	if index<12 and _world.world_save.worldgen_version==2:
		await _voxel_tree_view(_local_trees()[4])
		return
	var p: Array=_world.creation.sources()[index-12 if _world.world_save.worldgen_version==2 else index]["position"]
	var point: Vector3=Vector3(float(p[0]),floorf(float(p[1]))+0.3,float(p[2]))
	await _aim_point(point)
	var camera: Camera3D=_player.get_camera()
	camera.global_position=point+Vector3(5,4,-5) if index<12 else point+Vector3(2.5,2,-2.5)
	camera.look_at(point+Vector3.UP*1.7 if index<12 else point,Vector3.UP)
	_player._update_targeting()
	await _frames(3)


func _key(key: Key) -> void:
	var event: InputEventKey = InputEventKey.new();event.keycode=key;event.pressed=true
	_player._unhandled_input(event)

func _bootstrap_bench() -> void:
	var y: int = LfeWave1TerrainRules.height_at(_world.active_seed,0,-3)+1
	var cell: Vector3i = Vector3i(0,y,-3)
	_player.global_position=Vector3(cell)+Vector3(1.8,1.05,0.5)
	_select("workbench");await _aim(cell-Vector3i.UP)
	_player._update_targeting();var actual: Vector3i = _player.get_placement_cell()
	_check(_player.try_place_target(),"Fresh Workbench uses normal RMB inventory-backed placement")
	_bench=_world.creation.object_at(actual)
	_check(not _bench.is_empty(),"Placed Workbench has persistent functional identity")
	_built.append({"position":[actual.x,actual.y,actual.z],"block":"leyforge:workbench"})
	await _rmb_object(actual,_bench)
	_check(_world.inventory_panel.crafting.size==3,"Same inventory shell exposes nine Workbench staging slots")
	_world.close_inventory()

func _personal_grid_checks() -> void:
	_key(KEY_I)
	var panel: LeyforgeInventoryPanel = _world.inventory_panel
	var before: Dictionary = _world.resources.snapshot()
	# The exact tool's materials exist, but the personal context cannot provide it.
	var source: int = _slot("leyforge:oak_planks")
	_ui_slot(_world.resources.inventory,source);_ui_slot(panel.crafting.inventory,0)
	_ui_slot(_world.resources.inventory,_slot("leyforge:oak_stick"));_ui_slot(panel.crafting.inventory,1)
	_check(panel.crafting.preview().is_empty() and panel._output.disabled,"Invalid personal arrangement cannot preview a 3x3 tool")
	_check(_world.close_inventory() and _world.resources.snapshot()==before,"Closing populated 2x2 restores exact resources/identities")
	await _resource_view(4)
	await _capture("17_tree_variation.png")

var _tree_kept: Array = []
var _tree_mined: Array = []

func _local_trees() -> Array[Dictionary]:
	var trees: Array[Dictionary] = LfeStarterTreeRules.candidates(_world.active_seed,Vector2i(-40,-40),Vector2i(40,40))
	trees.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Vector3(a["base"]).length_squared()<Vector3(b["base"]).length_squared())
	return trees

func _voxel_tree_view(tree: Dictionary) -> void:
	var base: Vector3i = tree["base"]
	await _aim(base)
	var camera: Camera3D = _player.get_camera()
	camera.global_position=Vector3(base)+Vector3(7,5,-8)
	camera.look_at(Vector3(base)+Vector3(0.5,2.5,0.5),Vector3.UP)
	await _frames(3)

func _tree_demonstration() -> void:
	_check(_world.world_save.worldgen_version==2 and _world.creation.sources().all(func(v:Dictionary)->bool:return v["source"]!="fallen_oak"),"Fresh production v2 world uses voxel timber without finite tree sources")
	var trees: Array[Dictionary] = _local_trees()
	_check(trees.size()>15,"Several naturally distributed generated trees surround the starter region")
	if trees.is_empty():return
	var tree: Dictionary = trees[0];var base: Vector3i = tree["base"]
	_tree_mined=[base.x,base.y,base.z]
	await _voxel_tree_view(tree);await _capture("18_generated_woodland.png")
	# Position the approach, then use production walking toward the real trunk.
	_player.global_position=Vector3(base)+Vector3(0.5,0.05,-3.5);_player.rotation.y=PI;_player.velocity=Vector3.ZERO
	var before: Vector3 = _player.global_position
	_player.set_runtime_ready(true);Input.action_press("move_forward");await _frames(24);Input.action_release("move_forward")
	await _frames(4);_player.set_runtime_ready(false)
	_check(_player.global_position.distance_to(before)>0.5 and _player.global_position.distance_to(Vector3(base))<before.distance_to(Vector3(base)),"Player walks toward a generated voxel tree using production movement")
	for cell: Vector3i in LfeStarterTreeRules.cells(tree):
		if cell.y>=base.y+2:_tree_kept.append({"position":[cell.x,cell.y,cell.z],"block":"leyforge:oak_heartwood" if LfeStarterTreeRules.cells(tree)[cell]==1 else "leyforge:oak_leaves"})
	await _hold_voxel_demo(base)
	await _chop_block(base,true)
	var neighbour: Vector3i = base+Vector3i.UP
	_check(_tool.get_voxel(neighbour)==11,"Mining the basal trunk leaves the adjacent trunk standing")
	# Individually remove the top leaf; every other canopy voxel stays intact.
	var leaf: Vector3i = base+Vector3i(0,int(tree["height"])+1,0)
	await _aim(leaf);_player.global_position=Vector3(base)+Vector3(2.5,0.05,0.5)
	var resources: Dictionary = _world.resources.snapshot()
	_held(true)
	_check(_player.try_break_target() and _world.advance_harvest(2),"Top Oak Leaves voxel is individually targetable and breakable")
	_held(false)
	_check(_tool.get_voxel(leaf)==0 and _world.resources.snapshot()==resources,"Breaking a leaf yields no timber or item output")
	_edits.append({"position":[leaf.x,leaf.y,leaf.z],"block":"leyforge:air"})
	for index: int in range(_tree_kept.size()-1,-1,-1):
		if _tree_kept[index]["position"]==[leaf.x,leaf.y,leaf.z]:_tree_kept.remove_at(index)
	_verify_tree_cells(false)
	# Place the gathered canonical Heartwood through normal RMB, mine it again,
	# then retain one placed voxel for actual streamed/restart verification.
	var support: Vector3i = base+Vector3i(3,-1,-3)
	support.y=LfeWave1TerrainRules.height_at(_world.active_seed,support.x,support.z)
	var placed: Vector3i = support+Vector3i.UP
	_player.global_position=Vector3(support)+Vector3(2.5,1.05,0.5)
	_select("oak_heartwood");await _aim(support);_player._update_targeting()
	_check(_player.get_placement_cell()==placed and _player.try_place_target() and _world.resources.inventory.total(&"leyforge:oak_heartwood")==0,"RMB places exactly one gathered canonical Heartwood block")
	_check(_tool.get_voxel(placed)==11 and _tool.get_voxel(placed+Vector3i.UP)==_world._generator.sample_voxel_id(placed+Vector3i.UP),"Placed Heartwood is one voxel and spawns no tree")
	await _aim(placed)
	var camera: Camera3D = _player.get_camera();camera.global_position=Vector3(placed)+Vector3(3,2,-3)
	camera.look_at(Vector3(placed)+Vector3.ONE*0.5,Vector3.UP);await _frames(12)
	await _capture("20_placed_heartwood.png")
	await _chop_block(placed)
	# Recovered wood was already in the material ledger before its temporary place.
	_adjust("leyforge:oak_heartwood",-1)
	_check(_world.resources.inventory.total(&"leyforge:oak_heartwood")==1,"Re-mined placed Heartwood returns exactly once")
	_select("oak_heartwood");await _aim(support)
	_check(_player.try_place_target(),"Place recovered Heartwood for sparse save/restart proof")
	_built.append({"position":[placed.x,placed.y,placed.z],"block":"leyforge:oak_heartwood"})
	# Its air edit now has a later place, verified in _built instead.
	for index: int in range(_edits.size()-1,-1,-1):
		if _edits[index]["position"]==[placed.x,placed.y,placed.z]:_edits.remove_at(index)

func _chop_logs(count: int) -> void:
	var left: int = count
	for tree: Dictionary in _local_trees():
		var base: Vector3i = tree["base"]
		# The lowest two logs are exposed below every canopy variant.
		for layer: int in 2:
			var cell: Vector3i = base+Vector3i(0,layer,0)
			if _world._voxel_id_at(cell)!=11:continue
			await _chop_block(cell,false,left>1);left-=1
			if left==0:return
	_check(false,"Enough real tree voxels exist for the fresh crafting progression")

func _chop_block(cell: Vector3i, demonstrate: bool = false, keep_held: bool = false) -> void:
	await _aim(cell)
	_player.global_position=Vector3(cell)+Vector3(2.5,0.05,0.5)
	var camera: Camera3D = _player.get_camera();camera.global_position=Vector3(cell)+Vector3(1.7,0.5,0.5)
	camera.look_at(Vector3(cell)+Vector3.ONE*0.5,Vector3.UP);await _frames(2)
	_player._update_targeting()
	var neighbour: int = _tool.get_voxel(cell+Vector3i.UP)
	var overrides: int = _world.world_save.overrides.count()
	var equipment: Dictionary = _world.resources.equipment.stack_at(0)
	_held(true)
	_check(_player.target_source().is_empty() and _player.try_break_target(),"LMB targets a real Heartwood voxel through the normal terrain path")
	var seconds: float = float(_world._harvest.get("seconds",0));var wear: bool = _world._harvest.get("wear",false)
	_tree_times.append(seconds)
	_check(not _world.advance_harvest(seconds/2) and _tool.get_voxel(cell)==11,"Partial chopping leaves the single trunk voxel intact")
	_check(_world.advance_harvest(2) and _tool.get_voxel(cell)==0,"Completed chopping removes only the targeted trunk voxel")
	if not keep_held:_held(false)
	else:_check(Input.is_action_pressed("break_block"),"Continuous chopping retains held input across successive voxel attempts")
	_check(_tool.get_voxel(cell+Vector3i.UP)==neighbour,"Chopping preserves the neighbouring trunk/canopy voxel")
	if wear:_check(_world.resources.equipment.stack_at(0)["durability"]==equipment["durability"]-1,"Each correct axe block action costs exactly one durability")
	var drops: Array = _world.resources.drops()
	_check(drops.size()==1 and drops[0]["stack"]=={"content":"leyforge:oak_heartwood","quantity":1},"Each trunk voxel creates exactly one canonical Heartwood drop")
	if drops.is_empty():return
	var id: String = drops[0]["instance"];var p: Array = drops[0]["position"]
	var position: Vector3 = Vector3(float(p[0]),float(p[1]),float(p[2]))
	_check(position==_world.drop_rest_position(position),"New trunk drop settles at the actual local support surface")
	if demonstrate:
		var tree: Dictionary = _local_trees()[0]
		await _voxel_tree_view(tree);await _capture("19_partial_tree_grounded_drop.png")
		var saved: Dictionary = _world.resources.snapshot();var visual: MeshInstance3D = _world.resource_presenter._nodes[id].get_node("Visual");var transform: Transform3D = visual.transform
		await _frames(25)
		_check(visual.transform!=transform and _world.resources.snapshot()==saved and absf(visual.position.y)<=0.02,"Grounded drop gently bobs/rotates without changing its logical resting position")
		# Actual proximity pickup honours the existing real-time cooldown.
		_player.global_position=position+Vector3(0,0.1,0);_player.velocity=Vector3.ZERO;_player.set_runtime_ready(true)
		await _frames(85);_player.set_runtime_ready(false)
		_check(_world.resources.drop(id).is_empty() and _world.resources.inventory.total(&"leyforge:oak_heartwood")==1,"Player proximity picks up the exact Heartwood after cooldown")
	else:_check(_world.resources.pickup(id)==1,"Production pickup returns the single mined Heartwood")
	_adjust("leyforge:oak_heartwood",1)
	_edits.append({"position":[cell.x,cell.y,cell.z],"block":"leyforge:air"})

func _verify_tree_cells(physical: bool) -> void:
	for entry: Dictionary in _tree_kept:
		var p: Array = entry["position"];var cell: Vector3i = Vector3i(int(p[0]),int(p[1]),int(p[2]))
		_check((_tool.get_voxel(cell) if physical else _world._voxel_id_at(cell))==_catalog.get_voxel_id(StringName(entry["block"])),"Remaining generated trunk/leaf voxel stays exact")
	for entry: Dictionary in _edits:
		var p: Array = entry["position"];var cell: Vector3i = Vector3i(int(p[0]),int(p[1]),int(p[2]))
		_check((_tool.get_voxel(cell) if physical else _world._voxel_id_at(cell))==0,"Individual mined voxel remains air")

# Find a close, unobstructed evidence view without altering terrain or drop state.
func _drop_view(position: Vector3) -> void:
	var camera: Camera3D = _player.get_camera();camera.top_level=true
	for height: float in [1.2,2.5,4.0]:
		for direction: Vector2 in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1),Vector2(1,1),Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1)]:
			var offset: Vector2 = direction.normalized()*1.5
			var eye: Vector3 = position+Vector3(offset.x,height,offset.y)
			var clear: bool = true
			for step: int in 17:
				var cell: Vector3i = Vector3i(eye.lerp(position,float(step)/16).floor())
				if not _tool.is_area_editable(LfeVoxelInteractionRules.cell_aabb(cell)) or _catalog.is_solid_voxel(_tool.get_voxel(cell)):clear=false;break
			if not clear:continue
			camera.global_position=eye;camera.look_at(position,Vector3.UP);await _frames(12)
			return
	_check(false,"An unobstructed evidence view exists for the grounded drop")

func _dense_stone_demonstration(index: int) -> void:
	var entry: Dictionary = _world.creation.sources()[index-12 if _world.world_save.worldgen_version==2 else index]
	var before: Dictionary = _world.creation.snapshot()
	var resources: Dictionary = _world.resources.snapshot()
	await _resource_view(index)
	var body: Node3D = _world.creation_presenter._nodes[entry["instance"]]
	var centre: Vector3 = body.global_position+Vector3(0,0.5,0)
	await _drop_view(centre);_player._update_targeting()
	var meshes: Array[Node] = body.get_children().filter(func(node:Node)->bool:return node is MeshInstance3D)
	var collisions: Array[Node] = body.get_children().filter(func(node:Node)->bool:return node is CollisionShape3D)
	_check(entry["source"]=="dense_stone" and _player.target_source()==entry["instance"],"Rendered crosshair targets the actual finite Dense Stone source")
	_check(meshes.size()==1 and (meshes[0] as MeshInstance3D).mesh is BoxMesh and (meshes[0] as MeshInstance3D).mesh.size==Vector3.ONE,"Rendered Dense Stone contains exactly one unit BoxMesh")
	_check(collisions.size()==1 and (collisions[0] as CollisionShape3D).shape is BoxShape3D and (collisions[0] as CollisionShape3D).shape.size==Vector3.ONE,"Rendered Dense Stone has one unit collision box")
	_check(_player._target_highlight.visible and _player._target_highlight.global_position==centre and _player._target_highlight.scale==Vector3.ONE,"Actual highlighted bounds match the visible unit cube")
	_check(_world.creation.snapshot()==before and _world.resources.snapshot()==resources,"Presentation inspection preserves source depletion, identities and conservation")
	_report["dense_stone_presentation"]={"source":entry["source"],"instance":entry["instance"],"mesh_count":meshes.size(),"collision_count":collisions.size(),"size":[1,1,1],"remaining":entry["remaining"]}
	await _capture("23_dense_stone_unit_cube.png")

func _held(active: bool) -> void:
	if active:Input.action_press("break_block")
	else:Input.action_release("break_block")
	_player.sync_primary_action_input()

func _hold_voxel_demo(cell: Vector3i) -> void:
	await _aim(cell)
	var camera: Camera3D = _player.get_camera();camera.global_position=Vector3(cell)+Vector3(1.7,0.5,0.5)
	camera.look_at(Vector3(cell)+Vector3.ONE*0.5,Vector3.UP)
	_player.global_position=Vector3(cell)+Vector3(2.5,0.05,0.5)
	await _hold_cancel_demo("voxel","24_hold_voxel_cancelled.png")

func _hold_source_demo(index: int) -> void:
	var entry: Dictionary = _world.creation.sources()[index-12]
	var p: Array = entry["position"];var point: Vector3 = Vector3(float(p[0]),floorf(float(p[1]))+0.5,float(p[2]))
	_player.global_position=point+Vector3(2.5,-0.45,0)
	await _aim_point(point);await _drop_view(point)
	await _hold_cancel_demo("source","25_hold_source_cancelled.png")

func _hold_cancel_demo(family: String, frame: String) -> void:
	var resources: Dictionary = _world.resources.snapshot();var creation: Dictionary = _world.creation.snapshot();var edits: int = _world.world_save.overrides.count()
	Input.action_press("break_block");_player._handle_interaction_actions()
	_check(_world.has_active_harvest(),"Real continuous-input adapter starts held "+family+" work")
	_check(not _world.advance_harvest(float(_world._harvest.get("seconds",1))*0.25),"Short held "+family+" press does not complete")
	# The release callback precedes GUI capture; it must clear authority immediately.
	Input.action_release("break_block")
	var released: InputEventMouseButton = InputEventMouseButton.new();released.button_index=MOUSE_BUTTON_LEFT;released.pressed=false
	_player._input(released)
	_check(not _world.has_active_harvest() and not _world.advance_harvest(60),"LMB release immediately cancels "+family+" work")
	_check(_world.resources.snapshot()==resources and _world.creation.snapshot()==creation and _world.world_save.overrides.count()==edits,"Released "+family+" attempt retains exact block/source/output/durability state")
	# Opening the actual inventory shell while held cancels the action too.
	Input.action_press("break_block");_player._handle_interaction_actions()
	_check(_world.has_active_harvest(),"A new held "+family+" attempt begins from zero")
	_world.advance_harvest(float(_world._harvest.get("seconds",1))*0.25)
	_key(KEY_I)
	_check(_player.inventory_open and not _world.has_active_harvest() and not _world.advance_harvest(60),"Inventory immediately cancels held "+family+" work")
	_key(KEY_I);_held(false)
	_check(_world.resources.snapshot()==resources and _world.creation.snapshot()==creation,"Menu cancellation creates no background "+family+" output or wear")
	_player.show_status("Hold LMB — release cancels gathering")
	await _capture(frame)
