class_name LfeWorkstation
extends RefCounted

var input: LfeInventory
var fuel: LfeInventory
var output: LfeInventory
var _active: String = ""
var _progress: float = 0.0
var _recipes: LfeRecipeCatalog
var _catalog: LfeBlockCatalog

func _init(catalog: LfeBlockCatalog, recipes: LfeRecipeCatalog) -> void:
	_catalog = catalog
	_recipes = recipes
	input = LfeInventory.new(catalog, 3)
	fuel = LfeInventory.new(catalog, 1)
	output = LfeInventory.new(catalog, 3)

func snapshot() -> Dictionary:
	return {"input":input.snapshot(), "fuel":fuel.snapshot(), "output":output.snapshot(), "active":_active, "progress":_progress}

func restore(data: Variant) -> bool:
	if not data is Dictionary or data.size() != 5 or not data.get("active") is String or not LfeWorldSave._finite_in_range(data.get("progress"), 3600) or float(data["progress"]) < 0:
		return false
	var recipe: Dictionary = _recipes.definition(data["active"])
	if data["active"] == "":
		if float(data["progress"]) != 0:
			return false
	elif recipe.is_empty() or recipe["context"] != "kiln" or float(data["progress"]) > float(recipe["seconds"]):
		return false
	var a: LfeInventory = LfeInventory.new(_catalog, 3)
	var b: LfeInventory = LfeInventory.new(_catalog, 1)
	var c: LfeInventory = LfeInventory.new(_catalog, 3)
	if not a.restore(data.get("input")) or not b.restore(data.get("fuel")) or not c.restore(data.get("output")):
		return false
	if not LfeWorldResourceState.unique_instances(a.snapshot() + b.snapshot() + c.snapshot()):
		return false
	input.restore(a.snapshot()); fuel.restore(b.snapshot()); output.restore(c.snapshot())
	_active = data["active"]
	_progress = float(data["progress"])
	return true

func start(id: String) -> bool:
	var recipe: Dictionary = _recipes.definition(id)
	if not _active.is_empty() or recipe.is_empty() or recipe["context"] != "kiln":
		return false
	var a: LfeInventory = LfeInventory.new(_catalog, 3)
	var b: LfeInventory = LfeInventory.new(_catalog, 1)
	var c: LfeInventory = LfeInventory.new(_catalog, 3)
	a.restore(input.snapshot()); b.restore(fuel.snapshot()); c.restore(output.snapshot())
	if not LfeRecipeTransactions.consume(a, recipe["inputs"]) or not LfeRecipeTransactions.consume(b, recipe["fuel"]) or not LfeRecipeTransactions.outputs(c, recipe["outputs"]):
		return false
	# Inputs and fuel become the explicit active-process reservation. Outputs are
	# published only at completion; no offline wall-clock production is awarded.
	input.restore(a.snapshot()); fuel.restore(b.snapshot())
	_active = id
	_progress = 0.0
	return true

func advance(seconds: float) -> bool:
	if not LfeWorldSave._finite_in_range(seconds, 60) or seconds < 0:
		return false
	if _active.is_empty():
		return true
	var recipe: Dictionary = _recipes.definition(_active)
	_progress = minf(float(recipe["seconds"]), _progress + seconds)
	if _progress == float(recipe["seconds"]) and LfeRecipeTransactions.outputs(output, recipe["outputs"]):
		_active = ""
		_progress = 0.0
	return true

func status() -> String:
	if _active.is_empty():
		return "Idle"
	var seconds: float = float(_recipes.definition(_active)["seconds"])
	return "Output blocked" if _progress == seconds else "Processing %.1f / %.1f s" % [_progress, seconds]

func empty() -> bool:
	return _active.is_empty() and (input.snapshot() + fuel.snapshot() + output.snapshot()).all(func(v: Variant) -> bool: return v == null)


func start_reason(id: String) -> String:
	var recipe: Dictionary = _recipes.definition(id)
	if not _active.is_empty():
		return "Output blocked — clear output slots" if _progress==float(_recipes.definition(_active)["seconds"]) else "Running — inputs and fuel reserved"
	if recipe.is_empty() or recipe["context"]!="kiln":
		return "Unknown process"
	var a: LfeInventory = LfeInventory.new(_catalog,3)
	var b: LfeInventory = LfeInventory.new(_catalog,1)
	var c: LfeInventory = LfeInventory.new(_catalog,3)
	a.restore(input.snapshot());b.restore(fuel.snapshot());c.restore(output.snapshot())
	if not LfeRecipeTransactions.consume(a,recipe["inputs"]):
		return "Input missing: " + _requirements(recipe["inputs"])
	if not LfeRecipeTransactions.consume(b,recipe["fuel"]):
		return "Fuel missing: " + _requirements(recipe["fuel"])
	if not LfeRecipeTransactions.outputs(c,recipe["outputs"]):
		return "Output full — clear output slots"
	return "Ready — %.1f simulation seconds" % float(recipe["seconds"])


func _requirements(entries: Array) -> String:
	var parts: PackedStringArray = []
	for entry: Dictionary in entries:
		parts.append("%d %s" % [int(entry["quantity"]),_catalog.content_definition(StringName(entry["content"]))["display_name"]])
	return ", ".join(parts)
