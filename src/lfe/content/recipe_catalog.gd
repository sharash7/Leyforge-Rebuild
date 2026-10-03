class_name LfeRecipeCatalog
extends RefCounted

var _recipes: Dictionary = {}
var error: String = ""

func load_default(catalog: LfeBlockCatalog) -> bool:
	return load_path("res://content/recipes/wave_4_recipes.json", catalog)

func load_path(path: String, catalog: LfeBlockCatalog) -> bool:
	_recipes.clear()
	var root: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not root is Dictionary or root.get("schema_version") != 1 or not root.get("recipes") is Array:
		return _fail("Invalid recipe file")
	for value: Variant in root["recipes"]:
		if not value is Dictionary or value.size() != 6 or not value.get("id") is String or not String(value["id"]).contains(":") or _recipes.has(value["id"]):
			return _fail("Invalid or duplicate recipe")
		if value.get("context") not in ["hand", "kiln"] or not LfeWorldSave._finite_in_range(value.get("seconds"), 3600) or float(value["seconds"]) < 0:
			return _fail("Invalid recipe context/time")
		if (value["context"] == "hand") != (float(value["seconds"]) == 0):
			return _fail("Timed recipe needs a station")
		for key: String in ["inputs", "outputs", "fuel"]:
			if not value.get(key) is Array or (key != "fuel" and value[key].is_empty()):
				return _fail("Invalid recipe quantities")
			var seen: Dictionary = {}
			for entry: Variant in value[key]:
				if not entry is Dictionary or entry.size() != 2 or not entry.get("content") is String or not LfeWorldSave._is_integer(entry.get("quantity")):
					return _fail("Invalid recipe entry")
				var id: StringName = StringName(entry["content"])
				if not catalog.is_inventory_content(id) or int(entry["quantity"]) < 1 or int(entry["quantity"]) > 64 or seen.has(id):
					return _fail("Unknown/repeated ingredient or quantity")
				if key != "outputs" and LfeItemInstance.is_stateful(id, catalog):
					return _fail("Stateful ingredients require an explicit future rule")
				seen[id] = true
		if value["context"] == "hand" and not value["fuel"].is_empty():
			return _fail("Hand crafting cannot silently ignore fuel")
		_recipes[value["id"]] = value.duplicate(true)
	return true

func definition(id: String) -> Dictionary:
	return (_recipes.get(id, {}) as Dictionary).duplicate(true)

func all() -> Array:
	return _recipes.values().duplicate(true)

func _fail(message: String) -> bool:
	error = message
	_recipes.clear()
	return false
