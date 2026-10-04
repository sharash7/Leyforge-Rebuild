extends "res://tests/wave_4/wave_4_playtest_driver.gd"

func _run() -> void:
	if not _world.is_runtime_ready():await _world.runtime_ready
	_check(_world.local_player_id==_world.active_character.player_id and _player.character_record==_world.active_character,"Local controller explicitly presents profile's character record")
	_check(_world.authority.character(_world.local_player_id)==_world.active_character,"Active character belongs to authoritative roster")
	_check(not _world.personal_resources.snapshot().has("drops") and not _world.creation.snapshot().has("survival"),"Rendered gameplay uses separated v4 owners")
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
