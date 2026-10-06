extends SceneTree

var checks: int = 0
var failures: Array = []
var output: String
var catalog: LfeBlockCatalog
var fixture: String
var matrix: Array = []
const A: String = "11111111111111111111111111111111"
const B: String = "22222222222222222222222222222222"

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text); file.flush(); file = null

func _fixture(id: String) -> LfeWorldSave:
	var save: LfeWorldSave = LfeWorldSave.new()
	check(save.open_world(id,184552221,true,catalog,fixture,A) == OK,"new isolated "+id)
	var authority: LfeGameplayAuthority = LfeGameplayAuthority.new()
	check(authority.configure(save,catalog),"authority "+id)
	authority.add_character(A,Vector3(0.5,30.05,0.5))
	authority.add_character(B,Vector3(2.5,30.05,0.5))
	LfeItemTransactions.add(authority.character(B).resources.inventory,&"leyforge:oak_stick",3)
	check(save.save(authority.players_snapshot(),authority.world_resources.snapshot(),authority.creation.snapshot()) == OK,"first authoritative save "+id)
	return save

func _open(id: String) -> LfeWorldSave:
	var save: LfeWorldSave = LfeWorldSave.new()
	var result: Error = save.open_world(id,184552221,true,catalog,fixture,A)
	check(result == OK,"recovery opens "+id+" "+save.get_last_error())
	if result == OK:
		check(not save._validate_snapshot(save.players_state,save.world_resource_state,save.creation_state,save.owner_player_id).is_empty(),"whole authoritative graph "+id)
	return save

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	fixture = ProjectSettings.globalize_path("user://w57-fixtures")
	catalog = LfeBlockCatalog.new()
	check(catalog.load_default() == OK,"canonical catalogue")
	for kind: String in LfeSessionLifecycleProtocol.KINDS:
		var p: Dictionary = {"kind":kind}
		if kind == "session_closing": p["reason"] = "host_shutdown"
		check(LfeSessionLifecycleProtocol.decode(LfeSessionLifecycleProtocol.encode(p)) == p,"lifecycle roundtrip "+kind)
		var bad: Dictionary = p.duplicate(); bad["player_id"] = A
		check(LfeSessionLifecycleProtocol.encode(bad).is_empty(),"no claimed identity "+kind)
		for key: String in p:
			bad = p.duplicate(); bad.erase(key)
			check(LfeSessionLifecycleProtocol.encode(bad).is_empty(),"exact keys "+kind+key)
	for bytes: PackedByteArray in [PackedByteArray([255]),"{}".to_utf8_buffer(),"x".repeat(129).to_utf8_buffer(),'{"kind":"session_closing","reason":"other"}'.to_utf8_buffer()]:
		check(LfeSessionLifecycleProtocol.decode(bytes).is_empty(),"strict invalid lifecycle packet")
	check(LfeCompatibilityManifest.PROTOCOL == 6 and LfeWorldSave.SAVE_VERSION == 4 and LfeWorldSave.CONTENT_VERSION == 1 and LfeWorldSave.WORLDGEN_VERSION == 2,"versions")
	var local: Dictionary = LfeCompatibilityManifest.hello(A,LfeCompatibilityManifest.fingerprint())
	var world: Dictionary = {"world_id":"w57","seed":184552221,"worldgen_version":2,"save_version":4,"content_version":1,"content_hash":local["content_hash"],"network_protocol_version":6}
	var old: Dictionary = local.duplicate(true); old["network_protocol_version"] = 5
	check(LfeCompatibilityManifest.validate_hello(old,local,world) == "protocol_mismatch","real old wire hello")
	for phase: String in ["before_pending","after_pending_flush","after_pending_validation","after_rotation","before_promotion","after_promotion"]:
		var save: LfeWorldSave = _fixture(phase)
		var primary: String = save.get_primary_path()
		var prior: String = FileAccess.get_file_as_string(primary)
		var roster: Array = save.players_state.duplicate(true)
		roster[1]["survival"]["thirst"] = 37.0
		check(save.save(roster,save.world_resource_state,save.creation_state) == OK,"newer fixture "+phase)
		var newer: String = FileAccess.get_file_as_string(primary)
		if phase != "after_promotion":
			_write(primary,prior)
			if phase != "before_pending": _write(save.get_world_directory().path_join(LfeWorldSave.PENDING_FILE),newer)
		if phase in ["after_rotation","before_promotion"]:
			DirAccess.remove_absolute(primary)
			_write(save.get_world_directory().path_join(LfeWorldSave.PREVIOUS_FILE),prior)
		var loaded: LfeWorldSave = _open(phase)
		var uses_newer: bool = phase in ["after_rotation","before_promotion","after_promotion"]
		check(loaded.players_state[1]["survival"]["thirst"] == (37.0 if uses_newer else 100.0),"transaction commit choice "+phase)
		matrix.append({"phase":phase,"candidate":loaded.recovery_candidate,"reasons":loaded.recovery_reasons})
		check(loaded.save() == OK,"successful save after recovery "+phase)
		check(not FileAccess.file_exists(loaded.get_world_directory().path_join(LfeWorldSave.PENDING_FILE)),"pending retired only after primary durable "+phase)
		_open(phase)
	for corruption: String in ["json","checksum","payload","item_duplicate","player","object_parity"]:
		var save: LfeWorldSave = _fixture("bad_"+corruption)
		check(save.save() == OK,"establish previous "+corruption)
		var raw: String = FileAccess.get_file_as_string(save.get_primary_path())
		var envelope: Dictionary = JSON.parse_string(raw)
		var payload: Dictionary = JSON.parse_string(envelope["payload_json"])
		match corruption:
			"json": raw = "{broken"
			"checksum": envelope["sha256"] = "0".repeat(64)
			"payload": envelope["payload_json"] = "{}"; envelope["sha256"] = "{}".sha256_text()
			"player": payload["players"][1]["survival"]["thirst"] = -1
			"item_duplicate":
				var tool: Dictionary = LfeItemInstance.create(&"leyforge:wooden_pickaxe",catalog)
				payload["players"][0]["resources"]["inventory"][0] = tool
				payload["players"][1]["resources"]["inventory"][0] = tool.duplicate(true)
			"object_parity": payload["voxel_overrides"] = [{"position":[0,30,0],"block":"leyforge:workbench"}]
		if corruption in ["player","item_duplicate","object_parity"]:
			envelope["payload_json"] = JSON.stringify(payload); envelope["sha256"] = envelope["payload_json"].sha256_text()
		if corruption != "json": raw = JSON.stringify(envelope)
		_write(save.get_primary_path(),raw)
		var recovered: LfeWorldSave = _open("bad_"+corruption)
		check(recovered.recovery_candidate == LfeWorldSave.PREVIOUS_FILE,"full candidate rejection "+corruption)
		check(FileAccess.get_file_as_string(save.get_primary_path()) == raw,"corrupt primary retained on load "+corruption)
		check(recovered.save() == OK,"save recovered "+corruption)
		check(FileAccess.get_file_as_string(save.get_world_directory().path_join("world.json.corrupt")) == raw,"exact corrupt diagnostic preserved "+corruption)
		matrix.append({"corruption":corruption,"candidate":recovered.recovery_candidate,"reasons":recovered.recovery_reasons})
	var lone: LfeWorldSave = _fixture("no_valid")
	_write(lone.get_primary_path(),"broken")
	var closed: LfeWorldSave = LfeWorldSave.new()
	check(closed.open_world("no_valid",184552221,true,catalog,fixture,A) != OK,"no valid candidate fails closed")
	check(closed.save() != OK and FileAccess.get_file_as_string(lone.get_primary_path()) == "broken","failed load never resets world")
	_write(output,JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"recovery_matrix":matrix},"\t"))
	print("W5_7_FOCUSED_" + ("PASS" if failures.is_empty() else "FAIL") + " checks=%d" % checks)
	quit(0 if failures.is_empty() else 1)
