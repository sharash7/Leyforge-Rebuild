class_name LfeHarvestRules
extends RefCounted

static func tool(resources: LfePlayerResourceState) -> Dictionary:
	var stack: Dictionary = resources.equipment.stack_at(0)
	if stack.is_empty():
		stack = resources.inventory.stack_at(resources.selected_slot())
	return stack

static func evaluate(rule: Dictionary, stack: Dictionary, catalog: LfeBlockCatalog) -> Dictionary:
	if not rule.get("class") is String or not LfeWorldSave._is_integer(rule.get("capability")) or int(rule["capability"]) < 0 or not LfeWorldSave._finite_in_range(rule.get("seconds"), 60) or float(rule["seconds"]) <= 0:
		return {}
	var definition: Dictionary = catalog.content_definition(StringName(stack.get("content", "")))
	var spec: Dictionary = definition.get("tool", {})
	var matching: bool = not spec.is_empty() and spec["class"] == rule["class"] and int(stack.get("durability", 0)) > 0
	var capability: int = int(spec["capability"]) if matching else 0
	if capability < int(rule["capability"]):
		return {}
	return {"seconds": float(rule["seconds"]) / (float(spec["efficiency"]) if matching else 1.0),
		"wear": matching, "instance": stack.get("instance", "")}

static func wear(resources: LfePlayerResourceState, identity: String) -> bool:
	for inventory: LfeInventory in [resources.inventory, resources.equipment]:
		var next: Array = inventory.snapshot()
		for slot: int in next.size():
			if next[slot] != null and next[slot].get("instance") == identity:
				if int(next[slot]["durability"]) <= 0:
					return false
				next[slot]["durability"] -= 1
				return inventory.restore(next)
	return false
