extends "res://tests/wave_4/wave_4_playtest_driver.gd"

func _run() -> void:
	if not _world.is_runtime_ready():await _world.runtime_ready
	_check(_world.local_player_id==_world.active_character.player_id and _player.character_record==_world.active_character,"Local controller explicitly presents profile's character record")
	_check(_world.authority.character(_world.local_player_id)==_world.active_character,"Active character belongs to authoritative roster")
	_check(not _world.personal_resources.snapshot().has("drops") and not _world.creation.snapshot().has("survival"),"Rendered gameplay uses separated v4 owners")
	if _phase in ["P","Q"]:
		await _physical_repair_run()
		return
	if _phase not in ["M3","N3"]:
		await super._run()
		return
	_player.set_runtime_ready(false)
	_check(DisplayServer.get_name()!="headless","Real rendered migration process")
	if _phase=="M3":await _migration_v3()
	else:await _migration_restart()
	_report.merge({"phase":_phase,"checks":_checks,"passed":_failures.is_empty(),"failures":_failures,"world_id":_world.world_save.world_id,"seed":_world.active_seed,"survival_profile":_world.active_character.survival.profile_name,"survival_acceleration":false,"worldgen_version":_world.world_save.worldgen_version})
	_write_report()
	for failure: String in _failures:push_error("W5.1 rendered: "+failure)
	print("WAVE_4_RENDERED_%s_%s checks=%d" % [_phase,"PASS" if _failures.is_empty() else "FAIL",_checks])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _migration_v3() -> void:
	var primary: String=_world.world_save.get_primary_path()
	var original: String=FileAccess.get_file_as_string(primary)
	var envelope: Dictionary=JSON.parse_string(original)
	var legacy: Dictionary=JSON.parse_string(envelope["payload_json"])
	_check(envelope["save_version"]==3 and _world.world_save.load_status.contains("migrated v3"),"Copied v3 world opens without rewriting")
	_check(_same(LfeTestResourceView.view(_world.personal_resources,_world.world_resources).snapshot(),legacy["resources"]),"Rendered v3 split preserves inventory, durability, drops and crate")
	_check(_same(LfeTestCreationView.view(_world.creation,_world.active_character.survival).snapshot(),legacy["creation"]),"Rendered v3 split preserves survival and running kiln")
	var objects: Array=_world.creation.objects()
	_check(objects.size()==1 and objects[0].has("station") and objects[0]["station"]["progress"]==3,"Historical kiln reservation retained")
	var old_health: float=_world.active_character.survival.snapshot()["health"]
	_check(_world.damage_player(1) and _world.active_character.survival.snapshot()["health"]==old_health-1,"Migrated character responds to normal authority damage")
	_world.advance_creation(1)
	_check(_world.creation.objects()[0]["station"]["progress"]==4,"Migrated world process resumes through normal simulation")
	_check(_world.request_save() and _world.world_save.players_state[0]["player_id"]==_world.local_player_id,"Explicit rendered migration writes profile-owned v4 character")
	_check(FileAccess.get_file_as_string(primary+".previous")==original,"Accepted legacy bytes retained in previous copy")
	_snapshot_report()
	await _capture("26_migration_v3.png")

func _snapshot_report() -> void:
	super._snapshot_report()
	_report["players"]=_world.world_save.players_state.duplicate(true)
	_report["world_resources"]=_world.world_save.world_resource_state.duplicate(true)
	_report["owner_player_id"]=_world.world_save.owner_player_id

func _verify_restored(report: Dictionary) -> void:
	super._verify_restored(report)
	_check(_same(_world.world_save.players_state,report["players"]),"Fresh rendered process restores complete v4 character roster")
	_check(_same(_world.world_save.world_resource_state,report["world_resources"]) and _world.world_save.owner_player_id==report["owner_player_id"],"Fresh rendered process restores shared ownership and resources")

func _same(actual: Variant,expected: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(actual,"",true,true))==JSON.parse_string(JSON.stringify(expected,"",true,true))

func _verify_accounting() -> void:
	super._verify_accounting()
	for content: String in _ledger:
		_check(_world.authority.total(StringName(content))==int(_ledger[content]),"Whole-roster authority accounting "+content)
