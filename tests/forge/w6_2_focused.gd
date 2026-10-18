extends SceneTree
const Document = preload("res://src/forge_eng/editing/content_document.gd")
const Publication = preload("res://src/forge_eng/import_export/content_publication.gd")
var checks: Array = []
var failures: Array = []
var output: String

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks.append({"label": label, "passed": condition})
	if not condition: failures.append(label); print("W62_FAIL ", label)

func write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE); file.store_string(text); file.close()

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	# The gate supplies an isolated project. Refuse this test in a Git checkout.
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		push_error("Focused publication test requires disposable project"); quit(2); return
	var doc = Document.new()
	check(doc.open().success, "open canonical through strict parser and Windows guard")
	var target: String = doc.root.path_join(doc.relative_path)
	var original: String = FileAccess.get_file_as_string(target)
	var original_hash: String = FileAccess.get_sha256(target)
	var stone: Dictionary = doc.definition("leyforge:stone")
	check(doc.apply_edit("leyforge:stone", "display_name", "Forge stone").success, "name command")
	check(doc.apply_edit("leyforge:stone", "color", "#AA6633FF").success, "colour command one")
	check(doc.apply_edit("leyforge:stone", "color", "#2277BBFF").success, "colour command two")
	var saved: Dictionary = doc.data.duplicate(true)
	check(doc.undo().success and doc.definition("leyforge:stone").color == "#AA6633FF", "undo exact colour")
	check(doc.redo().success and doc.data == saved, "redo exact whole document")
	doc.undo(); doc.apply_edit("leyforge:stone", "display_name", "Branch stone")
	check(not doc.redo().success, "new command clears redo")
	for entry: Array in [["leyforge:stone", "id", "bad"], ["leyforge:stone", "voxel_id", 90], ["unknown:id", "color", "#FFFFFFFF"], ["leyforge:air", "display_name", "Air 2"], ["leyforge:stone", "display_name", "  "], ["leyforge:stone", "color", "#123456"], ["leyforge:stone", "color", 42]]:
		var before: Dictionary = doc.data.duplicate(true); var revision: int = doc.revision
		check(not doc.apply_edit(entry[0], entry[1], entry[2]).success and doc.data == before and doc.revision == revision, "atomic rejected command " + str(entry))
	check(not Publication.parse_strict('{"x":1,"x":2}').success, "duplicate root keys")
	check(not Publication.parse_strict('{"n":{"a":1,"\\u0061":2}}').success, "duplicate nested escaped keys")
	check(not Publication.parse_strict('{').success, "malformed JSON")
	check(Publication.parse_strict('{"a":[{"x":1},{"x":2}],"b":"}\\\""}').success, "strict scanner handles repeated keys in separate objects and escapes")
	check(doc.save_draft().success and not ProjectSettings.globalize_path(Publication.DRAFT).begins_with(doc.root.path_join("content")), "versioned draft outside canonical content")
	var resumed = Document.new(); resumed.open()
	check(resumed.resume_draft().success and resumed.data == doc.data, "draft restart restores commands and data")
	check(resumed.undo().success, "resumed edit history usable")
	var v: Dictionary = doc.validate()
	check(v.success and v.revision == doc.revision, "staged unchanged runtime catalog recipe crate source loaders")
	check(not doc.publish(false).success, "explicit confirmation mandatory")
	doc.apply_edit("leyforge:stone", "display_name", "Final stone")
	check(not doc.publish(true).success, "stale validation rejected")
	doc.validate()
	for fault: String in ["before_replace", "replace", "crash"]:
		check(not doc.publish(true, fault).success and FileAccess.get_sha256(target) == original_hash, "Windows failure preserves original: " + fault)
		check(FileAccess.file_exists(Publication.DRAFT), "failure preserves draft: " + fault)
		if fault == "crash":
			check(FileAccess.file_exists(target + ".forge-pending"), "pre-replace crash leaves recoverable pending candidate")
			var restart = Document.new()
			check(restart.open().success and not FileAccess.file_exists(target + ".forge-pending") and restart.resume_draft().success, "restart archives pending candidate and retains original/draft")
		check(not FileAccess.file_exists(target + ".forge-pending"), "temp cleanup: " + fault)
	write(target, original + "\n")
	check(not doc.publish(true).success and FileAccess.get_file_as_string(target) == original + "\n", "external base conflict never overwrites")
	write(target, original)
	var conflict = Document.new(); conflict.open(); conflict.base_hash = "mismatch"
	check(not conflict.resume_draft().success, "draft base conflict")
	check(not doc.open("../escape.json").success, "target escape blocked")
	check(Publication.guard(doc.root, doc.relative_path).success, "safe Windows target")
	var read_only: Dictionary = Publication.windows("$p=" + Publication.quote(target) + ";[IO.File]::SetAttributes($p,[IO.File]::GetAttributes($p) -bor [IO.FileAttributes]::ReadOnly)")
	check(read_only.success and not Publication.guard(doc.root, doc.relative_path).success and not doc.publish(true).success, "Windows read-only target rejected")
	Publication.windows("$p=" + Publication.quote(target) + ";[IO.File]::SetAttributes($p,[IO.FileAttributes]::Normal)")
	var junction: String = ProjectSettings.globalize_path("user://forge/junction-root")
	var linked: Dictionary = Publication.windows("$ErrorActionPreference='Stop';New-Item -ItemType Junction -Path " + Publication.quote(junction) + " -Target " + Publication.quote(doc.root) + " | Out-Null")
	check(linked.success and not Publication.guard(junction, doc.relative_path).success, "Windows junction escape rejected")
	var marker: String = ProjectSettings.globalize_path("user://forge/writer-lock")
	var lock_script: String = Publication._mutex(target) + "[IO.File]::WriteAllText(" + Publication.quote(marker) + ",'locked');try{[Threading.Thread]::Sleep(6000)}finally{$mutex.ReleaseMutex();$mutex.Dispose()}"
	var lock_pid: int = OS.create_process("powershell.exe", ["-NoProfile", "-NonInteractive", "-EncodedCommand", Marshalls.raw_to_base64(lock_script.to_utf16_buffer())])
	for attempt: int in 50:
		if FileAccess.file_exists(marker): break
		OS.delay_msec(100)
	check(lock_pid > 0 and FileAccess.file_exists(marker) and not doc.publish(true).success and FileAccess.get_sha256(target) == original_hash, "bounded lock rejects concurrent Forge writer")
	while OS.is_process_running(lock_pid): OS.delay_msec(100)
	var draft_text: String = FileAccess.get_file_as_string(Publication.DRAFT)
	write(Publication.DRAFT, '{"version":999}')
	var unknown_draft = Document.new(); unknown_draft.open()
	check(not unknown_draft.resume_draft().success and not unknown_draft.dirty(), "unknown draft version rejected without edits")
	write(Publication.DRAFT, draft_text)
	var tampered: Dictionary = doc.data.duplicate(true); doc.data.blocks[3].voxel_id = 99
	check(not doc.allowed_diff() and not doc.validate().success, "immutable mappings and unsupported diff blocked")
	doc.data = tampered; doc.validation = {}; doc.validate()
	check(doc.publish(true).success, "Windows atomic publication")
	var published: String = FileAccess.get_file_as_string(target)
	check(published == Publication.bytes(tampered), "deterministic UTF-8 LF sorted-key serialization")
	var runtime: LfeBlockCatalog = LfeBlockCatalog.new()
	check(runtime.load_from_path(target) == OK and runtime.definition_for_id(&"leyforge:stone").display_name == "Final stone" and runtime.definition_for_id(&"leyforge:stone").color == "#AA6633FF", "fresh runtime consumes published name/colour")
	check(doc.validate().success and doc.publish(true).success and FileAccess.get_file_as_string(target) == published, "no-op publish preserves exact bytes")
	check(FileAccess.file_exists("user://forge/recovery/base-" + original_hash + ".json"), "out-of-content recoverable base retained")
	check(not FileAccess.file_exists(target + ".forge-pending"), "successful replace removes fingerprint-visible temporary file")
	write(target, original)
	var repeat = Document.new(); repeat.open(); repeat.apply_edit("leyforge:stone", "display_name", "Final stone"); repeat.apply_edit("leyforge:stone", "color", "#AA6633FF"); repeat.validate()
	check(repeat.publish(true).success and FileAccess.get_file_as_string(target) == published, "same base and commands produce identical bytes")
	write(target, original)
	# Domain failures use the existing runtime loaders and stable diagnostic shape.
	for mode: String in ["duplicate_id", "unknown_reference", "schema"]:
		var invalid = Document.new(); invalid.open()
		if mode == "duplicate_id": invalid.data.blocks[3].id = invalid.data.blocks[2].id
		if mode == "unknown_reference": invalid.data.blocks[3].drop_content = "leyforge:missing"
		if mode == "schema": invalid.data.schema_version = 99
		var first: Dictionary = invalid.validate(); var second: Dictionary = invalid.validate()
		check(not first.success and first.diagnostics == second.diagnostics, "ordered deterministic diagnostics: " + mode)
		check(first.diagnostics[0].has_all(["severity", "code", "source", "id", "field", "message"]), "diagnostic interface: " + mode)
	write(target, original)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Publication.DRAFT))
	var report: Dictionary = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "original_sha256": original_hash, "final_sha256": FileAccess.get_sha256(target), "stone": stone}
	write(output, JSON.stringify(report, "  "))
	print("W62_FOCUSED ", checks.size(), " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
