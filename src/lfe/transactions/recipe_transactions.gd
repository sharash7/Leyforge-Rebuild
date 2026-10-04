class_name LfeRecipeTransactions
extends RefCounted

static func consume(inventory: LfeInventory, entries: Array) -> bool:
	var next: LfeInventory = LfeInventory.new(inventory._catalog, inventory.capacity())
	next.restore(inventory.snapshot())
	for entry: Dictionary in entries:
		var id: StringName = StringName(entry["content"])
		var left: int = int(entry["quantity"])
		if next.total(id) < left:
			return false
		for slot: int in next.capacity():
			var stack: Dictionary = next.stack_at(slot)
			if stack.get("content") == String(id):
				var removed: int = mini(left, int(stack["quantity"]))
				LfeItemTransactions.remove(next, slot, removed)
				left -= removed
				if left == 0:
					break
	return inventory.restore(next.snapshot())

static func outputs(inventory: LfeInventory, entries: Array) -> bool:
	var next: LfeInventory = LfeInventory.new(inventory._catalog, inventory.capacity())
	next.restore(inventory.snapshot())
	for entry: Dictionary in entries:
		if LfeItemTransactions.add(next, StringName(entry["content"]), int(entry["quantity"])) != int(entry["quantity"]):
			return false
	return inventory.restore(next.snapshot())

static func craft(inventory: LfeInventory, recipes: LfeRecipeCatalog, id: String) -> bool:
	var recipe: Dictionary = recipes.definition(id)
	if recipe.is_empty() or recipe["context"] != "hand" or recipe.has("grid"):
		return false
	var next: LfeInventory = LfeInventory.new(inventory._catalog, inventory.capacity())
	next.restore(inventory.snapshot())
	if not consume(next, recipe["inputs"]) or not outputs(next, recipe["outputs"]):
		return false
	return inventory.restore(next.snapshot())