# Physics repair phases use their own isolated world, keeping all earlier phases intact.
func _physical_repair_run() -> void:
	_player.set_runtime_ready(false)
	_check(DisplayServer.get_name()!="headless","Repair exercises a real rendered physics world")
	if _phase=="P":
		await _source_physical_collisions()
		await super._new_loop()
		await _deplete_physical_sources()
		await _ui_context_controls()
		await _airborne_inventory()
		_verify_accounting()
		_check(_world.request_save(),"Physics repair state saved through normal v4 authority")
		# The inherited loop already took a snapshot. Its merge preserves existing
		# keys, so refresh those fields before the second save/restart comparison.
		for key: String in ["resources","creation","player","ledger","built","edits","kiln","rest","home","tree_kept","tree_mined"]:
			_report.erase(key)
		_snapshot_report()
		await _capture("29_physics_saved.png")
	else:
		var previous: Dictionary=_read("P")
		_verify_restored(previous)
		_restore_report(previous)
		await _no_source_ghosts(previous["depleted_physical_sources"])
		await _capture("30_physics_restart.png")
	_report.merge({"phase":_phase,"checks":_checks,"passed":_failures.is_empty(),"failures":_failures,"world_id":_world.world_save.world_id,"seed":_world.active_seed,"survival_profile":_world.active_character.survival.profile_name,"survival_acceleration":false,"worldgen_version":_world.world_save.worldgen_version,"setup_only":["Temporarily lift original source bodies to isolate capsule collision from uneven terrain, then restore them","Position airborne character with controlled initial vertical speed","Fixed-duration production simulation calls while UI remains visible"],"state_injection":false})
	_write_report()
	for failure: String in _failures:push_error("W5.1 physics: "+failure)
	print("WAVE_4_RENDERED_%s_%s checks=%d" % [_phase,"PASS" if _failures.is_empty() else "FAIL",_checks])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _source_physical_collisions() -> void:
	var saved: Vector3=_player.global_position
	var proofs: Array=[]
	_check(_player.collision_mask==9 and _terrain.collision_layer==1,"Player physical mask 1 -> 9; voxel layer remains 1")
	for kind: String in ["dense_stone","trail_food","trail_water"]:
		var entry: Dictionary=_world.creation.sources().filter(func(v:Dictionary)->bool:return v["source"]==kind)[-1]
		var p: Array=entry["position"]
		await _aim_point(Vector3(float(p[0]),float(p[1]),float(p[2])))
		var body: StaticBody3D=_world.creation_presenter._nodes[entry["instance"]]
		var original: Vector3=body.position
		_check(body.collision_layer==8 and body.collision_mask==0,kind+" retains separate source/target layer")
		# Exercise the actual presented source and player capsule without a neighbouring
		# terrain slope being mistaken for a source collision. Restore before gathering.
		body.position+=Vector3.UP*50
		await _frames(2)
		_player.global_position=body.global_position+Vector3(-2,0.05,0)
		var hit: KinematicCollision3D=_player.move_and_collide(Vector3(4,0,0))
		_check(hit!=null and hit.get_collider()==body,kind+" physically stops the real player capsule")
		_check(_player.global_position.x<body.global_position.x,kind+" prevents walking through")
		_player.global_position=body.global_position+Vector3(-2,0.05,0)
		var clear: bool=true
		for motion: Vector3 in [Vector3(0,0,1.5),Vector3(4,0,0),Vector3(0,0,-1.5)]:
			if _player.move_and_collide(motion)!=null:clear=false
		_check(clear and _player.global_position.x>body.global_position.x+1.5,kind+" permits walking around the physical bounds")
		body.position=original
		await _frames(2)
		proofs.append({"source":kind,"instance":entry["instance"],"layer":body.collision_layer,"blocked":hit!=null,"walk_around":clear})
	_player.global_position=saved
	_report["source_collision"]=proofs

func _deplete_physical_sources() -> void:
	_equip("stone_pickaxe")
	var depleted: Array=[]
	for index: int in [15,17,19]:
		var entry: Dictionary=_world.creation.sources()[index-12]
		_check(int(entry["remaining"])>0,"Additional collision fixture is live before harvest: "+entry["source"])
		await _gather(index)
		_world.creation_presenter.sync()
		await _frames(3)
		depleted.append(entry["instance"])
	_check(depleted.size()==3,"Dense Stone, provisions and water all gathered through held-LMB path")
	await _no_source_ghosts(depleted)
	_report["depleted_physical_sources"]=depleted

