class_name LfeItemInstance
extends RefCounted

static func create(id: StringName, catalog: LfeBlockCatalog) -> Dictionary:
	return {"content": String(id), "quantity": 1,
		"instance": Crypto.new().generate_random_bytes(16).hex_encode(),
		"durability": int(catalog.content_definition(id)["tool"]["durability"])}

static func is_stateful(id: StringName, catalog: LfeBlockCatalog) -> bool:
	return catalog.content_definition(id).has("tool")
