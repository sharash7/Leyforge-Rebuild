extends SceneTree
var checks: int = 0
var failures: Array[String] = []
var output: String = ""
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var auth: LfePrivateSessionAuth = LfePrivateSessionAuth.new()
	check(auth.initialize(),"secure initialization")
	var rfc_key: PackedByteArray = PackedByteArray(); rfc_key.resize(20); rfc_key.fill(11)
	check(Crypto.new().hmac_digest(HashingContext.HASH_SHA256,rfc_key,"Hi There".to_utf8_buffer()).hex_encode() == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7","RFC 4231 HMAC-SHA256 vector")
	check(auth._secret.size() == 16 and auth.session_instance.length() == 32,"128-bit distinct session/secret")
	check(auth._secret.hex_encode() != auth.session_instance,"separate identities")
	check(auth.display_invite().length() == 39 and LfePrivateSessionAuth.parse_invite(auth.display_invite()) == auth._secret,"grouped round trip")
	for value: String in ["","123456","g".repeat(32),"-"+"a".repeat(32),"aaaa-".repeat(8),"a".repeat(40)]: check(LfePrivateSessionAuth.parse_invite(value).is_empty(),"malformed invite")
	var manifest: Dictionary = LfeCompatibilityManifest.hello("a".repeat(32),LfeCompatibilityManifest.fingerprint())
	var hello: Dictionary = LfePrivateSessionAuth.hello(manifest,LfePrivateSessionAuth.random_token())
	var challenge: Dictionary = auth.challenge(2,hello,100,6000)
	check(not challenge.is_empty() and not challenge.has("world") and not challenge.has("secret"),"challenge reveals no world/secret")
	check(auth.challenge(2,hello,100,6000).is_empty() and auth.challenge(3,hello,100,6000).is_empty(),"one challenge per peer and no reused pending nonce")
	for value: Variant in [true,false,1.5,"1",[],{},null]:
		var malformed_hello: Dictionary = hello.duplicate(true); malformed_hello["auth_version"] = value
		var malformed_challenge: Dictionary = challenge.duplicate(true); malformed_challenge["auth_version"] = value
		check(not LfePrivateSessionAuth.valid_hello(malformed_hello) and not LfePrivateSessionAuth.valid_challenge(malformed_challenge),"reject malformed auth-version type")
	var proof: Dictionary = LfePrivateSessionAuth.proof(auth._secret,manifest,hello["client_nonce"],challenge)
	check(proof["proof"].length() == 64,"fixed HMAC output")
	check(not JSON.stringify([hello,challenge,proof]).contains(auth._secret.hex_encode()),"secret absent on wire")
	check(auth.verify(2,proof,101) == manifest and auth.pending.is_empty(),"valid proof consumes challenge")
	check(auth.verify(2,proof,101).is_empty(),"proof cannot be reused")
	var reordered: Dictionary = {}; var keys: Array = manifest.keys(); keys.reverse()
	for key: String in keys: reordered[key] = manifest[key]
	check(LfePrivateSessionAuth.transcript(manifest,hello["client_nonce"],challenge) == LfePrivateSessionAuth.transcript(reordered,hello["client_nonce"],challenge),"order-independent canonical framing")
	for field: String in ["player_id","build_version","content_hash","network_protocol_version","save_version","content_version","worldgen_versions"]:
		var changed: Dictionary = manifest.duplicate(true)
		if field == "worldgen_versions": changed[field] = [1]
		elif field in ["network_protocol_version","save_version","content_version"]: changed[field] += 1
		else: changed[field] = str(changed[field])+"x"
		check(LfePrivateSessionAuth.proof(auth._secret,changed,hello["client_nonce"],challenge) != proof,"transcript binds "+field)
	for kind: String in ["wrong","missing","malformed","byte","session","stale","replay","nonce","player","build","content"]:
		hello = LfePrivateSessionAuth.hello(manifest,LfePrivateSessionAuth.random_token())
		challenge = auth.challenge(2,hello,100,6000)
		var key: PackedByteArray = auth._secret.duplicate()
		if kind == "wrong": key[0] ^= 1
		if kind == "missing": key.clear()
		var used_manifest: Dictionary = manifest.duplicate(true)
		if kind in ["player","build","content"]: used_manifest[{"player":"player_id","build":"build_version","content":"content_hash"}[kind]] = "b".repeat(32 if kind == "player" else 64)
		var received: Dictionary = LfePrivateSessionAuth.proof(key,used_manifest,LfePrivateSessionAuth.random_token() if kind == "nonce" else hello["client_nonce"],challenge)
		if kind == "byte": received["proof"] = ("0" if received["proof"][0] != "0" else "1")+received["proof"].substr(1)
		if kind == "malformed": received["proof"] = "bad"
		if kind == "session": received["session_instance"] = "0".repeat(32)
		if kind == "replay": received = proof
		check(auth.verify(2,received,6100 if kind == "stale" else 101).is_empty() and auth.pending.is_empty(),"denied/cleared "+kind)
	for field: String in ["kind","session_instance","proof"]:
		for value: Variant in [true,1,[],{},null]:
			hello = LfePrivateSessionAuth.hello(manifest,LfePrivateSessionAuth.random_token())
			challenge = auth.challenge(2,hello,100,6000)
			var malformed: Dictionary = LfePrivateSessionAuth.proof(auth._secret,manifest,hello["client_nonce"],challenge)
			malformed[field] = value
			check(auth.verify(2,malformed,101).is_empty() and auth.pending.is_empty(),"reject malformed proof type "+field)
	var bad: Dictionary = hello.duplicate(true); bad["client_nonce"] = "bad"
	check(auth.challenge(2,bad,0,6000).is_empty(),"malformed nonce")
	for peer: int in range(2,10): check(not auth.challenge(peer,LfePrivateSessionAuth.hello(manifest,LfePrivateSessionAuth.random_token()),0,6000).is_empty(),"bounded pending entry")
	check(auth.pending.size() == 8 and auth.challenge(10,hello,0,6000).is_empty(),"pending flood bounded")
	var previous: String = auth.session_instance; var previous_secret: PackedByteArray = auth._secret.duplicate()
	check(auth.initialize() and auth.session_instance != previous and auth._secret != previous_secret and auth.pending.is_empty(),"HOST restart new session/secret")
	for address: String in ["10.0.0.1","172.16.2.1","192.168.1.1","127.0.0.1","169.254.1.1","100.64.0.1","100.127.255.254","::1","fe80::1","fd00::1"]: check(LfeHostConnectivity.classification(address) == "non_routable","CGNAT/private classification")
	check(LfeHostConnectivity.classification("100.128.0.1") == "global_candidate" and LfeHostConnectivity.classification("") == "unknown","no false definite CGNAT")
	check(LfeSessionOptions.valid_address("::1") and LfeSessionOptions.valid_address("host.example") and not LfeSessionOptions.valid_address("bad host"),"IPv6 and DNS")
	check(LfeCompatibilityManifest.PROTOCOL == 7 and LfeNetworkSession.CONNECT_SECONDS == 12 and LfeNetworkSession.AUTH_SECONDS == 6 and LfeNetworkSession.LIVENESS_MSEC == 10000,"WAN bounded timeouts")
	for packet: Dictionary in [{"kind":"session_ping","sequence":1},{"kind":"session_pong","sequence":2147483647}]: check(not LfeSessionLifecycleProtocol.decode(LfeSessionLifecycleProtocol.encode(packet)).is_empty(),"bounded ping")
	check(LfeSessionLifecycleProtocol.encode({"kind":"session_ping","sequence":0}).is_empty(),"ping invalid sequence")
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE); file.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures})); file=null
	print("W5_8_FOCUSED checks=%d failures=%d" % [checks,failures.size()]); quit(0 if failures.is_empty() else 1)
