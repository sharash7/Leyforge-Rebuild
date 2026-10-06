class_name LfeSurvivalProtocol
extends RefCounted

const CONTROL_CHANNEL: int = 9
const SNAPSHOT_CHANNEL: int = 10
const MAX_BYTES: int = 1024
const HZ: float = 10.0
const KEYS: Array = ["kind","revision","mutation_revision","health","stamina","hunger","thirst","fatigue","exposure","alive","thirst_enabled","profile","sheltered","resting"]

static func valid(p: Variant) -> bool:
	if not p is Dictionary: return false
	if p.get("kind") == "survival_resync": return LfeCompatibilityManifest.exact_keys(p,["kind"])
	if not LfeCompatibilityManifest.exact_keys(p,KEYS) or p["kind"] not in ["survival_state","survival_snapshot"]: return false
	for key: String in ["revision","mutation_revision"]:
		if not LfeResourceProtocol.integer(p[key],1,LfeResourceProtocol.MAX_SEQUENCE): return false
	for key: String in LfeCharacterSurvival.KEYS:
		if not LfeWorldSave._finite_in_range(p[key],100) or float(p[key]) < 0: return false
	for key: String in ["alive","thirst_enabled","sheltered","resting"]:
		if not p[key] is bool: return false
	return p["profile"] is String and LfeCharacterSurvival.PROFILES.has(p["profile"]) and p["thirst_enabled"] == LfeCharacterSurvival.PROFILES[p["profile"]]["thirst"] and p["alive"] == (float(p["health"]) > 0) and (not p["resting"] or p["sheltered"])

static func view(s: LfeCharacterSurvival, revision: int, mutation: int, sheltered: bool, resting: bool, reliable: bool = true) -> Dictionary:
	var p: Dictionary = s.snapshot()
	p.erase("timing")
	p.merge({"kind":"survival_state" if reliable else "survival_snapshot","revision":revision,"mutation_revision":mutation,"alive":s.alive(),"thirst_enabled":s.thirst_enabled(),"profile":s.profile_name,"sheltered":sheltered,"resting":resting and sheltered})
	return p

static func encode(p: Dictionary) -> PackedByteArray:
	if not valid(p): return PackedByteArray()
	var bytes: PackedByteArray = JSON.stringify(p).to_utf8_buffer()
	return bytes if bytes.size() <= MAX_BYTES else PackedByteArray()

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_BYTES: return {}
	var source: String = bytes.get_string_from_utf8()
	if source.to_utf8_buffer() != bytes: return {}
	var parser: JSON = JSON.new()
	if parser.parse(source) != OK or not valid(parser.data): return {}
	return parser.data
