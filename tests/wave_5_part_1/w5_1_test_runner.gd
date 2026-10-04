extends SceneTree

const A: String="11111111111111111111111111111111"
const B: String="22222222222222222222222222222222"
const C: String="33333333333333333333333333333333"
const SEED: int=184552221
var _checks: int=0
var _failures: Array[String]=[]
var _root: String
var _out: String
var _catalog: LfeBlockCatalog
var _profile_id: String

func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--w51-root="):_root=argument.trim_prefix("--w51-root=")
		if argument.begins_with("--w51-out="):_out=argument.trim_prefix("--w51-out=")
	if not _root.is_absolute_path() or not _out.is_absolute_path():quit(1);return
	_catalog=LfeBlockCatalog.new()
	_check(_catalog.load_default()==OK,"Canonical content loads")
	var profile: LfeLocalProfile=LfeLocalProfile.new()
	_check(profile.open_profile()==OK,"Installation profile opens")
	_profile_id=profile.player_id
	if OS.get_cmdline_user_args().has("--w51-restart"):
		_restart()
	else:
		_profiles()
		_roster_commands()
		_actor_crafting_and_conservation()
		_roster_bound()
		_migration()
	var name: String="restart" if OS.get_cmdline_user_args().has("--w51-restart") else "focused"
	_write(_out.path_join("w51_"+name+".json"),JSON.stringify({"checks":_checks,"passed":_failures.is_empty(),"failures":_failures,"profile_id":_profile_id},"\t"))
	for failure: String in _failures:push_error("W5.1: "+failure)
	print("W5_1_"+name.to_upper()+"_"+("PASS" if _failures.is_empty() else "FAIL")+" checks=%d" % _checks)
	quit(0 if _failures.is_empty() else 1)

func _profiles() -> void:
	_check(LfeWorldResourceState._valid_identity(_profile_id),"Profile is cryptographic 128-bit lowercase hex")
	var bytes: String=FileAccess.get_file_as_string(LfeLocalProfile.PROFILE_PATH)
	var again: LfeLocalProfile=LfeLocalProfile.new()
	_check(again.open_profile()==OK and again.player_id==_profile_id and FileAccess.get_file_as_string(LfeLocalProfile.PROFILE_PATH)==bytes,"Repeated profile open reuses exact identity/bytes")
	for malformed: Variant in [{},{"profile_version":2,"player_id":A},{"profile_version":1.5,"player_id":A},{"profile_version":1,"player_id":"player1"},{"profile_version":1,"player_id":A,"email":"unwanted"},"broken"]:
		var p: String=_root.path_join("bad_profile.json")
		var raw: String=JSON.stringify(malformed)
		_write(p,raw)
		var invalid: LfeLocalProfile=LfeLocalProfile.new()
		_check(invalid.open_profile(p)!=OK and invalid.player_id.is_empty() and not invalid.error.is_empty(),"Malformed profile fails visibly")
		_check(FileAccess.get_file_as_string(p)==raw,"Malformed identity is never regenerated")
	var oversized: String="x".repeat(LfeLocalProfile.MAX_BYTES+1)
	var p: String=_root.path_join("oversized_profile.json");_write(p,oversized)
	_check(LfeLocalProfile.new().open_profile(p)!=OK and FileAccess.get_file_as_string(p)==oversized,"Profile content bound rejects without replacement")
	p=_root.path_join("pending_profile.json");_write(p+".pending",JSON.stringify({"profile_version":1,"player_id":C}))
	var recovered: LfeLocalProfile=LfeLocalProfile.new()
	_check(recovered.open_profile(p)==OK and recovered.player_id==C,"Interrupted first creation retains original identity")
	p=_root.path_join("bad_pending_profile.json");_write(p+".pending","bad")
	_check(LfeLocalProfile.new().open_profile(p)!=OK and not FileAccess.file_exists(p),"Malformed interrupted profile does not create another identity")

func _new(id: String,actor: String=A) -> LfeWorldSave:
	var save: LfeWorldSave=LfeWorldSave.new()
	_check(save.open_world(id,SEED,true,_catalog,_root,actor)==OK,"World opens: "+id)
	return save

func _authority(save: LfeWorldSave) -> LfeGameplayAuthority:
	var authority: LfeGameplayAuthority=LfeGameplayAuthority.new()
	_check(authority.configure(save,_catalog),"Authoritative owners restore")
	return authority

