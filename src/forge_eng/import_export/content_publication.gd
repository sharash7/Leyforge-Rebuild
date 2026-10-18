extends RefCounted
## Windows owns atomic replacement; a bounded named mutex serializes Forge writers.
const RUNNER = "D:/AI/Projects/leyforge/.local/Godot_v4.8-dev-a9c94-shutdown-fixed/godot.windows.editor.x86_64.console.exe"
const DRAFT = "user://forge/session.json"

static func valid_color(value: String) -> bool:
	var regex: RegEx = RegEx.new()
	regex.compile("^#[0-9a-fA-F]{8}$")
	return regex.search(value) != null

static func parse_strict(text: String) -> Dictionary:
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK: return {"success": false, "reason": "JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()]}
	# Scan strings after syntax validation; decoded keys catch escaped duplicates too.
	var objects: Array = []
	var index: int = 0
	while index < text.length():
		var c: String = text[index]
		if c == "{": objects.append({})
		elif c == "}": objects.pop_back()
		elif c == '"':
			var start: int = index
			index += 1
			while index < text.length():
				if text[index] == "\\": index += 2; continue
				if text[index] == '"': break
				index += 1
			var end: int = index + 1
			while end < text.length() and text[end] in [" ", "\t", "\r", "\n"]: end += 1
			if end < text.length() and text[end] == ":" and not objects.is_empty():
				var key: String = JSON.parse_string(text.substr(start, index - start + 1))
				if objects.back().has(key): return {"success": false, "reason": "Duplicate JSON key: " + key}
				objects.back()[key] = true
		index += 1
	return {"success": true, "value": parser.data}

static func bytes(data: Dictionary) -> String:
	return JSON.stringify(data, "  ", true, true) + "\n"

static func quote(value: String) -> String:
	return "'" + value.replace("'", "''") + "'"

static func windows(script: String) -> Dictionary:
	var output: Array = []
	var encoded: String = Marshalls.raw_to_base64(("$ProgressPreference='SilentlyContinue';\n" + script).to_utf16_buffer())
	var code: int = OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded], output, true)
	return {"success": code == 0, "reason": "\n".join(output).strip_edges()}

static func guard(root: String, relative: String) -> Dictionary:
	if relative != "content/blocks/wave_1_blocks.json" or not root.is_absolute_path():
		return {"success": false, "reason": "Target path escape/unsupported target"}
	return windows("""
$ErrorActionPreference='Stop'
try {
 $p=[IO.Path]::GetFullPath(%s)
 $x=Get-Item -LiteralPath $p -Force
 if($x.Attributes -band [IO.FileAttributes]::ReadOnly){throw 'Read-only target'}
 while($null -ne $x){
  if($x.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Symlink/junction target rejected'}
  $x=if($x -is [IO.DirectoryInfo]){$x.Parent}else{$x.Directory}
 }
} catch {Write-Output $_.Exception.Message;exit 1}
""" % quote(root.path_join(relative)))

static func save_draft(doc: RefCounted) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://forge"))
	var file: FileAccess = FileAccess.open(DRAFT + ".tmp", FileAccess.WRITE)
	if file == null: return doc.result(false, "Cannot write draft; existing draft retained")
	file.store_string(bytes({"version": 1, "root": doc.root, "target": doc.relative_path, "base_hash": doc.base_hash, "payload": doc.data, "commands": doc.history.commands, "cursor": doc.history.cursor}))
	file.flush()
	file.close()
	var moved: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(DRAFT + ".tmp"), ProjectSettings.globalize_path(DRAFT))
	return doc.result(moved == OK, "Draft saved" if moved == OK else "Draft replacement failed; temporary recovery retained")

static func resume_draft(doc: RefCounted) -> Dictionary:
	if not FileAccess.file_exists(DRAFT): return doc.result(true, "No saved draft")
	var parsed: Dictionary = parse_strict(FileAccess.get_file_as_string(DRAFT))
	if not parsed.success: return doc.result(false, parsed.reason)
	var envelope: Variant = parsed.value
	if not envelope is Dictionary or envelope.get("version") != 1 or envelope.get("target") != doc.relative_path or envelope.get("root") != doc.root or not envelope.get("payload") is Dictionary:
		return doc.result(false, "Unsupported draft version/identity; export or explicitly discard")
	if envelope.get("base_hash") != doc.base_hash: return doc.result(false, "Draft base conflict; export or explicitly discard")
	var old: Dictionary = doc.data
	doc.data = envelope.payload.duplicate(true)
	if not doc.allowed_diff():
		doc.data = old
		return doc.result(false, "Draft changes unsupported fields")
	# Replay the saved linear history through the command boundary, including redo.
	var expected: Dictionary = doc.data.duplicate(true)
	var old_history: RefCounted = doc.history
	var old_revision: int = doc.revision
	doc.data = doc.base.duplicate(true)
	doc.history = preload("res://src/forge_eng/history/edit_history.gd").new()
	var valid: bool = envelope.get("commands") is Array and envelope.get("cursor") is float and envelope.cursor == floor(envelope.cursor) and envelope.cursor >= 0 and envelope.cursor <= envelope.commands.size()
	if valid:
		for command: Variant in envelope.commands:
			if not command is Dictionary or not command.has_all(["id", "field", "before", "after"]) or not command.id is String or not command.field is String or doc.definition(command.id).get(command.field) != command.before:
				valid = false; break
			if not doc.apply_edit(command.id, command.field, command.after).success:
				valid = false; break
	if valid:
		while doc.history.cursor > int(envelope.cursor): doc.undo()
		valid = doc.data == expected
	if not valid:
		doc.data = old; doc.history = old_history; doc.revision = old_revision; doc.validation = {}
		return doc.result(false, "Invalid draft history/payload; export or explicitly discard")
	return doc.result(true, "Draft resumed")

