class_name LfeItemStack
extends RefCounted


static func valid(value: Variant, catalog: LfeBlockCatalog, allow_empty: bool = true) -> bool:
	if value == null:
		return allow_empty
	if not value is Dictionary:
		return false
	if not value.get("content") is String or not LfeWorldSave._is_integer(value.get("quantity")):
		return false
	var id: StringName = StringName(value["content"])
	var quantity: int = int(value["quantity"])
	if not catalog.is_inventory_content(id) or quantity <= 0 or quantity > catalog.stack_limit(id):
		return false
	if LfeItemInstance.is_stateful(id, catalog):
		return value.size() == 4 and quantity == 1 and LfeWorldResourceState._valid_identity(value.get("instance")) and LfeWorldSave._is_integer(value.get("durability")) and int(value["durability"]) >= 0 and int(value["durability"]) <= int(catalog.content_definition(id)["tool"]["durability"])
	return value.size() == 2


static func make(id: StringName, quantity: int) -> Dictionary:
	return {"content": String(id), "quantity": quantity}