func _roster_commands() -> void:
	var save: LfeWorldSave=_new("two_players")
	var world: LfeGameplayAuthority=_authority(save)
	var a: LfePlayerCharacter=world.add_character(A,Vector3(0.5,20.05,0.5))
	var b: LfePlayerCharacter=world.add_character(B,Vector3(1.5,20.05,0.5))
	_check(a!=null and b!=null and a!=b and a.resources!=b.resources and a.survival!=b.survival,"Characters have independent mutable owners")
	_check(a.resources.inventory.snapshot().all(func(v:Variant)->bool:return v==null) and a.resources.equipment.snapshot()==[null,null] and a.resources.selected_slot()==0 and a.survival.snapshot()["health"]==100,"New character has safe personal defaults")
	LfeItemTransactions.add(a.resources.inventory,&"leyforge:oak_heartwood",12)
	LfeItemTransactions.add(a.resources.inventory,&"leyforge:wooden_axe",1)
	var axe: int=_slot(a.resources.inventory,&"leyforge:wooden_axe")
	LfeHarvestRules.wear(a.resources,a.resources.inventory.stack_at(axe)["instance"])
	LfeItemTransactions.transfer(a.resources.inventory,axe,a.resources.equipment,1,0)
	LfeItemTransactions.add(b.resources.inventory,&"leyforge:stone",9)
	LfeItemTransactions.add(b.resources.inventory,&"leyforge:stone_pickaxe",1)
	LfeItemTransactions.transfer(b.resources.inventory,_slot(b.resources.inventory,&"leyforge:stone_pickaxe"),b.resources.equipment,1,0)
	var biology: Dictionary=a.survival.snapshot();biology["hunger"]=75;biology["fatigue"]=12;biology["stamina"]=60;biology["health"]=82
	a.survival.restore(biology)
	biology=b.survival.snapshot();biology["hunger"]=40;biology["fatigue"]=30;biology["stamina"]=35;biology["health"]=65
	b.survival.restore(biology)
	a.transform["yaw"]=0.2;b.transform["yaw"]=-0.4
	var untouched: Dictionary=b.snapshot()
	_check(world.execute(A,"select",{"slot":5}).success and b.snapshot()==untouched,"Actor hotbar selection leaves B untouched")
	var crate: String=world.world_resources.ensure_crate(Vector3(1,20,1))
	var deposit: LfeCommandResult=world.execute(A,"transfer",{"source":"inventory","destination":"storage/"+crate,"source_slot":0,"quantity":4})
	_check(deposit.success and deposit.data["quantity"]==4 and a.resources.inventory.total(&"leyforge:oak_heartwood")==8 and world.world_resources.storage_inventory(crate).total(&"leyforge:oak_heartwood")==4 and b.snapshot()==untouched,"A deposits exact quantity without changing B")
	var withdrawal: LfeCommandResult=world.execute(B,"transfer",{"source":"storage/"+crate,"destination":"inventory","source_slot":0,"quantity":4})
	_check(withdrawal.success and withdrawal.data["quantity"]==4 and b.resources.inventory.total(&"leyforge:oak_heartwood")==4 and world.total(&"leyforge:oak_heartwood")==12,"B withdraws shared resources; all-player total conserved")
	var before: Array=world.players_snapshot()
	_check(world.execute(A,"transfer",{"source":"inventory","destination":"storage/"+crate,"source_slot":0,"quantity":1,"expected":{"content":"leyforge:stone","quantity":8}}).reason_code=="stale_state" and world.players_snapshot()==before,"Stale expected stack rejects atomically")
	_check(world.execute(A,"transfer",{"source":"player/"+B+"/inventory","destination":"inventory","source_slot":0,"quantity":1}).reason_code=="invalid_target","Actor cannot address another player's inventory")
	var drop: LfeCommandResult=world.execute(A,"drop",{"slot":0,"quantity":2,"position":Vector3(1,20,1)})
	_check(drop.success and a.resources.inventory.total(&"leyforge:oak_heartwood")==6 and world.total(&"leyforge:oak_heartwood")==12,"Personal drop moves exact ownership into shared world")
	_check(world.execute(B,"pickup",{"target":drop.data["drop_id"]}).success and b.resources.inventory.total(&"leyforge:oak_heartwood")==6 and world.total(&"leyforge:oak_heartwood")==12,"Other actor picks up same shared drop exactly once")
	_check(not world.execute(B,"pickup",{"target":drop.data["drop_id"]}).success,"Repeated pickup cannot duplicate")
	var full_b: Dictionary=b.snapshot()
	for op: String in ["select","pickup","drop","transfer","swap","craft","close_grid","consume","damage","recover","advance_player","start_process"]:
		before=world.players_snapshot();var shared: Dictionary=world.world_resources.snapshot()
		_check(world.execute(C,op,{}).reason_code=="invalid_actor" and world.players_snapshot()==before and world.world_resources.snapshot()==shared,"Unknown actor rejects without fallback: "+op)
	var b_survival: Dictionary=b.survival.snapshot()
	_check(world.advance_world(3) and b.survival.snapshot()==b_survival and a.survival.snapshot()["hunger"]==75,"World tick advances no character biology")
	_check(world.execute(A,"advance_player",{"seconds":2,"sprinting":true}).success and a.survival.snapshot()["hunger"]<75 and b.survival.snapshot()==b_survival,"Only explicit active actor biology advances")
	_check(world.execute(A,"damage",{"amount":100}).success and not a.survival.alive() and b.snapshot()==full_b,"Damage affects only actor A")
	var retained: Dictionary=a.resources.snapshot()
	_check(world.execute(A,"recover",{"spawn":Vector3(0.5,20.05,0.5)}).success and a.resources.snapshot()==retained and b.snapshot()==full_b,"Safe recovery retains A inventory and all B state")
	# Shared finite sources, station, constructed storage and functional voxels.
	world.creation.initialize_sources(SEED,1);save.worldgen_version=1
	for spec: Dictionary in [{"content":"leyforge:workbench","cell":Vector3i(2,20,1)},{"content":"leyforge:kiln","cell":Vector3i(2,20,2)},{"content":"leyforge:storage_box","cell":Vector3i(2,20,3)}]:
		_check(world.creation.add_object(StringName(spec["content"]),spec["cell"],1),"Shared functional object exists")
		_check(save.record_voxel_edit(spec["cell"],_catalog.get_voxel_id(StringName(spec["content"])),0)==OK,"Functional object has one world voxel")
	var kiln: String=world.creation.object_at(Vector3i(2,20,2))
	var station: LfeWorkstation=world.creation.station(kiln)
	LfeItemTransactions.add(station.input,&"leyforge:oak_heartwood",2);LfeItemTransactions.add(station.fuel,&"leyforge:oak_heartwood",1)
	var total_before: int=world.total(&"leyforge:oak_heartwood")
	_check(world.execute(A,"start_process",{"target":kiln,"recipe":"leyforge:charcoal_burn"}).success and world.total(&"leyforge:oak_heartwood")==total_before-1,"Fuel consumption and active input reservation counted once")
	_check(world.advance_world(2) and station.snapshot()["progress"]==2 and b.survival.snapshot()==b_survival,"One shared station progresses independently of B")
	var shared_storage: String=world.creation.object_at(Vector3i(2,20,3))
	_check(world.execute(B,"transfer",{"source":"inventory","destination":"storage/"+shared_storage,"source_slot":0,"quantity":3}).success,"B transfers to constructed world storage")
	world.execute(A,"drop",{"slot":0,"quantity":1,"position":Vector3(1,20,1)})
	_check(not a.resources.snapshot().has("drops") and not a.resources.snapshot().has("storage") and not world.world_resources.snapshot().has("inventory") and not world.creation.snapshot().has("survival"),"Snapshots enforce player/world ownership boundaries")
	before=world.players_snapshot()
	_check(save.record_voxel_edit(Vector3i(-1,0,0),0,3)==OK and world.players_snapshot()==before,"Shared voxel edit is stored once outside both characters")
	var roster: Array=world.players_snapshot();roster.reverse()
	_check(save.save(roster,world.world_resources.snapshot(),world.creation.snapshot())==OK,"Two complete characters and shared world save as v4")
	var data: Dictionary=_payload(save.get_primary_path())
	_check(data.keys().size()==5 and data.has("players") and data.has("world_resources") and not data.has("player") and not data.has("resources"),"v4 durable high-level shape is clean")
	_check(data["players"][0]["player_id"]==A and data["players"][1]["player_id"]==B and data["metadata"]["owner_player_id"]==A,"Canonical roster order and durable owner")
	_check(not save.is_dirty(world.players_snapshot(),world.world_resources.snapshot(),world.creation.snapshot()),"Coherent snapshot begins clean")
	b.transform["yaw"]=0.7
	_check(save.is_dirty(world.players_snapshot(),world.world_resources.snapshot(),world.creation.snapshot()),"Inactive character transform changes are dirty")
	b.transform["yaw"]=-0.4
	# Duplicate instances in every endpoint are rejected both on save and restore.
	var valid_players: Array=world.players_snapshot()
	var valid_world: Dictionary=world.world_resources.snapshot()
	var valid_creation: Dictionary=world.creation.snapshot()
	var durable: Dictionary=valid_players[0]["resources"]["equipment"][0]
	for endpoint: String in ["other_inventory","other_equipment","drop","crate","constructed","station"]:
		var players: Array=valid_players.duplicate(true);var resources: Dictionary=valid_world.duplicate(true);var creation: Dictionary=valid_creation.duplicate(true)
		match endpoint:
			"other_inventory":players[1]["resources"]["inventory"][26]=durable.duplicate(true)
			"other_equipment":players[1]["resources"]["equipment"][0]=durable.duplicate(true)
			"drop":resources["drops"].append({"instance":C,"stack":durable.duplicate(true),"position":[1,20,1]})
			"crate":resources["storage"][0]["slots"][0]=durable.duplicate(true)
			"constructed":
				for object: Dictionary in creation["objects"]:
					if object.has("slots"):object["slots"][0]=durable.duplicate(true)
			"station":
				for object: Dictionary in creation["objects"]:
					if object.has("station"):object["station"]["output"][0]=durable.duplicate(true)
		var bytes: String=FileAccess.get_file_as_string(save.get_primary_path())
		_check(save.save(players,resources,creation)!=OK and FileAccess.get_file_as_string(save.get_primary_path())==bytes,"Cross-owner duplicate rejected on save: "+endpoint)
		var bad: Dictionary=data.duplicate(true);bad["players"]=players;bad["world_resources"]=resources;bad["creation"]=creation
		_corrupt_fixture(bad,"dup_"+endpoint)
	# Structural corruption controls retain valid checksums.
	for mutation: String in ["owner","duplicate_player","bad_id","nonfinite","hotbar","personal_world","global_survival","missing_player","roster_bound"]:
		var bad: Dictionary=data.duplicate(true)
		match mutation:
			"owner":bad["metadata"]["owner_player_id"]=C
			"duplicate_player":bad["players"].append(bad["players"][0].duplicate(true))
			"bad_id":bad["players"][0]["player_id"]="player1"
			"nonfinite":bad["players"][0]["transform"]["position"]=[1000001,0,0]
			"hotbar":bad["players"][0]["resources"]["hotbar_selected"]=9
			"personal_world":bad["players"][0]["resources"]["drops"]=[]
			"global_survival":bad["creation"]["survival"]=a.survival.snapshot()
			"missing_player":bad["players"]=[]
			"roster_bound":
				bad["players"]=[]
				for n: int in LfeWorldSave.MAX_PLAYERS+1:
					var player: Dictionary=data["players"][0].duplicate(true);player["player_id"]=str(n).sha256_text().substr(0,32);bad["players"].append(player)
		_corrupt_fixture(bad,"bad_"+mutation)
	var loaded: LfeWorldSave=_new("two_players",C)
	_check(loaded.owner_player_id==A and loaded.players_state==save.players_state,"A different local profile cannot steal ownership or progress")
	var other: LfeGameplayAuthority=_authority(loaded)
	var new_character: LfePlayerCharacter=other.add_character(C,Vector3(0.5,20.05,0.5))
	_check(new_character!=null and new_character.resources.total(&"leyforge:oak_heartwood")==0 and other.characters.size()==3 and other.character(A).snapshot()==a.snapshot(),"Missing v4 identity obtains separate safe default character")
	var isolation: LfeWorldSave=_new("same_seed")
	var isolated: LfeGameplayAuthority=_authority(isolation)
	var separate: LfePlayerCharacter=isolated.add_character(A,Vector3(0.5,20.05,0.5))
	_check(separate.resources.inventory.snapshot().all(func(v:Variant)->bool:return v==null) and separate.survival.snapshot()["health"]==100 and isolated.world_resources.drops().is_empty() and isolated.creation.objects().is_empty() and isolation.overrides.count()==0,"Same profile/seed in another world has independent progress")
	_check(separate.transform!=a.transform and separate.resources!=a.resources,"World-local record is not installation progress")
	# Fresh-process restart receives only a serialized expected report.
	_write(_out.path_join("expected_restart.json"),JSON.stringify({"profile_id":_profile_id,"players":save.players_state,"resources":save.world_resource_state,"creation":save.creation_state,"overrides":save.overrides.serialized_entries()},"",true,true))
	var primary: String=save.get_primary_path();var bytes: String=FileAccess.get_file_as_string(primary)
	_write(primary,bytes+" ")
	_check(save.save(valid_players,valid_world,valid_creation)!=OK and FileAccess.get_file_as_string(primary)==bytes+" ","External authoritative byte change prevents overwrite")
	_write(primary,bytes)
	_check(loaded.save(valid_players,valid_world,valid_creation)==OK,"Valid save rotates complete previous copy")
	_check(DirAccess.remove_absolute(primary)==OK,"Disposable interrupted promotion setup")
	var recovered: LfeWorldSave=_new("two_players")
	_check(recovered.load_status.contains("Recovered") and recovered.players_state==save.players_state and recovered.world_resource_state==valid_world,"Previous copy recovers both characters/shared state")
	_check(recovered.save()==OK,"Recovered v4 snapshot promotes safely")