static func recover(root: String, relative: String) -> Dictionary:
	var pending: String = root.path_join(relative) + ".forge-pending"
	if not FileAccess.file_exists(pending): return {"success": true, "reason": ""}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://forge/recovery"))
	return windows(_mutex(root.path_join(relative)) + """
try {
 [IO.File]::Copy(%s,%s,$false)
 [IO.File]::Delete(%s)
 Write-Output 'Interrupted publication recovered; original canonical and draft retained. Review draft before publishing.'
} catch {Write-Output $_.Exception.Message;exit 1} finally {$mutex.ReleaseMutex();$mutex.Dispose()}
""" % [quote(pending), quote(ProjectSettings.globalize_path("user://forge/recovery/interrupted-" + str(Time.get_unix_time_from_system()) + ".json")), quote(pending)])

static func _mutex(target: String) -> String:
	return "$ErrorActionPreference='Stop';$mutex=[Threading.Mutex]::new($false,'Local\\LeyforgeForge" + target.to_lower().sha256_text() + "');try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true};if(!$locked){Write-Output 'Another Forge writer is publishing';exit 1}\n"

static func publish(doc: RefCounted, confirmed: bool, fault: String = "") -> Dictionary:
	if not confirmed: return doc.result(false, "Explicit Publish confirmation required")
	if not doc.validation.get("success", false) or doc.validation.get("revision", -1) != doc.revision:
		return doc.result(false, "Current successful validation required")
	if not doc.allowed_diff(): return doc.result(false, "Unsupported field diff")
	if not doc.validate().success: return doc.result(false, "Publication revalidation failed; see diagnostics")
	var guarded: Dictionary = guard(doc.root, doc.relative_path)
	if not guarded.success: return doc.result(false, guarded.reason)
	var target: String = doc.root.path_join(doc.relative_path)
	if FileAccess.get_sha256(target) != doc.base_hash: return doc.result(false, "Canonical base conflict; draft retained")
	if not doc.dirty(): return doc.result(true, "No changes; canonical bytes preserved")
	var saved: Dictionary = save_draft(doc)
	if not saved.success: return saved
	var folder: String = ProjectSettings.globalize_path("user://forge/recovery")
	DirAccess.make_dir_recursive_absolute(folder)
	var candidate: String = folder.path_join("candidate.json")
	var file: FileAccess = FileAccess.open(candidate, FileAccess.WRITE)
	if file == null: return doc.result(false, "Cannot stage publication")
	file.store_string(bytes(doc.data)); file.flush(); file.close()
	var backup: String = folder.path_join("base-" + doc.base_hash + ".json")
	var script: String = _mutex(target) + """
$target=%s;$temp=$target+'.forge-pending';$backup=%s
function Get-ForgeHash($path){$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($path)))).Replace('-','').ToLower()}finally{$sha.Dispose()}}
try {
 if([IO.File]::Exists($temp)){throw 'Interrupted publish needs recovery/reopen'}
 if((Get-ForgeHash $target) -ne %s){throw 'Canonical base conflict'}
 $candidateBytes=[IO.File]::ReadAllBytes(%s)
 $stream=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$stream.Write($candidateBytes,0,$candidateBytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
 if(%s -eq 'crash'){[Environment]::Exit(23)}
 if(%s -eq 'before_replace'){throw 'Injected pre-replace failure'}
 $original=[IO.File]::ReadAllBytes($target)
 $stream=[IO.File]::Open($backup,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$stream.Write($original,0,$original.Length);$stream.Flush($true)}finally{$stream.Dispose()}
 if((Get-ForgeHash $target) -ne %s){throw 'Canonical base conflict immediately before replace'}
 if(%s -eq 'replace'){throw 'Injected replace failure'}
 [IO.File]::Replace($temp,$target,[NullString]::Value)
 Write-Output 'Published atomically; recovery base retained'
} catch {Write-Output $_.Exception.Message;exit 1} finally {
 if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}
 $mutex.ReleaseMutex();$mutex.Dispose()
}
""" % [quote(target), quote(backup), quote(doc.base_hash), quote(candidate), quote(fault), quote(fault), quote(doc.base_hash), quote(fault)]
	var outcome: Dictionary = windows(script)
	print("FORGE_PUBLICATION_RESULT ", outcome)
	if not outcome.success: return doc.result(false, outcome.reason)
	if FileAccess.get_file_as_string(target) != bytes(doc.data): return doc.result(false, "Published bytes could not be verified; inspect recovery")
	doc.base = doc.data.duplicate(true)
	doc.base_hash = FileAccess.get_sha256(target)
	doc.history = preload("res://src/forge_eng/history/edit_history.gd").new()
	doc.revision += 1
	doc.validation = {}
	save_draft(doc)
	return doc.result(true, outcome.reason)
