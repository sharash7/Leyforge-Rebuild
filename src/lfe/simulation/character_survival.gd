class_name LfeCharacterSurvival
extends RefCounted

const KEYS: Array[String] = ["health", "stamina", "hunger", "thirst", "fatigue", "exposure"]
var _values: Dictionary = {"health":100.0, "stamina":100.0, "hunger":100.0, "thirst":100.0, "fatigue":0.0, "exposure":0.0}

func snapshot() -> Dictionary:
	return _values.duplicate(true)

func restore(data: Variant) -> bool:
	if not data is Dictionary or data.size() != KEYS.size():
		return false
	for key: String in KEYS:
		if not LfeWorldSave._finite_in_range(data.get(key), 100) or float(data[key]) < 0:
			return false
	for key: String in KEYS:
		_values[key] = float(data[key])
	return true

func alive() -> bool:
	return float(_values["health"]) > 0

func exert(amount: float) -> bool:
	if not alive() or not LfeWorldSave._finite_in_range(amount, 100) or amount <= 0 or float(_values["stamina"]) < amount:
		return false
	_values["stamina"] -= amount
	return true

func damage(amount: float) -> bool:
	if not alive() or not LfeWorldSave._finite_in_range(amount, 100) or amount <= 0:
		return false
	_values["health"] = maxf(0, float(_values["health"]) - amount)
	return true

func respawn() -> void:
	_values["health"] = 50.0
	_values["stamina"] = 50.0

func advance(seconds: float, sheltered: bool, resting: bool, sprinting: bool) -> bool:
	if not LfeWorldSave._finite_in_range(seconds, 60) or seconds < 0:
		return false
	_values["hunger"] = maxf(0, float(_values["hunger"]) - seconds * 0.04)
	_values["thirst"] = maxf(0, float(_values["thirst"]) - seconds * 0.06)
	_values["fatigue"] = clampf(float(_values["fatigue"]) + seconds * (-3.0 if resting and sheltered else 0.025), 0, 100)
	_values["exposure"] = clampf(float(_values["exposure"]) + seconds * (-2.0 if sheltered else 0.04), 0, 100)
	_values["stamina"] = clampf(float(_values["stamina"]) + seconds * (-12.0 if sprinting else 8.0), 0, 100)
	if resting and sheltered and float(_values["hunger"]) > 0 and float(_values["thirst"]) > 0 and alive():
		_values["health"] = minf(100, float(_values["health"]) + seconds * 0.5)
	if float(_values["hunger"]) == 0 or float(_values["thirst"]) == 0:
		_values["health"] = maxf(0, float(_values["health"]) - seconds * 0.5)
	return true

func consume(inventory: LfeInventory, slot: int) -> bool:
	var stack: Dictionary = inventory.stack_at(slot)
	if stack.is_empty() or not alive():
		return false
	var effects: Dictionary = inventory._catalog.content_definition(StringName(stack["content"])).get("consume", {})
	var changed: bool = false
	var next: Dictionary = snapshot()
	for key: String in effects:
		var value: float = minf(100, float(next[key]) + float(effects[key]))
		changed = changed or value != float(next[key])
		next[key] = value
	if not changed or not LfeItemTransactions.remove(inventory, slot, 1):
		return false
	return restore(next)
