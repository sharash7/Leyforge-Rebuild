class_name LfeSurvivalReplica
extends RefCounted

# Session presentation only. No consume/damage/advance/restore authority methods.
var _state: Dictionary = {}
var received_at: float = -1.0

func ready() -> bool:
	return not _state.is_empty()

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func receive(p: Dictionary, now: float) -> bool:
	if not LfeSurvivalProtocol.valid(p) or p["kind"] == "survival_resync" or int(p["revision"]) <= int(_state.get("revision",0)): return false
	if _state.is_empty() and p["kind"] != "survival_state": return false
	_state = p.duplicate(true)
	received_at = now
	return true

func can_sprint() -> bool:
	return ready() and _state["alive"] and float(_state["stamina"]) >= 1 and float(_state["fatigue"]) < 100

func clear() -> void:
	_state.clear(); received_at = -1.0
