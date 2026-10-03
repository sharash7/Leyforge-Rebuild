class_name LfeItemStack
extends RefCounted


static func valid(value: Variant, catalog: LfeBlockCatalog, allow_empty: bool = true) -> bool:
	if value == null:
		return allow_empty
	if not value is Dictionary or value.size() != 2:
		return false
	if not value.get("content") is String or not LfeWorldSave._is_integer(value.get("quantity")):
		return false
	var id: StringName = StringName(value["content"])
	var quantity: int = int(value["quantity"])
	return catalog.is_inventory_content(id) and quantity > 0 and quantity <= catalog.stack_limit(id)


static func make(id: StringName, quantity: int) -> Dictionary:
	return {"content": String(id), "quantity": quantity}
