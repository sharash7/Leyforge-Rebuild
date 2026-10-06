class_name LfeCharacterSurvival
extends RefCounted

# Set 29B/C reference rates use simulation seconds, not render frames.
const KEYS: Array[String] = ["health", "stamina", "hunger", "thirst", "fatigue", "exposure"]
const PROFILES: Dictionary = {
	"Standard": {"hunger":1.0,"thirst":false,"fatigue":1.0,"health_delay":20.0,"health_rate":0.1,"regen":16.0,"spend_delay":1.25,"empty_delay":2.25,"attrition":true},
	"Peaceful": {"hunger":0.35,"thirst":false,"fatigue":0.25,"health_delay":8.0,"health_rate":0.2,"regen":20.0,"spend_delay":0.75,"empty_delay":1.5,"attrition":false},
	"Relaxed": {"hunger":0.55,"thirst":false,"fatigue":0.5,"health_delay":12.0,"health_rate":0.15,"regen":18.0,"spend_delay":1.0,"empty_delay":1.75,"attrition":false},
	"Harsh": {"hunger":1.35,"thirst":true,"fatigue":1.5,"health_delay":30.0,"health_rate":0.07,"regen":14.0,"spend_delay":1.5,"empty_delay":3.0,"attrition":true}}
var profile_name: String = "Standard"
var _test_rate: float = 1.0
var _values: Dictionary = {"health":100.0,"stamina":100.0,"hunger":100.0,"thirst":100.0,"fatigue":0.0,"exposure":0.0}
var _timing: Dictionary = {"health_delay":0.0,"stamina_delay":0.0,"starvation":0.0,"dehydration":0.0}

func configure_profile(name: String) -> bool:
	if not PROFILES.has(name):
		return false
	profile_name = name
	return true

# Verification only: requires an explicit isolated Wave 4 test invocation.
# It scales biology time, never workstation/world time or production defaults.
func configure_test_rate(rate: float) -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--wave4-test-survival") or not LfeWorldSave._finite_in_range(rate,3600) or rate < 1:
		return false
	if not args.has("--wave4-playtest") and not args.has("--wave4-focused"):
		return false
	_test_rate = rate
	print("WAVE_4_TEST_SURVIVAL_RATE=%s PROFILE=%s" % [rate,profile_name])
	return true

func thirst_enabled() -> bool:
	return PROFILES[profile_name]["thirst"]

func snapshot() -> Dictionary:
	var result: Dictionary = _values.duplicate(true)
	result["timing"] = _timing.duplicate(true)
	return result