func _corrupt_fixture(data: Dictionary,id: String) -> void:
	data["metadata"]["world_id"]=id
	var primary: String=_root.path_join(id+"/world.json");_envelope(primary,data,4)
	var bytes: String=FileAccess.get_file_as_string(primary)
	var rejected: LfeWorldSave=LfeWorldSave.new()
	_check(rejected.open_world(id,SEED,true,_catalog,_root,A)!=OK and rejected.save()!=OK and FileAccess.get_file_as_string(primary)==bytes,"Restore rejects corruption without replacing authority: "+id)


func _actor_crafting_and_conservation() -> void:
	var save: LfeWorldSave=_new("actor_crafting")
	var world: LfeGameplayAuthority=_authority(save)
	var point: Vector3=Vector3(1,20,1)
	var a: LfePlayerCharacter=world.add_character(A,point)
	var b: LfePlayerCharacter=world.add_character(B,point)
	LfeItemTransactions.add(a.resources.inventory,&"leyforge:oak_heartwood",10)
	LfeItemTransactions.add(b.resources.inventory,&"leyforge:oak_heartwood",10)
	var ga: LfeCraftingGrid=world.open_grid(A)
	var gb: LfeCraftingGrid=world.open_grid(B)
	_check(ga!=null and gb!=null and ga!=gb,"Crafting staging belongs independently to each actor")
	_check(world.execute(A,"transfer",{"source":"inventory","source_slot":0,"destination":"grid","destination_slot":0,"quantity":1}).success,"Actor A stages its own crafting input")
	_check(world.execute(B,"transfer",{"source":"inventory","source_slot":0,"destination":"grid","destination_slot":0,"quantity":2}).success,"Actor B stages its own crafting input")
	var before_b: Dictionary=b.snapshot()
	var staged_b: Array=gb.inventory.snapshot()
	_check(world.execute(A,"craft",{"recipe":"leyforge:saw_planks"}).success and a.resources.inventory.total(&"leyforge:oak_planks")==4,"Actor A consumes its staging and receives its outputs")
	_check(b.snapshot()==before_b and gb.inventory.snapshot()==staged_b,"Actor A crafting leaves B and B staging exact")
	_check(world.execute(A,"close_grid").success and world.execute(B,"close_grid").success and world.total(&"leyforge:oak_heartwood")==19,"Each actor closes its grid without losing staged material")
	var crate: String=world.world_resources.ensure_crate(point)
	var rng: RandomNumberGenerator=RandomNumberGenerator.new();rng.seed=516271
	for iteration: int in 300:
		var actor: String=A if rng.randi_range(0,1)==0 else B
		var record: LfePlayerCharacter=world.character(actor)
		match rng.randi_range(0,3):
			0:
				world.execute(actor,"transfer",{"source":"inventory","source_slot":_slot(record.resources.inventory,&"leyforge:oak_heartwood"),"destination":"storage/"+crate,"destination_slot":-1,"quantity":1})
			1:
				world.execute(actor,"transfer",{"source":"storage/"+crate,"source_slot":_slot(world.world_resources.storage_inventory(crate),&"leyforge:oak_heartwood"),"destination":"inventory","destination_slot":-1,"quantity":1})
			2:
				world.execute(actor,"drop",{"slot":_slot(record.resources.inventory,&"leyforge:oak_heartwood"),"quantity":1,"position":point})
			3:
				var drops: Array=world.world_resources.snapshot()["drops"]
				if not drops.is_empty():world.execute(actor,"pickup",{"target":drops[0]["instance"]})
		_check(4*world.total(&"leyforge:oak_heartwood")+world.total(&"leyforge:oak_planks")==80,"Seeded cross-player/crate/drop/crafting conservation step %d" % iteration)
	var baseline: Array=world.players_snapshot()
	for request: Dictionary in [{"operation":"pickup","args":{"target":[]}},{"operation":"transfer","args":{"source":[]}},{"operation":"craft","args":{"recipe":5}},{"operation":"advance_player","args":{"seconds":1,"sprinting":"true"}}]:
		_check(not world.execute(A,request["operation"],request["args"]).success and world.players_snapshot()==baseline,"Malformed typed command is rejected without personal mutation")

