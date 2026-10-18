extends SceneTree
## Worker entry point runs unchanged fixed-path runtime owners in a staged project.
const Publication = preload("res://src/forge_eng/import_export/content_publication.gd")
const References = preload("res://src/forge_eng/references/content_references.gd")

static func diagnostic(code: String, source: String, field: String, message: String, id: String = "") -> Dictionary:
	return {"severity": "error", "code": code, "source": source, "id": id, "field": field, "message": message}

static func copy_tree(source: String, target: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(target) != OK: return false
	for name: String in DirAccess.get_files_at(source):
		if DirAccess.copy_absolute(source.path_join(name), target.path_join(name)) != OK: return false
	for name: String in DirAccess.get_directories_at(source):
		if not copy_tree(source.path_join(name), target.path_join(name)): return false
	return true

static func check(doc: RefCounted) -> Dictionary:
	var diagnostics: Array = []
	var references: Array = []
	if not doc.allowed_diff(): diagnostics.append(diagnostic("allowed_fields", doc.relative_path, "/", "Only solid block display_name/color edits are allowed"))
	for entry: Dictionary in doc.data.get("blocks", []):
		var original: Dictionary = {}
		for base_entry: Dictionary in doc.base.get("blocks", []):
			if base_entry.get("id") == entry.get("id"): original = base_entry
		if original != entry and not original.get("solid", false): diagnostics.append(diagnostic("read_only", doc.relative_path, "/blocks", "Non-solid blocks are read-only", str(entry.get("id"))))
		if not entry.get("display_name") is String or str(entry.get("display_name", "")).strip_edges().is_empty(): diagnostics.append(diagnostic("name", doc.relative_path, "/blocks/display_name", "Name must not be empty", str(entry.get("id"))))
		if original.get("color") != entry.get("color") and (not entry.get("color") is String or not Publication.valid_color(entry.color)):
			diagnostics.append(diagnostic("color", doc.relative_path, "/blocks/color", "Expected #RRGGBBAA", str(entry.get("id"))))
	var stage: String = ProjectSettings.globalize_path("user://forge/validation-project")
	var source: String = ProjectSettings.globalize_path("res://")
	# No owner save state is copied. The worker's res:// points only at this candidate.
	var copied: bool = copy_tree(source.path_join("src"), stage.path_join("src")) and copy_tree(doc.root.path_join("content"), stage.path_join("content"))
	DirAccess.make_dir_recursive_absolute(stage.path_join(".godot"))
	copied = copied and DirAccess.copy_absolute(source.path_join(".godot/global_script_class_cache.cfg"), stage.path_join(".godot/global_script_class_cache.cfg")) == OK
	var config: FileAccess = FileAccess.open(stage.path_join("project.godot"), FileAccess.WRITE)
	if config != null:
		config.store_string('config_version=5\n[application]\nconfig/name="Leyforge Forge Validation"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n'); config.close()
	else: copied = false
	var candidate: FileAccess = FileAccess.open(stage.path_join(doc.relative_path), FileAccess.WRITE)
	if candidate != null: candidate.store_string(Publication.bytes(doc.data)); candidate.close()
	else: copied = false
	if copied:
		var output: Array = []
		var status: int = OS.execute(Publication.RUNNER, ["--headless", "--path", stage, "--script", "res://src/forge_eng/validation/content_validation.gd", "--", stage.path_join("result.json")], output, true)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(stage.path_join("result.json"))) if FileAccess.file_exists(stage.path_join("result.json")) else null
		if status != 0 or not parsed is Dictionary:
			diagnostics.append(diagnostic("worker", doc.relative_path, "/", "Runtime validation worker failed: " + "\n".join(output)))
		else:
			diagnostics.append_array(parsed.diagnostics)
			references = parsed.get("references", [])
	else: diagnostics.append(diagnostic("stage", doc.relative_path, "/", "Could not create disposable validation project"))
	diagnostics.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return JSON.stringify(a) < JSON.stringify(b))
	return {"success": diagnostics.is_empty(), "revision": doc.revision, "diagnostics": diagnostics, "references": references, "stage": stage}

func _initialize() -> void:
	var diagnostics: Array = []
	var references: Array = []
	var paths: Array[String] = ["content/blocks/wave_1_blocks.json", "content/recipes/wave_4_recipes.json", "content/world_objects/wave_3_crate.json", "content/world_objects/wave_4_sources.json"]
	var documents: Dictionary = {}
	for path: String in paths:
		var parsed: Dictionary = Publication.parse_strict(FileAccess.get_file_as_string("res://" + path))
		if not parsed.success or not parsed.get("value") is Dictionary:
			diagnostics.append(diagnostic("json", path, "/", parsed.get("reason", "Expected JSON object"))); continue
		documents[path] = parsed.value
		if parsed.value.get("schema_version") != 1: diagnostics.append(diagnostic("schema", path, "/schema_version", "Unsupported schema version"))
	var catalog: LfeBlockCatalog = LfeBlockCatalog.new()
	if catalog.load_default() != OK: diagnostics.append(diagnostic("runtime_catalog", paths[0], "/", catalog.get_last_error()))
	else:
		var recipes: LfeRecipeCatalog = LfeRecipeCatalog.new()
		if not recipes.load_default(catalog): diagnostics.append(diagnostic("runtime_recipes", paths[1], "/recipes", recipes.error))
		var resources: LfeWorldResourceState = LfeWorldResourceState.new(catalog)
		if resources.storage_definition().is_empty(): diagnostics.append(diagnostic("runtime_crate", paths[2], "/", "Runtime crate loader rejected definition"))
		var creations: LfeCreationState = LfeCreationState.new(catalog)
		if not creations.content_error.is_empty(): diagnostics.append(diagnostic("runtime_sources", paths[3], "/sources", creations.content_error))
		for path: String in paths:
			if not documents.has(path): continue
			for ref: Dictionary in References.collect(documents[path], catalog, path):
				references.append(ref)
				if not ref.resolved: diagnostics.append(diagnostic("reference", ref.source, ref.field, "Unknown canonical reference", ref.id))
	var output: FileAccess = FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	output.store_string(JSON.stringify({"diagnostics": diagnostics, "references": references})); output.close()
	quit()