func restore(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if data.size() != KEYS.size() + (1 if data.has("timing") else 0):
		return false
	for key: String in KEYS:
		if not LfeWorldSave._finite_in_range(data.get(key),100) or float(data[key]) < 0:
			return false
	var timing: Dictionary = {"health_delay":0.0,"stamina_delay":0.0,"starvation":0.0,"dehydration":0.0}
	if data.has("timing"):
		if not data["timing"] is Dictionary or data["timing"].size() != timing.size():
			return false
		for key: String in timing:
			var limit: float = 60.0 if key.ends_with("delay") else 1000000000.0
			if not LfeWorldSave._finite_in_range(data["timing"].get(key),limit) or float(data["timing"][key]) < 0:
				return false
			timing[key] = float(data["timing"][key])
	for key: String in KEYS:
		_values[key] = float(data[key])
	_timing = timing
	return true

func alive() -> bool:
	return float(_values["health"]) > 0

func exert(amount: float) -> bool:
	if not alive() or not LfeWorldSave._finite_in_range(amount,100) or amount <= 0 or float(_values["stamina"]) < amount:
		return false
	_values["stamina"] -= amount
	var p: Dictionary = PROFILES[profile_name]
	_timing["stamina_delay"] = float(p["empty_delay"] if _values["stamina"] == 0 else p["spend_delay"])
	return true

func damage(amount: float) -> bool:
	if not alive() or not LfeWorldSave._finite_in_range(amount,100) or amount <= 0:
		return false
	_values["health"] = maxf(0,float(_values["health"])-amount)
	_timing["health_delay"] = float(PROFILES[profile_name]["health_delay"])
	return true

func respawn() -> void:
	_values["health"] = 50.0
	_values["stamina"] = 50.0
	_timing["health_delay"] = float(PROFILES[profile_name]["health_delay"])

func advance(seconds: float, sheltered: bool, resting: bool, sprinting: bool) -> bool:
	if not LfeWorldSave._finite_in_range(seconds,60) or seconds < 0:
		return false
	# Small bounded slices make debt threshold crossings and recovery deterministic.
	var left: float = seconds * _test_rate
	while left > 0:
		var dt: float = minf(left,1.0)
		_step(dt,sheltered,resting,sprinting)
		left = maxf(0,left-dt)
	return true

func _step(dt: float, sheltered: bool, resting: bool, sprinting: bool) -> void:
	var p: Dictionary = PROFILES[profile_name]
	var old_hunger: float = float(_values["hunger"])
	var old_thirst: float = float(_values["thirst"])
	var thirst_rate: float = 5.0/3600.0*(1.1 if profile_name=="Harsh" else 1.0)
	_values["hunger"] = maxf(0,old_hunger-dt*4.0/3600.0*float(p["hunger"]))
	if thirst_enabled():
		_values["thirst"] = maxf(0,float(_values["thirst"])-dt*thirst_rate)
	if resting and sheltered:
		_values["fatigue"] = maxf(0,float(_values["fatigue"])-dt*0.05/60.0)
	elif sprinting:
		_values["fatigue"] = minf(100,float(_values["fatigue"])+dt*0.18/60.0*float(p["fatigue"]))
	# Wave 4 supplies benign conditions. Weather/biome hazards arrive in Wave 6.
	# Legacy exposure is retained and can recover in shelter, never grows outdoors.
	if sheltered:
		_values["exposure"] = maxf(0,float(_values["exposure"])-dt*2.0/60.0)
	var stamina_delay: float = float(_timing["stamina_delay"])
	if sprinting and float(_values["stamina"]) > 0:
		exert(minf(float(_values["stamina"]),dt*12.0)) # Representative movement cost.
	else:
		_timing["stamina_delay"] = maxf(0,stamina_delay-dt)
		_values["stamina"] = minf(100,float(_values["stamina"])+maxf(0,dt-stamina_delay)*float(p["regen"]))
	var health_delay: float = float(_timing["health_delay"])
	_timing["health_delay"] = maxf(0,health_delay-dt)
	var nourished: bool = float(_values["hunger"]) > 20 and (not thirst_enabled() or float(_values["thirst"]) > 20)
	if nourished and alive(): # Current Wave 4 environment is benign; shelter is not a healing tax.
		_values["health"] = minf(100,float(_values["health"])+maxf(0,dt-health_delay)*float(p["health_rate"]))
	var hunger_empty: float = dt if old_hunger == 0 else maxf(0,dt-old_hunger/(4.0/3600.0*float(p["hunger"])))
	_debt("starvation",hunger_empty,float(_values["hunger"]),6*3600.0,24*3600.0,0.5,1.0,2.0,p["attrition"],dt)
	if thirst_enabled():
		_debt("dehydration",dt if old_thirst==0 else maxf(0,dt-old_thirst/thirst_rate),float(_values["thirst"]),2*3600.0,8*3600.0,1.0,2.0,3.0,p["attrition"],dt)

func _debt(key: String, empty_seconds: float, reserve: float, grace: float, late: float, rate: float, late_rate: float, decay: float, harmful: bool, dt: float) -> void:
	var before: float = float(_timing[key])
	if empty_seconds > 0:
		var after: float = minf(1000000000,before+empty_seconds)
		_timing[key] = after
		if harmful:
			var early_seconds: float = maxf(0,minf(after,late)-maxf(before,grace))
			var late_seconds: float = maxf(0,after-maxf(before,late))
			var loss: float = (early_seconds*rate+late_seconds*late_rate)/3600.0
			if loss > 0 and alive():
				damage(minf(100,loss))
	else:
		if harmful and reserve<=20 and before>grace and alive():
			damage(minf(100,dt*(late_rate if before>late else rate)/3600.0))
		if reserve > (40 if key=="starvation" else 60):
			_timing[key] = maxf(0,before-decay*dt)

func consume(inventory: LfeInventory, slot: int) -> bool:
	var stack: Dictionary = inventory.stack_at(slot)
	if stack.is_empty() or not alive():
		return false
	var effects: Dictionary = inventory._catalog.content_definition(StringName(stack["content"])).get("consume",{})
	var changed: bool = false
	var next: Dictionary = snapshot()
	for key: String in effects:
		if key=="thirst" and not thirst_enabled():
			continue
		var value: float = minf(100,float(next[key])+float(effects[key]))
		changed = changed or value != float(next[key])
		next[key] = value
	# Prepare both sides before publishing either. Canonical biology remains the
	# sole implementation; a failed removal/restore cannot destroy an item.
	var prepared: LfeInventory = LfeInventory.new(inventory._catalog,inventory.capacity(),inventory._restrictions)
	var biology: LfeCharacterSurvival = LfeCharacterSurvival.new()
	if not changed or not biology.restore(next) or not prepared.restore(inventory.snapshot()) or not LfeItemTransactions.remove(prepared,slot,1):
		return false
	inventory._slots = prepared.snapshot()
	_values = biology._values.duplicate(true)
	_timing = biology._timing.duplicate(true)
	return true
