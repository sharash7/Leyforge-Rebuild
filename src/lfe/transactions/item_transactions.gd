class_name LfeItemTransactions
extends RefCounted

# Operations prepare detached snapshots and publish only after every check.
# No UI receives a mutable authoritative slot array, and no signals run mid-commit.
static func add(destination: LfeInventory, id: StringName, quantity: int, partial: bool = false) -> int:
	if quantity <= 0 or quantity > 1000000 or not destination._catalog.is_inventory_content(id):
		return 0
	var next: Array = destination.snapshot()
	var left: int = quantity
	for empty_pass: bool in [false, true]:
		for slot: int in next.size():
			if not destination.accepts(slot, id):
				continue
			var stack: Variant = next[slot]
			if (stack == null) != empty_pass:
				continue
			if stack != null and StringName(stack["content"]) != id:
				continue
			var current: int = 0 if stack == null else int(stack["quantity"])
			var accepted: int = mini(left, destination._catalog.stack_limit(id) - current)
			if accepted > 0:
				next[slot] = LfeItemInstance.create(id, destination._catalog) if LfeItemInstance.is_stateful(id, destination._catalog) else LfeItemStack.make(id, current + accepted)
				left -= accepted
			if left == 0:
				break
		if left == 0:
			break
	if left == quantity or (left > 0 and not partial) or not destination.validate(next):
		return 0
	destination.restore(next)
	return quantity - left


static func remove(source: LfeInventory, slot: int, quantity: int) -> bool:
	var stack: Dictionary = source.stack_at(slot)
	if quantity <= 0 or stack.is_empty() or quantity > int(stack["quantity"]):
		return false
	var next: Array = source.snapshot()
	var remaining: int = int(stack["quantity"]) - quantity
	next[slot] = null if remaining == 0 else LfeItemStack.make(StringName(stack["content"]), remaining)
	return source.restore(next)


# A target slot merges/moves/splits. -1 fills available slots. Partial transfers
# are explicit; a full transfer otherwise either succeeds entirely or changes nothing.
static func transfer(source: LfeInventory, from_slot: int, destination: LfeInventory,
		quantity: int, to_slot: int = -1, partial: bool = false) -> int:
	if source._catalog != destination._catalog:
		return 0
	var stack: Dictionary = source.stack_at(from_slot)
	if quantity <= 0 or stack.is_empty() or quantity > int(stack["quantity"]):
		return 0
	if source == destination and (to_slot < 0 or to_slot == from_slot):
		return 0
	var id: StringName = StringName(stack["content"])
	if LfeItemInstance.is_stateful(id, source._catalog):
		return _transfer_instance(source, from_slot, destination, stack, to_slot)
	var working: LfeInventory = LfeInventory.new(destination._catalog, destination.capacity(), destination._restrictions)
	working.restore(destination.snapshot())
	var accepted: int = 0
	if to_slot == -1:
		accepted = add(working, id, quantity, partial)
	elif destination.accepts(to_slot, id):
		var target: Dictionary = working.stack_at(to_slot)
		if target.is_empty() or target["content"] == stack["content"]:
			var current: int = int(target.get("quantity", 0))
			accepted = mini(quantity, source._catalog.stack_limit(id) - current)
			if accepted < quantity and not partial:
				return 0
			var next: Array = working.snapshot()
			next[to_slot] = LfeItemStack.make(id, current + accepted)
			if not working.restore(next):
				return 0
	if accepted <= 0:
		return 0
	var source_next: Array = source.snapshot() if source != destination else working.snapshot()
	var remainder: int = int(stack["quantity"]) - accepted
	source_next[from_slot] = null if remainder == 0 else LfeItemStack.make(id, remainder)
	if not source.validate(source_next) or not destination.validate(working.snapshot()):
		return 0
	if source != destination:
		destination.restore(working.snapshot())
	source.restore(source_next)
	return accepted


static func swap(a: LfeInventory, a_slot: int, b: LfeInventory, b_slot: int) -> bool:
	if a._catalog != b._catalog or a_slot < 0 or b_slot < 0 or a_slot >= a.capacity() or b_slot >= b.capacity():
		return false
	if a == b and a_slot == b_slot:
		return false
	var next_a: Array = a.snapshot()
	var next_b: Array = b.snapshot() if a != b else next_a
	var first: Variant = next_a[a_slot]
	next_a[a_slot] = next_b[b_slot]
	next_b[b_slot] = first
	if not a.validate(next_a) or not b.validate(next_b):
		return false
	a.restore(next_a)
	if a != b:
		b.restore(next_b)
	return true


static func _transfer_instance(source: LfeInventory, from_slot: int, destination: LfeInventory, stack: Dictionary, to_slot: int) -> int:
	var next: Array = destination.snapshot()
	if to_slot == -1:
		for slot: int in destination.capacity():
			if next[slot] == null and destination.accepts(slot, StringName(stack["content"])):
				to_slot = slot
				break
	if not destination.accepts(to_slot, StringName(stack["content"])) or next[to_slot] != null:
		return 0
	next[to_slot] = stack.duplicate(true)
	var source_next: Array = source.snapshot() if source != destination else next
	source_next[from_slot] = null
	if not source.validate(source_next) or not destination.validate(next):
		return 0
	if source != destination:
		destination.restore(next)
	source.restore(source_next)
	return 1
