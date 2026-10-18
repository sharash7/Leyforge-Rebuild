extends RefCounted
const History = preload("res://src/forge_eng/history/edit_history.gd")
const Publication = preload("res://src/forge_eng/import_export/content_publication.gd")
const Validation = preload("res://src/forge_eng/validation/content_validation.gd")
const TARGET = "content/blocks/wave_1_blocks.json"
var root: String = ""
var relative_path: String = TARGET
var base_hash: String = ""
var base: Dictionary = {}
var data: Dictionary = {}
var revision: int = 0
var history = History.new()
var validation: Dictionary = {}
var error: String = ""

func open(path: String = TARGET) -> Dictionary:
	if path != TARGET: return result(false, "Only the canonical block catalog is supported")
	if root.is_empty():
		root = OS.get_environment("LEYFORGE_FORGE_ROOT")
		if root.is_empty(): root = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var guard: Dictionary = Publication.guard(root, path)
	if not guard.success: return result(false, guard.reason)
	var recovered: Dictionary = Publication.recover(root, path)
	if not recovered.success: return result(false, recovered.reason)
	var parsed: Dictionary = Publication.parse_strict(FileAccess.get_file_as_string(root.path_join(path)))
	if not parsed.success: return result(false, parsed.reason)
	if not parsed.value is Dictionary or parsed.value.get("schema_version") != 1 or not parsed.value.get("blocks") is Array:
		return result(false, "Unsupported catalog schema/shape")
	var catalog: LfeBlockCatalog = LfeBlockCatalog.new()
	if catalog.load_from_path(root.path_join(path)) != OK: return result(false, catalog.get_last_error())
	base_hash = FileAccess.get_sha256(root.path_join(path))
	base = parsed.value.duplicate(true)
	data = base.duplicate(true)
	history = History.new()
	revision += 1
	validation = {}
	return result(true, recovered.reason)

func result(success: bool, reason: String = "") -> Dictionary:
	error = reason if not success else ""
	return {"success": success, "reason": reason, "revision": revision}

func definition(id: String) -> Dictionary:
	for entry: Dictionary in data.get("blocks", []) + data.get("items", []):
		if entry.get("id") == id: return entry.duplicate(true)
	return {}

func apply_edit(id: String, field: String, value: Variant) -> Dictionary:
	var before: Dictionary = definition(id)
	if before.is_empty() or not before.get("solid", false) or before.get("kind") != "block":
		return result(false, "Read-only or unknown block: " + id)
	if field not in ["display_name", "color"] or not value is String:
		return result(false, "Unsupported field/type: " + field)
	if field == "display_name" and value.strip_edges().is_empty(): return result(false, "display_name: name must not be empty")
	if field == "color" and not Publication.valid_color(value): return result(false, "color: expected #RRGGBBAA")
	if before.get(field) == value: return result(true, "No change")
	history.push({"id": id, "field": field, "before": before.get(field), "after": value})
	_set_field(id, field, value)
	return result(true)

func _set_field(id: String, field: String, value: Variant) -> void:
	for entry: Dictionary in data.blocks:
		if entry.id == id: entry[field] = value
	revision += 1
	validation = {}

func undo() -> Dictionary:
	var command: Dictionary = history.undo()
	if command.is_empty(): return result(false, "Nothing to undo")
	_set_field(command.id, command.field, command.before)
	return result(true)

func redo() -> Dictionary:
	var command: Dictionary = history.redo()
	if command.is_empty(): return result(false, "Nothing to redo")
	_set_field(command.id, command.field, command.after)
	return result(true)

func dirty() -> bool:
	return data != base

func diff() -> Array:
	var changes: Array = []
	for index: int in data.get("blocks", []).size():
		var entry: Dictionary = data.blocks[index]
		for field: String in ["display_name", "color"]:
			if entry.get(field) != base.blocks[index].get(field):
				changes.append({"id": entry.id, "field": field, "before": base.blocks[index].get(field), "after": entry.get(field)})
	return changes

func allowed_diff() -> bool:
	var restored: Dictionary = data.duplicate(true)
	if not restored.get("blocks") is Array or restored.blocks.size() != base.get("blocks", []).size(): return false
	for index: int in restored.blocks.size():
		if not restored.blocks[index] is Dictionary: return false
		for field: String in ["display_name", "color"]:
			if base.blocks[index].has(field): restored.blocks[index][field] = base.blocks[index][field]
	return restored == base

func validate() -> Dictionary:
	validation = Validation.check(self)
	return validation

func save_draft() -> Dictionary:
	return Publication.save_draft(self)

func resume_draft() -> Dictionary:
	return Publication.resume_draft(self)

func publish(confirmed: bool = false, fault: String = "") -> Dictionary:
	return Publication.publish(self, confirmed, fault)
