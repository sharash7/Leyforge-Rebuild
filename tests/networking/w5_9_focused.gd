extends SceneTree

var checks: int = 0
var failures: Array[String] = []
var catalog: LfeBlockCatalog
var output: String
var families: Dictionary = {}

func _initialize() -> void: call_deferred("_run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func decode(family: String, bytes: PackedByteArray) -> Variant:
	match family:
		"auth": return LfePrivateSessionAuth.valid_hello(LfeCompatibilityManifest.decode(bytes))
		"movement": return not LfeMovementProtocol.decode(bytes).is_empty()
		"voxel": return not LfeVoxelProtocol.decode(bytes,catalog).is_empty()
		"resource": return not LfeResourceProtocol.decode(bytes,catalog).is_empty()
		"survival": return not LfeSurvivalProtocol.decode(bytes).is_empty()
		"lifecycle": return not LfeSessionLifecycleProtocol.decode(bytes).is_empty()
	return false

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	catalog=LfeBlockCatalog.new();check(catalog.load_default()==OK,"canonical catalogue")
	check(ProjectSettings.get_setting("application/config/version")=="0.6.1-wave5-w5.9","candidate app")
	check(LfeCompatibilityManifest.PROTOCOL==7 and LfeWorldSave.SAVE_VERSION==4 and LfeWorldSave.CONTENT_VERSION==1 and LfeWorldSave.WORLDGEN_VERSION==2,"unchanged compatibility")
	check(LfeNetworkSession.MAX_PLAYERS==8 and LfeMovementProtocol.MAX_PLAYERS==8,"consistent eight-player bounds")
	var hello: Dictionary=LfeCompatibilityManifest.hello("a".repeat(32),LfeCompatibilityManifest.fingerprint())
	var samples: Dictionary={
		"auth":LfePrivateSessionAuth.hello(hello,LfePrivateSessionAuth.random_token()),
		"movement":LfeMovementProtocol.input(1,{"move":Vector2.ZERO,"jump":false,"sprint":false,"yaw":0.0,"pitch":0.0},1),
		"voxel":{"kind":"voxel_harvest_state","action_sequence":1,"active":true,"target_cell":[0,20,0],"expected_block":"leyforge:dirt"},
		"resource":{"kind":"resource_request","sequence":1,"transaction_id":"b".repeat(32),"operation":"select","args":{"slot":0},"expected_revisions":{}},
		"survival":LfeSurvivalProtocol.view(LfeCharacterSurvival.new(),1,1,false,false),
		"lifecycle":{"kind":"session_ping","sequence":1}}
	for family: String in samples:
		var before: int=checks
		var good: Dictionary=samples[family]
		check(decode(family,JSON.stringify(good).to_utf8_buffer()),family+" valid control")
		for key: String in good:
			var missing: Dictionary=good.duplicate(true);missing.erase(key)
			check(not decode(family,JSON.stringify(missing).to_utf8_buffer()),family+" missing "+key)
		var extra: Dictionary=good.duplicate(true);extra["actor_id"]="c".repeat(32)
		check(not decode(family,JSON.stringify(extra).to_utf8_buffer()),family+" spoof/unknown key")
		for text: String in ["null","[]","true","1","{}","{",'{"kind":null}',JSON.stringify(good)+"x"," ".repeat(9000)+JSON.stringify(good)]:
			check(not decode(family,text.to_utf8_buffer()),family+" malformed/oversized shape")
		var invalid_kind: Dictionary=good.duplicate(true);invalid_kind["kind"]="impossible"
		check(not decode(family,JSON.stringify(invalid_kind).to_utf8_buffer()),family+" unknown kind")
		families[family]=checks-before
	for number: float in [NAN,INF,-INF]:
		check(not LfeMovementProtocol.finite(number,1000000),"nonfinite movement")
		check(not LfeVoxelProtocol.coordinate([number,0,0]),"nonfinite voxel")
		var bad: Dictionary=samples["survival"].duplicate(true);bad["health"]=number
		check(not LfeSurvivalProtocol.valid(bad),"nonfinite survival")
	for value: Variant in [-1,0,1.5,2147483648,"1",null,true,{},[]]:
		for family: String in ["movement","resource","lifecycle"]:
			var bad: Dictionary=samples[family].duplicate(true);bad["sequence"]=value
			check(not decode(family,JSON.stringify(bad).to_utf8_buffer()),family+" invalid sequence")
	var world: Dictionary={"world_id":"w59","seed":184552221,"worldgen_version":2,"save_version":4,"content_version":1,"content_hash":hello["content_hash"],"network_protocol_version":7}
	var old: Dictionary=hello.duplicate(true);old["build_version"]="0.6.0-wave5-w5.8"
	check(LfeCompatibilityManifest.validate_hello(old,hello,world)=="build_mismatch","exact previous build rejected")
	for version: int in [1,2]:
		var first: LfeWave1TerrainGenerator=LfeWave1TerrainGenerator.new();first.configure(184552221,catalog,version)
		var second: LfeWave1TerrainGenerator=LfeWave1TerrainGenerator.new();second.configure(184552221,catalog,version)
		for x: int in [-33,-17,-16,-1,0,15,16,31,129]:
			for z: int in [-17,0,16,130]:
				for y: int in [0,15,20,25,30,40]:
					check(first.sample_voxel_id(Vector3i(x,y,z))==second.sample_voxel_id(Vector3i(x,y,z)),"deterministic v"+str(version))
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"families":families}));file=null
	print("W5_9_FOCUSED checks=%d failures=%d" % [checks,failures.size()]);quit(0 if failures.is_empty() else 1)