func _roster_bound() -> void:
	var save: LfeWorldSave=_new("roster_bound")
	var world: LfeGameplayAuthority=_authority(save)
	for n: int in LfeWorldSave.MAX_PLAYERS:
		var id: String=A if n==0 else str(n).sha256_text().substr(0,32)
		_check(world.add_character(id,Vector3(0.5,20,0.5))!=null,"Bounded character roster admits valid record %d" % n)
	_check(world.add_character(C,Vector3(0.5,20,0.5))==null and world.characters.size()==LfeWorldSave.MAX_PLAYERS,"Character admission refuses record beyond documented bound")
	_check(save.save(world.players_snapshot(),world.world_resources.snapshot(),world.creation.snapshot())==OK,"Maximum bounded valid roster saves")
	var loaded: LfeWorldSave=_new("roster_bound",B)
	_check(loaded.players_state.size()==LfeWorldSave.MAX_PLAYERS and loaded.owner_player_id==A,"Maximum bounded valid roster restores without ownership reassignment")

func _migration() -> void:
	var save: LfeWorldSave=_new("legacy_source",_profile_id)
	var world: LfeGameplayAuthority=_authority(save)
	save.worldgen_version=1;world.creation.initialize_sources(SEED,1)
	var position: Vector3=Vector3(0.5,LfeWave1TerrainRules.height_at(SEED,0,0)+1.05,0.5)
	var a: LfePlayerCharacter=world.add_character(_profile_id,position)
	LfeItemTransactions.add(a.resources.inventory,&"leyforge:stone",7);a.resources.select(5)
	LfeItemTransactions.add(a.resources.inventory,&"leyforge:wooden_axe",1)
	LfeHarvestRules.wear(a.resources,a.resources.inventory.stack_at(1)["instance"])
	var crate: String=world.world_resources.ensure_crate(position+Vector3(2,-0.6,0))
	LfeItemTransactions.transfer(a.resources.inventory,0,world.world_resources.storage_inventory(crate),2)
	world.world_resources.drop_from_inventory(a.resources,0,1,position)
	a.survival.damage(15)
	var kiln_cell: Vector3i=Vector3i(3,21,3)
	world.creation.add_object(&"leyforge:kiln",kiln_cell,2);save.record_voxel_edit(kiln_cell,_catalog.get_voxel_id(&"leyforge:kiln"),0)
	var station: LfeWorkstation=world.creation.station(world.creation.object_at(kiln_cell))
	LfeItemTransactions.add(station.input,&"leyforge:oak_heartwood",2);LfeItemTransactions.add(station.fuel,&"leyforge:oak_heartwood",1);station.start("leyforge:charcoal_burn");world.advance_world(3)
	_check(save.save(world.players_snapshot(),world.world_resources.snapshot(),world.creation.snapshot())==OK,"Rich source fixture has durable tools, drops, storage and kiln reservation")
	var source: Dictionary=_payload(save.get_primary_path())
	for version: int in [1,2,3]:
		var legacy: Dictionary=LfeTestWorldSave.legacy_payload(source,version)
		var id: String="historical_v%d" % version
		legacy["metadata"]["world_id"]=id
		if version<3:legacy.erase("creation");legacy["voxel_overrides"]=[]
		if version==1:legacy.erase("resources")
		if version==2:
			# Genuine v2 nonstateful item format; damaged tools entered in Wave 4.
			legacy["resources"]["inventory"][1]=null
		var primary: String=_root.path_join(id+"/world.json");_envelope(primary,legacy,version)
		var bytes: String=FileAccess.get_file_as_string(primary)
		var migrated: LfeWorldSave=_new(id,_profile_id)
		var player: Dictionary=migrated.players_state[0]
		_check(player["player_id"]==_profile_id and migrated.owner_player_id==_profile_id and player["transform"]==legacy["player"],"v%d assigns implicit character/owner to migration profile" % version)
		_check(FileAccess.get_file_as_string(primary)==bytes and migrated.worldgen_version==1,"v%d opening retains historical bytes/worldgen" % version)
		if version>=2:
			var combined: Dictionary=player["resources"].duplicate(true);combined.merge(migrated.world_resource_state)

			_check(_same(combined,legacy["resources"]),"v%d migration preserves quantities, identities, durability and positions" % version)
		else:_check(player["resources"]==LfePlayerResourceState.new(_catalog).snapshot() and migrated.world_resource_state==LfeWorldResourceState.new(_catalog).snapshot(),"v1 safe resources")
		if version==3:
			var combined: Dictionary=migrated.creation_state.duplicate(true);combined["survival"]=player["survival"]

			_check(_same(combined,legacy["creation"]),"v3 creation/survival split preserves every field and kiln reservation")
			var rendered: Dictionary=legacy.duplicate(true);rendered["metadata"]["world_id"]="rendered_v3"
			_envelope(_root.path_join("rendered_v3/world.json"),rendered,3)
		else:_check(player["survival"]==LfeCharacterSurvival.new().snapshot() and migrated.creation_state["objects"].is_empty(),"Historical creation defaults safe")
		_check(migrated.save()==OK and FileAccess.get_file_as_string(primary+".previous")==bytes,"v%d explicit save writes v4 and retains historical previous copy" % version)
		var restarted: LfeWorldSave=_new(id,_profile_id)
		_check(restarted.players_state==migrated.players_state and restarted.creation_state==migrated.creation_state and restarted.world_resource_state==migrated.world_resource_state,"v%d -> v4 exact restart" % version)

