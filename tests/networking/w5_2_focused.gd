extends SceneTree

const A: String = "11111111111111111111111111111111"
var checks: int = 0
var failures: Array[String] = []
var fixture: String
var output: String

func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="): fixture = arg.trim_prefix("--fixture=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not fixture.is_absolute_path() or not output.is_absolute_path(): quit(1); return
	DirAccess.make_dir_recursive_absolute(fixture)
	var catalog: LfeBlockCatalog = LfeBlockCatalog.new()
	check(catalog.load_default() == OK,"canonical content loads")
	var save: LfeWorldSave = LfeWorldSave.new()
	check(save.open_world("focused",184552221,true,catalog,fixture,A) == OK,"save v4 host fixture")
	var hash: String = LfeCompatibilityManifest.fingerprint()
	var hello: Dictionary = LfeCompatibilityManifest.hello(A,hash)
	var world: Dictionary = LfeCompatibilityManifest.world(save,hash)
	check(hash.length() == 64,"runtime hash")
	check(LfeCompatibilityManifest.validate_hello(hello,hello,world) == "ok","compatible")
	for pair: Array in [["network_protocol_version",2,"protocol_mismatch"],["build_version","other","build_mismatch"],["save_version",3,"save_schema_mismatch"],["content_version",2,"content_version_mismatch"],["content_hash","a".repeat(64),"content_hash_mismatch"],["player_id","bad","invalid_identity"]]:
		var bad: Dictionary = hello.duplicate(true)
		bad[pair[0]] = pair[1]
		check(LfeCompatibilityManifest.validate_hello(bad,hello,world) == pair[2],pair[2])
	world["worldgen_version"] = 1
	check(LfeCompatibilityManifest.validate_hello(hello,hello,world) == "ok","legacy worldgen v1 accepted")
	world["worldgen_version"] = 99
	check(LfeCompatibilityManifest.validate_hello(hello,hello,world) == "worldgen_unsupported","unsupported actual world")
	world["worldgen_version"] = 2
	for bad: Variant in [null,[],{},{"extra":1}]:
		check(LfeCompatibilityManifest.validate_hello(bad,hello,world) == "malformed_handshake","malformed structure")
	for key: String in hello:
		var bad: Dictionary = hello.duplicate(true)
		bad.erase(key)
		check(LfeCompatibilityManifest.validate_hello(bad,hello,world) == "malformed_handshake","missing " + key)
	for key: String in ["network_protocol_version","save_version","content_version"]:
		for value: Variant in [true,"1",1.5,0,-1,65536,null]:
			var bad: Dictionary = hello.duplicate(true)
			bad[key] = value
			check(LfeCompatibilityManifest.validate_hello(bad,hello,world) == "malformed_handshake","version bounds/types")
	for value: Variant in [[],[1,1],[0],[1.5],["2"],range(1,11),null]:
		var bad: Dictionary = hello.duplicate(true)
		bad["worldgen_versions"] = value
		check(LfeCompatibilityManifest.validate_hello(bad,hello,world) == "malformed_handshake","worldgen array bound")
	check(LfeCompatibilityManifest.decode("x".repeat(4097).to_utf8_buffer()) == null,"oversized payload")
	check(LfeCompatibilityManifest.decode("{broken".to_utf8_buffer()) == null,"malformed JSON")
	check(LfeCompatibilityManifest.validate_hello(LfeCompatibilityManifest.decode(JSON.stringify(hello).to_utf8_buffer()),hello,world) == "ok","JSON wire numbers compatible")
	check(LfeCompatibilityManifest.valid_world(world,hello),"host manifest validation")
	for key: String in world:
		var bad: Dictionary = world.duplicate(true)
		bad.erase(key)
		check(not LfeCompatibilityManifest.valid_world(bad,hello),"world manifest missing field")
	for args: PackedStringArray in [PackedStringArray(["--session=bad"]),PackedStringArray(["--port=0"]),PackedStringArray(["--port=65536"]),PackedStringArray(["--port=4.2"]),PackedStringArray(["--session=HOST","--session=JOIN"]),PackedStringArray(["--address=bad address"]),PackedStringArray(["--profile-path=res://profile.json"]),PackedStringArray(["--profile-path=relative.json"]),PackedStringArray(["--profile-path=user://identity/../x.json"]),PackedStringArray(["--profile-path=" + ProjectSettings.globalize_path("res://bad.json")])]:
		check(not LfeSessionOptions.new().parse(args),"invalid launch args")
	var options: LfeSessionOptions = LfeSessionOptions.new()
	check(options.parse(PackedStringArray()) and options.mode == "OFFLINE","default offline no socket")
	options = LfeSessionOptions.new()
	check(options.parse(PackedStringArray(["--session=JOIN"])) and options.profile_path == LfeSessionOptions.CLIENT_PROFILE,"join dedicated identity")
	var network: LfeNetworkSession = LfeNetworkSession.new()
	check(network.state == "OFFLINE" and network._api == null,"offline no MultiplayerAPI")
	check(not network.transition("CONNECTED") and network.state == "OFFLINE","invalid transition fails safely")
	check(network.transition("CONNECTING") and network.transition("AUTHENTICATING") and network.transition("CONNECTED") and network.transition("DISCONNECTED","server_disconnected"),"bounded state flow")
	check(not network.transition("unknown"),"unknown state safe")
	network.free()
	_write(fixture.path_join("a.json"),"one")
	_write(fixture.path_join("b.json"),"two")
	_write(fixture.path_join(".gitkeep"),"ignored")
	var order_a: Array[String] = ["a.json","b.json",".gitkeep"]
	var order_b: Array[String] = ["b.json",".gitkeep","a.json"]
	var first: String = LfeCompatibilityManifest.fingerprint(fixture,order_a)
	check(first == LfeCompatibilityManifest.fingerprint(fixture,order_b),"enumeration order independent")
	_write(fixture.path_join(".gitkeep"),"different placeholder")
	check(first == LfeCompatibilityManifest.fingerprint(fixture,order_b),"placeholder ignored")
	_write(fixture.path_join("b.json"),"twO")
	check(first != LfeCompatibilityManifest.fingerprint(fixture,order_a),"one byte changes fingerprint")
	var profile: LfeLocalProfile = LfeLocalProfile.new()
	var profile_path: String = fixture.path_join("identity.json")
	check(profile.open_profile(profile_path) == OK,"profile override atomic creation")
	var again: LfeLocalProfile = LfeLocalProfile.new()
	check(again.open_profile(profile_path) == OK and again.player_id == profile.player_id,"profile stable")
	_write(output,JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}, "\t"))
	print("W5_2_FOCUSED_" + ("PASS" if failures.is_empty() else "FAIL") + " checks=%d" % checks)
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text)