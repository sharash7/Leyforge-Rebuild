class_name LfePrivateSessionAuth
extends RefCounted

# One wire/crypto owner. Secrets are process memory only; packets contain proofs.
const AUTH_VERSION: int = 1
const RANDOM_BYTES: int = 16
const MAX_PENDING: int = 8
var session_instance: String = ""
var _secret: PackedByteArray = PackedByteArray()
var pending: Dictionary = {}

func initialize() -> bool:
	session_instance = random_token()
	_secret = Crypto.new().generate_random_bytes(RANDOM_BYTES)
	pending.clear()
	return valid_token(session_instance) and _secret.size() == RANDOM_BYTES

static func random_token() -> String:
	return Crypto.new().generate_random_bytes(RANDOM_BYTES).hex_encode()

static func valid_token(value: Variant, length: int = 32) -> bool:
	if not value is String or value.length() != length: return false
	for c: String in value:
		if c not in "0123456789abcdef": return false
	return true

static func parse_invite(value: String) -> PackedByteArray:
	if value.length() > 39: return PackedByteArray()
	var normalized: String = value.to_lower()
	if normalized.contains("-"):
		var groups: PackedStringArray = normalized.split("-")
		if groups.size() != 8: return PackedByteArray()
		for group: String in groups:
			if group.length() != 4: return PackedByteArray()
		normalized = normalized.replace("-", "")
	return normalized.hex_decode() if valid_token(normalized) else PackedByteArray()

func display_invite() -> String:
	var raw: String = _secret.hex_encode().to_upper()
	var groups: PackedStringArray = PackedStringArray()
	for index: int in range(0, raw.length(), 4): groups.append(raw.substr(index, 4))
	return "-".join(groups)

static func hello(manifest: Dictionary, client_nonce: String) -> Dictionary:
	return {"kind":"private_hello", "auth_version":AUTH_VERSION, "manifest":manifest, "client_nonce":client_nonce}

static func valid_hello(value: Variant) -> bool:
	return LfeCompatibilityManifest.exact_keys(value, ["kind","auth_version","manifest","client_nonce"]) and value["kind"] is String and value["kind"] == "private_hello" and LfeWorldSave._is_integer(value["auth_version"]) and int(value["auth_version"]) == AUTH_VERSION and value["manifest"] is Dictionary and valid_token(value["client_nonce"])

static func valid_challenge(value: Variant) -> bool:
	return LfeCompatibilityManifest.exact_keys(value, ["kind","auth_version","session_instance","server_nonce"]) and value["kind"] is String and value["kind"] == "private_challenge" and LfeWorldSave._is_integer(value["auth_version"]) and int(value["auth_version"]) == AUTH_VERSION and valid_token(value["session_instance"]) and valid_token(value["server_nonce"])

static func transcript(manifest: Dictionary, client_nonce: String, challenge: Dictionary) -> PackedByteArray:
	# Fixed field order, uint32 little-endian UTF-8 lengths. Never serialize a Dictionary.
	var fields: Array[String] = ["Leyforge/private-admission", str(AUTH_VERSION)]
	for key: String in ["network_protocol_version","build_version","content_hash","player_id","save_version","content_version"]:
		fields.append(str(int(manifest[key])) if key in ["network_protocol_version","save_version","content_version"] else str(manifest[key]))
	var versions: PackedStringArray = PackedStringArray()
	for version: Variant in manifest["worldgen_versions"]: versions.append(str(int(version)))
	fields.append(",".join(versions))
	fields.append(client_nonce); fields.append(challenge["server_nonce"]); fields.append(challenge["session_instance"])
	var result: PackedByteArray = PackedByteArray()
	for field: String in fields:
		var bytes: PackedByteArray = field.to_utf8_buffer()
		var frame: PackedByteArray = PackedByteArray(); frame.resize(4); frame.encode_u32(0,bytes.size())
		result.append_array(frame); result.append_array(bytes)
	return result

static func proof(secret: PackedByteArray, manifest: Dictionary, client_nonce: String, challenge: Dictionary) -> Dictionary:
	if secret.size() != RANDOM_BYTES or not valid_challenge(challenge) or not valid_token(client_nonce): return {}
	var digest: PackedByteArray = Crypto.new().hmac_digest(HashingContext.HASH_SHA256,secret,transcript(manifest,client_nonce,challenge))
	return {"kind":"private_proof","session_instance":challenge["session_instance"],"proof":digest.hex_encode()}

func challenge(peer: int, value: Dictionary, now: int, timeout: int) -> Dictionary:
	if pending.has(peer) or pending.size() >= MAX_PENDING or not valid_hello(value): return {}
	for attempt: Dictionary in pending.values():
		if attempt["hello"]["client_nonce"] == value["client_nonce"]: return {}
	var packet: Dictionary = {"kind":"private_challenge","auth_version":AUTH_VERSION,"session_instance":session_instance,"server_nonce":random_token()}
	if not valid_challenge(packet): return {}
	pending[peer] = {"hello":value.duplicate(true),"challenge":packet,"deadline":now+timeout}
	return packet

func verify(peer: int, value: Variant, now: int) -> Dictionary:
	if not pending.has(peer): return {}
	var attempt: Dictionary = pending[peer]
	pending.erase(peer) # Every proof consumes its challenge, including malformed proofs.
	if now >= attempt["deadline"] or not LfeCompatibilityManifest.exact_keys(value,["kind","session_instance","proof"]): return {}
	if not value["kind"] is String or value["kind"] != "private_proof" or not valid_token(value["session_instance"]) or value["session_instance"] != session_instance or not valid_token(value["proof"],64): return {}
	var expected: Dictionary = proof(_secret,attempt["hello"]["manifest"],attempt["hello"]["client_nonce"],attempt["challenge"])
	if not Crypto.new().constant_time_compare(expected["proof"].hex_decode(),value["proof"].hex_decode()): return {}
	return attempt["hello"]["manifest"]

func clear() -> void:
	pending.clear(); _secret.fill(0); _secret.clear(); session_instance = ""