func _restart() -> void:
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(_out.path_join("expected_restart.json")))
	_check(_profile_id==expected["profile_id"],"Profile survives a genuinely fresh process")
	var save: LfeWorldSave=_new("two_players")
	_check(_same(save.players_state,expected["players"]),"Fresh-process exact transform/inventory/equipment/hotbar/survival for both players")
	_check(_same(save.world_resource_state,expected["resources"]) and _same(save.creation_state,expected["creation"]) and _same(save.overrides.serialized_entries(),expected["overrides"]),"Fresh-process shared drops/storage/station/reservations/source state/voxel edits exact")
	_check(_payload(save.get_primary_path())["metadata"]["save_version"]==4 and save.owner_player_id==A,"Fresh-process v4 owner persists")

func _slot(inventory: LfeInventory,id: StringName) -> int:
	for n: int in inventory.capacity():
		if inventory.stack_at(n).get("content")==String(id):return n
	return -1
func _payload(primary: String) -> Dictionary:
	var envelope: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(primary))
	return JSON.parse_string(envelope["payload_json"])
func _envelope(primary: String,payload: Dictionary,version: int) -> void:
	var raw: String=JSON.stringify(payload,"",true,true)
	_write(primary,JSON.stringify({"save_version":version,"payload_json":raw,"sha256":raw.sha256_text()},"\t"))
func _write(p: String,text: String) -> void:
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f: FileAccess=FileAccess.open(p,FileAccess.WRITE)
	if f==null:_check(false,"Disposable file could not be written");return
	f.store_string(text);f.flush()
func _check(condition: bool,message: String) -> void:
	_checks+=1
	if not condition:_failures.append(message)

# JSON's parser represents all numeric tokens as floats; compare exact numbers,
# without requiring an integer field's transient Variant type to be identical.
func _same(actual: Variant,expected: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(actual,"",true,true))==JSON.parse_string(JSON.stringify(expected,"",true,true))