func _no_source_ghosts(ids: Array) -> void:
	for id: String in ids:
		var entry: Dictionary=_world.creation.source(id)
		var p: Array=entry["position"]
		var point: Vector3=Vector3(float(p[0]),floorf(float(p[1]))+0.3,float(p[2]))
		await _aim_point(point)
		_check(int(entry["remaining"])==0 and not _world.creation_presenter._nodes.has(id),"Depletion/restart removes "+entry["source"]+" presentation and body")
		var query: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(point+Vector3.LEFT*1.5,point+Vector3.RIGHT*1.5,LfeVoxelInteractionRules.SOURCE_TARGET_MASK)
		_check(_player.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"Depletion/restart leaves no ghost source collision: "+entry["source"])

func _capture(name: String) -> void:
	if _phase=="P" and name=="03_workstation.png":
		var station: LfeWorkstation=_world.creation.station(_kiln)
		var before: float=float(station.snapshot()["progress"])
		var elapsed: float=float(_world.creation.snapshot()["elapsed"])
		var hunger: float=float(_world.active_character.survival.snapshot()["hunger"])
		_check(_player.inventory_open and _world.inventory_panel._panel.visible,"Kiln UI visible before measured interval")
		var continuously_visible: bool=true
		for tick: int in 4:
			_world.advance_creation(0.25)
			await _frames(1)
			continuously_visible=continuously_visible and _player.inventory_open and _world.inventory_panel._panel.visible
		var after: float=float(station.snapshot()["progress"])
		_check(continuously_visible and is_equal_approx(after,before+1),"Kiln advances one measured second with UI continuously visible")
		_check(is_equal_approx(float(_world.creation.snapshot()["elapsed"]),elapsed+1),"World elapsed time advances with UI open")
		_check(float(_world.active_character.survival.snapshot()["hunger"])<hunger,"Standard active-player survival continues with UI visible")
		_check(not get_tree().paused and Engine.time_scale==1,"UI never globally pauses SceneTree or engine time")
		_report["ui_simulation"]={"kiln_before":before,"kiln_after":after,"elapsed_before":elapsed,"elapsed_after":_world.creation.snapshot()["elapsed"],"hunger_before":hunger,"hunger_after":_world.active_character.survival.snapshot()["hunger"],"ui_visible_entire_interval":continuously_visible,"tree_paused":get_tree().paused,"time_scale":Engine.time_scale}
	await super._capture(name)

func _ui_context_controls() -> void:
	var storage: String=""
	for entry: Dictionary in _world.creation.objects():
		if entry["content"]=="leyforge:storage_box":storage=entry["instance"]
	for context: String in ["inventory","crafting",_bench,_kiln,storage]:
		_world.close_inventory()
		if context in ["inventory","crafting"]:
			_world.inventory_panel.open_context("",context=="crafting")
		else:
			var entry: Dictionary=_world.creation.objects().filter(func(v:Dictionary)->bool:return v["instance"]==context)[0]
			var c: Array=entry["cell"]
			_player.global_position=Vector3(float(c[0])+1.5,float(c[1])+1,float(c[2])+0.5)
			_world.inventory_panel.open_context(context)
		_check(_player.inventory_open and _world.inventory_panel._panel.visible,"Real UI context owns local input: "+context)
		var resources: Dictionary=_world.personal_resources.snapshot()
		var creation: Dictionary=_world.creation.snapshot()
		var yaw: float=_player.rotation.y
		var pitch: float=_player._head.rotation.x
		var motion: InputEventMouseMotion=InputEventMouseMotion.new();motion.relative=Vector2(50,50)
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		_player._unhandled_input(motion)
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		_key(KEY_E)
		Input.action_press("break_block");Input.action_press("place_block")
		_player._handle_interaction_actions()
		_check(not _player.try_break_target() and not _player.try_place_target() and not _world.has_active_harvest(),"UI blocks gather/mine/place/E interaction: "+context)
		_check(_player.rotation.y==yaw and _player._head.rotation.x==pitch,"UI blocks mouse look: "+context)
		_check(_world.personal_resources.snapshot()==resources and _world.creation.snapshot()==creation,"Blocked UI actions preserve authoritative resources/world: "+context)
		Input.action_release("break_block");Input.action_release("place_block")
	_world.close_inventory()

