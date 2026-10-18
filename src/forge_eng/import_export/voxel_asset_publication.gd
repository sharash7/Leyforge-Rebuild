extends RefCounted
## Voxel-only target guard. Catalogue publication permissions are unchanged.
const Source = preload("res://src/lfe/content/voxel_asset.gd")
const Compiler = preload("res://src/lfe/voxel/voxel_asset_compiler.gd")
const Loader = preload("res://src/lfe/voxel/voxel_asset_loader.gd")
const IO = preload("res://src/forge_eng/import_export/content_publication.gd")
const Document = "res://src/forge_eng/editing/voxel_asset_document.gd"
const DRAFT_ROOT = "user://forge/voxel_assets"

static func draft_path(id: String) -> String:
	return DRAFT_ROOT.path_join(id.replace(":","/"))+".draft.json" if Source.valid_id(id) else ""

static func hash_at(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "ABSENT"

static func guard_script() -> String:
	return """
function Assert-SafePath([string]$p){
 $full=[IO.Path]::GetFullPath($p)
 if($full.StartsWith('\\\\') -or $full.Substring(2).Contains(':')){throw 'Unsafe Windows path'}
 $current=[IO.Path]::GetPathRoot($full)
 foreach($part in $full.Substring($current.Length).Split('\\')){
  if(!$part){continue}
  if([IO.Directory]::Exists($current)){
   $found=@(Get-ChildItem -LiteralPath $current -Force | Where-Object {$_.Name -ieq $part})
   if($found.Count -gt 1 -or ($found.Count -eq 1 -and $found[0].Name -cne $part)){throw 'Case-fold path collision'}
  }
  $current=[IO.Path]::Combine($current,$part)
  if(Test-Path -LiteralPath $current){
   $item=Get-Item -LiteralPath $current -Force
   if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse-point ancestor rejected'}
   if($item.Attributes -band [IO.FileAttributes]::ReadOnly){throw 'Read-only path rejected'}
  }
 }
}
function Hash-File([string]$p){
 if(![IO.File]::Exists($p)){return 'ABSENT'}
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($p)))).Replace('-','').ToLower()}finally{$sha.Dispose()}
}
function Flush-File([string]$p,[byte[]]$bytes){
 $stream=[IO.File]::Open($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
"""

static func target_valid(root: String, relative: String) -> bool:
	if not root.is_absolute_path() or root.begins_with("user://") or not relative.begins_with("content/voxel_assets/") or not relative.ends_with(".voxel.json"): return false
	var id: String = relative.trim_prefix("content/voxel_assets/").trim_suffix(".voxel.json").replace("/",":")
	return Source.valid_id(id) and Source.path_for(id)==relative

static func guard(root: String, relative: String) -> Dictionary:
	if not target_valid(root,relative): return Source.fail("Unsafe voxel source path")
	return IO.windows("$ErrorActionPreference='Stop'\n"+guard_script()+"\ntry{Assert-SafePath "+IO.quote(root.path_join(relative).replace("/","\\"))+"}catch{Write-Output $_.Exception.Message;exit 1}")

static func atomic_profile(path: String, text: String, fault: String = "") -> Dictionary:
	var target: String = ProjectSettings.globalize_path(path)
	var parent: String = target.get_base_dir(); DirAccess.make_dir_recursive_absolute(parent)
	var stage: String = target+".stage-"+str(OS.get_process_id())
	var file: FileAccess = FileAccess.open(stage,FileAccess.WRITE)
	if file==null: return Source.fail("Cannot stage profile output")
	file.store_string(text); file.flush(); file.close()
	var script: String = IO._mutex(target)+guard_script()+"""
try{
 $target=%s;$temp=$target+'.pending';$backup=$target+'.bak'
 Assert-SafePath $target;Assert-SafePath $temp;Assert-SafePath $backup
 if([IO.File]::Exists($temp)){throw 'Interrupted write retained at .pending; export or explicitly recover'}
 Flush-File $temp ([IO.File]::ReadAllBytes(%s))
 if(%s -eq 'crash'){[Environment]::Exit(23)}
 if(%s -eq 'replace'){throw 'Injected profile replace failure'}
 if([IO.File]::Exists($target)){
  if([IO.File]::Exists($backup)){[IO.File]::Delete($backup)}
  [IO.File]::Replace($temp,$target,$backup)
 }else{[IO.File]::Move($temp,$target)}
}catch{Write-Output $_.Exception.Message;exit 1}finally{$mutex.ReleaseMutex();$mutex.Dispose()}
""" % [IO.quote(target),IO.quote(stage),IO.quote(fault),IO.quote(fault)]
	var written: Dictionary = IO.windows(script)
	DirAccess.remove_absolute(stage)
	if written.success and FileAccess.get_file_as_string(target)!=text: return Source.fail("Output verification failed")
	return written

static func save_draft(doc: RefCounted, fault: String = "") -> Dictionary:
	if doc.draft_problem or doc.data.is_empty(): return Source.fail("Draft conflict/empty document; export before saving")
	var checked: Dictionary = Source.check(doc.data,doc.relative_path)
	if not checked.success: return checked
	var resolved: Dictionary = Source.resolve(doc.data,doc.root)
	# Invalid references are preserved for recovery; successful dependency hashes pin reopening.
	var envelope: Dictionary = {"draft_version":1,"root":doc.root,"target":doc.relative_path,"base_hash":doc.base_hash,"base":doc.base,"initial":doc.initial,"payload":doc.data,"revision":doc.revision,"commands":doc.history.commands,"cursor":doc.history.cursor,"dependencies":resolved.get("dependencies",{})}
	var text: String = Source.bytes(envelope)
	if text.to_utf8_buffer().size()>67108864: return Source.fail("Draft history exceeds 64 MiB; previous draft retained")
	return atomic_profile(draft_path(doc.data.id),text,fault)

static func resume_draft(doc: RefCounted, id: String, backup: bool = false) -> Dictionary:
	if not Source.valid_id(id): return Source.fail("Invalid asset ID")
	var recovery: Dictionary=recover_draft(id)
	if not recovery.success:return recovery
	var path: String = draft_path(id)+(".bak" if backup else "")
	var file: FileAccess = FileAccess.open(path,FileAccess.READ)
	if file==null:return Source.fail("Draft missing; original retained")
	var length: int=file.get_length()
	if length>67108864: return Source.fail("Draft oversized; original retained")
	var raw: PackedByteArray=file.get_buffer(length);file.close()
	var parsed: Dictionary = Source.parse(raw,67108864)
	if not parsed.success: return parsed
	var e: Variant = parsed.value
	if not e is Dictionary or e.size()!=11 or not e.has_all(["draft_version","root","target","base_hash","base","initial","payload","revision","commands","cursor","dependencies"]) or e.draft_version!=1 or e.root!=doc.root or e.target!=Source.path_for(id) or not e.commands is Array or e.commands.size()>65536 or not Source.integer(e.cursor) or e.cursor<0 or e.cursor>e.commands.size() or not Source.integer(e.revision) or e.revision<0 or not e.dependencies is Dictionary: return Source.fail("Unsupported/corrupt draft envelope; original retained")
	if not e.base_hash is String or (e.base_hash!="ABSENT" and not Source.matches("^[0-9a-f]{64}$",e.base_hash)) or e.revision<e.commands.size():return Source.fail("Invalid draft base hash/revision; original retained")
	var source_recovery: Dictionary=recover(doc.root,e.target)
	if not source_recovery.success:return source_recovery
	var candidate: RefCounted = load(Document).new(); candidate.root=doc.root; candidate.relative_path=e.target
	var checked: Dictionary = Source.check(e.initial,e.target)
	if not checked.success: return checked
	candidate.data=checked.value; candidate.initial=candidate.data.duplicate(true)
	for command: Variant in e.commands:
		if not command is Dictionary: return Source.fail("Corrupt draft history")
		var applied: Dictionary = candidate.command(command)
		if not applied.success: return Source.fail("Draft replay: "+applied.reason)
	while candidate.history.cursor>int(e.cursor):
		if not candidate.undo().success: return Source.fail("Draft undo cursor invalid")
	if candidate.data!=e.payload: return Source.fail("Draft replay/payload mismatch")
	if not e.base is Dictionary or (e.base_hash!="ABSENT" and not Source.check(e.base,e.target,true).success): return Source.fail("Invalid canonical base")
	if e.base_hash=="ABSENT" and not e.base.is_empty(): return Source.fail("Absent target requires empty base")
	if candidate.data.asset_version!=(1 if e.base.is_empty() else e.base.asset_version):return Source.fail("Draft version differs from canonical base")
	var conflict: bool = hash_at(doc.root.path_join(e.target))!=e.base_hash
	if not conflict and e.base_hash!="ABSENT":
		var actual: Dictionary=Source.read_source(doc.root,e.target)
		if not actual.success or actual.data!=e.base:return Source.fail("Draft canonical base payload mismatch; original retained")
	for dep: String in e.dependencies:
		if dep!=Source.CATALOG or hash_at(doc.root.path_join(dep))!=e.dependencies[dep]: conflict=true
	doc.data=candidate.data; doc.initial=candidate.initial; doc.base=e.base; doc.base_hash=e.base_hash; doc.relative_path=e.target; doc.history=candidate.history; doc.revision=int(e.revision); doc.validation={}; doc.draft_problem=conflict
	return Source.fail("Draft source/dependency conflict; recovered read-only, export or explicitly discard") if conflict else {"success":true,"reason":"Draft and full history restored"}

static func recover_draft(id: String) -> Dictionary:
	var target: String=ProjectSettings.globalize_path(draft_path(id));var pending: String=target+".pending"
	if not FileAccess.file_exists(pending):return {"success":true,"reason":""}
	var folder: String=ProjectSettings.globalize_path(DRAFT_ROOT.path_join("exports"));DirAccess.make_dir_recursive_absolute(folder)
	return IO.windows(IO._mutex(target)+guard_script()+"""
try{Assert-SafePath %s;[IO.File]::Copy(%s,%s,$false);[IO.File]::Delete(%s);Write-Output 'Interrupted draft exported; last good draft retained'}catch{Write-Output $_.Exception.Message;exit 1}finally{$mutex.ReleaseMutex();$mutex.Dispose()}
""" % [IO.quote(pending),IO.quote(pending),IO.quote(folder.path_join("interrupted-draft-"+str(Time.get_ticks_usec())+".json")),IO.quote(pending)])

static func recover(root: String, relative: String) -> Dictionary:
	var guarded: Dictionary = guard(root,relative)
	if not guarded.success: return guarded
	var pending: String = root.path_join(relative)+".forge-pending"
	if not FileAccess.file_exists(pending): return {"success":true,"reason":""}
	var folder: String = ProjectSettings.globalize_path(DRAFT_ROOT.path_join("recovery")); DirAccess.make_dir_recursive_absolute(folder)
	return IO.windows(IO._mutex(root.path_join(relative))+guard_script()+"""
try{Assert-SafePath %s;[IO.File]::Copy(%s,%s,$false);[IO.File]::Delete(%s);Write-Output 'Interrupted candidate exported; canonical retained'}catch{Write-Output $_.Exception.Message;exit 1}finally{$mutex.ReleaseMutex();$mutex.Dispose()}
""" % [IO.quote(pending),IO.quote(pending),IO.quote(folder.path_join("interrupted-"+str(Time.get_ticks_usec())+".json")),IO.quote(pending)])

static func publish(doc: RefCounted, confirmed: bool, fault: String = "") -> Dictionary:
	if not confirmed: return Source.fail("Explicit creator confirmation required")
	if doc.draft_problem or not doc.validation.get("success",false) or doc.validation.get("revision",-1)!=doc.revision: return Source.fail("Current successful validation required")
	var prior: Dictionary = doc.validation.get("dependencies",{}).duplicate()
	var checked: Dictionary = doc.validate()
	if not checked.success or checked.get("dependencies",{})!=prior: return Source.fail("Source/dependencies changed; validate and review again")
	var guarded: Dictionary = guard(doc.root,doc.relative_path)
	if not guarded.success: return guarded
	if not doc.dirty(): return {"success":true,"reason":"No changes; bytes/version preserved"}
	var saved: Dictionary = save_draft(doc)
	if not saved.success: return saved
	var next: Dictionary = doc.data.duplicate(true); next.asset_version=1 if doc.base.is_empty() else int(doc.base.asset_version)+1
	var next_checked: Dictionary=Source.check(next,doc.relative_path,true)
	if not next_checked.success:return next_checked
	var text: String = Source.bytes(Source.canonical(next)); var target: String = doc.root.path_join(doc.relative_path)
	var recovery: String = ProjectSettings.globalize_path(DRAFT_ROOT.path_join("recovery")); DirAccess.make_dir_recursive_absolute(recovery)
	var candidate: String = recovery.path_join("candidate-"+str(OS.get_process_id())+".json")
	var file: FileAccess = FileAccess.open(candidate,FileAccess.WRITE)
	if file==null: return Source.fail("Cannot stage source")
	file.store_string(text);file.flush();file.close()
	var dependency_checks: String = ""
	for dependency: String in prior:
		dependency_checks+="if((Hash-File "+IO.quote(doc.root.path_join(dependency))+") -ne "+IO.quote(prior[dependency])+"){throw 'Dependency conflict'}\n"
	var script: String = IO._mutex(target)+guard_script()+"""
try{
 $target=%s;$temp=$target+'.forge-pending';$backup=%s
 Assert-SafePath $target;Assert-SafePath $temp;Assert-SafePath $backup
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))|Out-Null
 if([IO.File]::Exists($temp)){throw 'Recover interrupted publication first'}
 if((Hash-File $target) -ne %s){throw 'Canonical base conflict'}
 %s
 Flush-File $temp ([IO.File]::ReadAllBytes(%s))
 if(%s -eq 'crash'){[Environment]::Exit(23)}
 if(%s -eq 'before_replace'){throw 'Injected replacement failure'}
 if((Hash-File $target) -ne %s){throw 'Observed concurrent source change'}
 %s
 Assert-SafePath $target
 if([IO.File]::Exists($target)){
  if([IO.File]::Exists($backup)){[IO.File]::Delete($backup)}
  [IO.File]::Replace($temp,$target,$backup)
 }else{[IO.File]::Move($temp,$target)}
 Write-Output 'Source published; bake separately'
}catch{Write-Output $_.Exception.Message;exit 1}finally{$mutex.ReleaseMutex();$mutex.Dispose()}
""" % [IO.quote(target),IO.quote(recovery.path_join("base-"+doc.base_hash+".json")),IO.quote(doc.base_hash),dependency_checks,IO.quote(candidate),IO.quote(fault),IO.quote(fault),IO.quote(doc.base_hash),dependency_checks]
	var written: Dictionary = IO.windows(script)
	if not written.success: return written
	if FileAccess.get_file_as_string(target)!=text: return Source.fail("Cannot confirm published bytes; inspect recovery")
	# Publication is not undo. Advance version in every history baseline for exact replay.
	doc.data.asset_version=next.asset_version;doc.initial.asset_version=next.asset_version
	doc.base=doc.data.duplicate(true);doc.base_hash=text.sha256_text();doc.touch()
	var persisted: Dictionary = save_draft(doc)
	if not persisted.success: return Source.fail("Source published, draft update failed: "+persisted.reason)
	return written

static func bake(doc: RefCounted) -> Dictionary:
	if doc.draft_problem or doc.dirty(): return Source.fail("Publish current draft before baking")
	var source: Dictionary = Source.read_source(doc.root,doc.relative_path)
	if not source.success: return source
	if source.source_hash!=doc.base_hash: return Source.fail("Stale source; reopen before bake")
	var compiled: Dictionary = Compiler.compile(source.data,source,source.source_hash)
	if not compiled.success: return compiled
	var path: String = DRAFT_ROOT.path_join("bakes/"+compiled.bundle.bake_key+".mesh.json")
	var text: String = Source.bytes(compiled.bundle)
	if hash_at(doc.root.path_join(doc.relative_path))!=source.source_hash: return Source.fail("Source changed during bake")
	for dependency: String in source.dependencies:
		if hash_at(doc.root.path_join(dependency))!=source.dependencies[dependency]: return Source.fail("Dependency changed during bake")
	var written: Dictionary = atomic_profile(path,text)
	if not written.success: return written
	var loaded: Dictionary = Loader.load_bundle(doc.root,doc.relative_path,path)
	if not loaded.success: return loaded
	return {"success":true,"reason":"Baked published source: "+ProjectSettings.globalize_path(path),"path":ProjectSettings.globalize_path(path),"bundle":compiled.bundle}

static func export_bake(doc: RefCounted, path: String, directory: String) -> Dictionary:
	if doc.dirty() or path.is_empty() or not directory.is_absolute_path():return Source.fail("A current published bake and external directory are required")
	var full: String=directory.replace("\\","/").simplify_path().trim_suffix("/")
	var forbidden: Array=[doc.root.path_join("content"),ProjectSettings.globalize_path("user://")]
	for variable: String in ["APPDATA","LOCALAPPDATA"]:
		if not OS.get_environment(variable).is_empty():forbidden.append(OS.get_environment(variable))
	for prefix: String in forbidden:
		var normalized: String=prefix.replace("\\","/").simplify_path().trim_suffix("/")
		if full.to_lower()==normalized.to_lower() or full.to_lower().begins_with(normalized.to_lower()+"/"):return Source.fail("Export must be outside canonical content, Forge drafts and owner profiles")
	var loaded: Dictionary=Loader.load_bundle(doc.root,doc.relative_path,path)
	if not loaded.success:return loaded
	var target: String=full.path_join(loaded.bundle.bake_key+".mesh.json")
	var text: String=Source.bytes(loaded.bundle)
	var guarded: Dictionary=IO.windows("$ErrorActionPreference='Stop'\n"+guard_script()+"\ntry{Assert-SafePath "+IO.quote(target)+"}catch{Write-Output $_.Exception.Message;exit 1}")
	if not guarded.success:return guarded
	if FileAccess.file_exists(target):
		return {"success":FileAccess.get_sha256(target)==text.sha256_text(),"reason":"Export already exists; bytes preserved: "+target}
	var copied: Dictionary=atomic_profile(target,text)
	if copied.success:copied.reason="Exported validated runtime bundle: "+target
	return copied
