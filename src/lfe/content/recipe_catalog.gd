class_name LfeRecipeCatalog
extends RefCounted

var _recipes: Dictionary = {}
var error: String = ""

func load_default(catalog: LfeBlockCatalog) -> bool:
	return load_path("res://content/recipes/wave_4_recipes.json", catalog)

func load_path(path: String, catalog: LfeBlockCatalog) -> bool:
	_recipes.clear()
	error = ""
	var root: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not root is Dictionary or root.get("schema_version") != 1 or not root.get("recipes") is Array:
		return _fail("Invalid recipe file")
	for value: Variant in root["recipes"]:
		if not value is Dictionary or value.size() != (7 if value.has("grid") else 6) or not value.get("id") is String or not String(value["id"]).contains(":") or _recipes.has(value["id"]):
			return _fail("Invalid or duplicate recipe")
		if value.get("context") not in ["hand", "workbench", "kiln"] or not LfeWorldSave._finite_in_range(value.get("seconds"), 3600) or float(value["seconds"]) < 0:
			return _fail("Invalid recipe context/time")
		if (value["context"] != "kiln") != (float(value["seconds"]) == 0):
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
		if value["context"] != "kiln" and not value["fuel"].is_empty():
			return _fail("Hand crafting cannot silently ignore fuel")
		if value.has("grid") and not _valid_grid(value):
			return _fail("Invalid crafting pattern/context or pattern quantities")
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

# Grid metadata extends recipe schema 1; old six-field recipes remain readable.
func _valid_grid(recipe: Dictionary) -> bool:
	var grid: Variant = recipe["grid"]
	if not grid is Dictionary or grid.get("type") not in ["shaped","shapeless"] or not LfeWorldSave._is_integer(grid.get("size")) or int(grid["size"]) not in [2,3]:
		return false
	if recipe["context"] != ("hand" if int(grid["size"])==2 else "workbench"):
		return false
	if grid["type"]=="shapeless":
		return grid.size()==2 and recipe["inputs"].size()<=int(grid["size"])*int(grid["size"])
	if grid.size()!=5 or not grid.get("pattern") is Array or not grid.get("keys") is Dictionary or not grid.get("mirror") is bool:
		return false
	var pattern: Array = grid["pattern"]
	if pattern.is_empty() or pattern.size()>int(grid["size"]) or not pattern[0] is String:
		return false
	var width: int = pattern[0].length()
	if width<1 or width>int(grid["size"]):return false
	var counts: Dictionary = {}
	var used: Dictionary = {}
	for row: Variant in pattern:
		if not row is String or row.length()!=width:return false
		for symbol: String in row:
			if symbol==" ":continue
			if not grid["keys"].has(symbol) or not grid["keys"][symbol] is String:return false
			used[symbol]=true
			var id: String = grid["keys"][symbol]
			counts[id]=int(counts.get(id,0))+1
	if used.size()!=grid["keys"].size() or counts.size()!=recipe["inputs"].size():return false
	for entry: Dictionary in recipe["inputs"]:
		if int(counts.get(entry["content"],0))!=int(entry["quantity"]):return false
	# A trimmed pattern has no empty border; translation is handled by matching.
	if String(pattern[0]).strip_edges().is_empty() or String(pattern[-1]).strip_edges().is_empty():return false
	return true

func match_grid(inventory: LfeInventory, size: int, context: String) -> Dictionary:
	if size not in [2,3] or inventory.capacity()!=size*size or context not in ["hand","workbench"] or (context=="hand" and size!=2) or (context=="workbench" and size!=3):
		return {}
	for recipe: Dictionary in _recipes.values():
		if not recipe.has("grid") or recipe["context"]=="kiln" or int(recipe["grid"]["size"])>size or (recipe["context"]=="workbench" and context!="workbench"):
			continue
		var consumption: Array = _shapeless(inventory,recipe) if recipe["grid"]["type"]=="shapeless" else _shaped(inventory,size,recipe)
		if not consumption.is_empty():return {"recipe":recipe["id"],"consumption":consumption,"outputs":recipe["outputs"].duplicate(true)}
	return {}

func _shapeless(inventory: LfeInventory, recipe: Dictionary) -> Array:
	var required: Dictionary = {}
	for entry: Dictionary in recipe["inputs"]:required[entry["content"]]=int(entry["quantity"])
	for slot: int in inventory.capacity():
		var stack: Dictionary = inventory.stack_at(slot)
		if not stack.is_empty() and (stack.has("instance") or not required.has(stack["content"])):return []
	var consumption: Array = []
	for id: String in required:
		var left: int = required[id]
		var slots: Array[int] = []
		for slot: int in inventory.capacity():
			if inventory.stack_at(slot).get("content","")==id:slots.append(slot)
		if slots.size()>left:return [] # Every occupied slot participates in this craft.
		for index: int in slots.size():
			var slot: int = slots[index]
			var count: int = mini(int(inventory.stack_at(slot)["quantity"]),left-(slots.size()-index-1))
			if count>0:consumption.append({"slot":slot,"quantity":count});left-=count
		if left>0:return []
	return consumption

func _shaped(inventory: LfeInventory, size: int, recipe: Dictionary) -> Array:
	var grid: Dictionary = recipe["grid"]
	var pattern: Array = grid["pattern"]
	var width: int = String(pattern[0]).length()
	for mirrored: bool in [false,true] if grid["mirror"] else [false]:
		for oy: int in range(size-pattern.size()+1):
			for ox: int in range(size-width+1):
				var consumption: Array = []
				var valid: bool = true
				for slot: int in size*size:
					var x: int = slot%size-ox;var y: int = slot/size-oy
					var symbol: String = " "
					if x>=0 and x<width and y>=0 and y<pattern.size():symbol=String(pattern[y])[width-1-x if mirrored else x]
					var stack: Dictionary = inventory.stack_at(slot)
					if symbol==" ":
						valid=valid and stack.is_empty()
					else:
						valid=valid and stack.get("content","")==grid["keys"][symbol] and not stack.has("instance")
						consumption.append({"slot":slot,"quantity":1})
				if valid:return consumption
	return []