func _airborne_inventory() -> void:
	# Use real streamed voxel support at the normal safe spawn.
	var support: Vector3=_world._find_safe_spawn()
	_check(not is_inf(support.x) and _world._position_is_safe(support),"Airborne fixture uses current safe voxel support above constructed terrain")
	await _aim_point(support)
	_player.global_position=support+Vector3.UP*3
	_player.velocity=Vector3(2,-1,0)
	_player.set_runtime_ready(true)
	_world.inventory_panel.open()
	Input.action_press("move_forward");Input.action_press("sprint");Input.action_press("jump")
	Input.action_press("break_block");Input.action_press("place_block")
	var start: Vector3=_player.global_position
	var health: float=float(_world.active_character.survival.snapshot()["health"])
	var visible: bool=true
	await _frames(8)
	_check(_player.global_position.y<start.y and _player.velocity.y< -1,"Airborne Inventory continues gravity and vertical movement")
	_check(absf(_player.velocity.z)<0.001 and absf(_player.velocity.x)<0.001,"UI suppresses WASD/sprint acceleration and normally decelerates momentum")
	for frame: int in 240:
		await _frames(1)
		visible=visible and _player.inventory_open and _world.inventory_panel._panel.visible
		if _player.is_on_floor():break
	_check(_player.is_on_floor() and absf(_player.global_position.y-support.y)<0.2,"UI-open character lands on real voxel support")
	_check(visible and _player.inventory_open,"Inventory remains visible and usable throughout fall and landing")
	await _frames(4)
	_check(_player.is_on_floor() and _player.velocity.y<=0,"Held jump cannot initiate through open UI")
	_check(not _world.has_active_harvest() and not get_tree().paused and Engine.time_scale==1,"Held actions stay blocked; world is unpaused during fall")
	_check(float(_world.active_character.survival.snapshot()["health"])==health,"Ordinary short UI-open fall retains existing safe threshold")
	var landed: float=_player.global_position.y
	await _capture("27_airborne_inventory_landed.png")
	# Controlled fall exceeds the existing 12 m/s threshold; sample each pre-slide
	# speed to verify the unchanged (speed-12)*3 formula at the landing step.
	_player.global_position=support+Vector3.UP*3
	_player.velocity=Vector3(0,-14,0)
	await _frames(1)
	var fall_speed: float=0
	for frame: int in 240:
		fall_speed=-_player.velocity.y+_player._gravity/Engine.physics_ticks_per_second
		await _frames(1)
		visible=visible and _world.inventory_panel._panel.visible and _player.inventory_open
		if _player.is_on_floor():break
	var damage: float=health-float(_world.active_character.survival.snapshot()["health"])
	_check(_player.is_on_floor() and visible and damage>0,"Fast fall applies authoritative fall damage with Inventory open")
	_check(absf(damage-minf(100,(fall_speed-12)*3))<0.01,"UI-open fall preserves existing threshold and damage formula")
	_report["airborne_ui"]={"y_start":start.y,"y_landed":landed,"ui_visible_entire_interval":visible,"fall_speed":fall_speed,"fall_damage":damage,"supported":_player.is_on_floor(),"tree_paused":get_tree().paused,"time_scale":Engine.time_scale}
	await _capture("28_inventory_fall_damage.png")
	for action: String in ["move_forward","sprint","jump","break_block","place_block"]:Input.action_release(action)
	_player.set_runtime_ready(false)
	_world.close_inventory()

func _hold_cancel_demo(family: String, frame: String) -> void:
	await super._hold_cancel_demo(family,frame)
	Input.action_press("break_block");_player._handle_interaction_actions()
	_check(_world.has_active_harvest(),"Fresh held "+family+" attempt starts before UI")
	_world.advance_harvest(float(_world._harvest.get("seconds",1))*0.25)
	_world.inventory_panel.open()
	_check(not _world.has_active_harvest(),"Opening UI immediately clears partial "+family+" work")
	_world.close_inventory()
	_player._handle_interaction_actions()
	_check(_world.has_active_harvest() and float(_world._harvest.get("work",-1))==0,"Closing UI while LMB held begins "+family+" from zero")
	_held(false)
