extends RefCounted
const Source = preload("res://src/lfe/content/voxel_asset.gd")
const History = preload("res://src/forge_eng/history/edit_history.gd")
const Publication = preload("res://src/forge_eng/import_export/voxel_asset_publication.gd")
var root: String = ""
var relative_path: String = ""
var base_hash: String = "ABSENT"
var base: Dictionary = {}
var initial: Dictionary = {}
var data: Dictionary = {}
var history = History.new()
var revision: int = 0
var validation: Dictionary = {}
var draft_problem: bool = false

func result(success: bool, reason: String = "") -> Dictionary:
	return {"success":success,"reason":reason,"revision":revision}

func create(id: String, display_name: String) -> Dictionary:
	var value: Dictionary = {"schema_version":1,"id":id,"asset_version":1,"display_name":display_name,"dimensions":[16,16,16],"voxels_per_metre":16,"origin":[0,0,0],"palette":[{"key":"base","color":"#B9BFC7FF"}],"cells":[],"collision":"occupied_boxes"}
	var checked: Dictionary = Source.check(value)
	if not checked.success: return checked
	if root.is_empty():
		root = OS.get_environment("LEYFORGE_FORGE_ROOT")
		if root.is_empty(): root = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var path: String = Source.path_for(id)
	if FileAccess.file_exists(root.path_join(path)): return result(false,"Asset exists; use Open source")
	data=checked.value; initial=data.duplicate(true); base={}; base_hash="ABSENT"; relative_path=path; history=History.new(); revision=0; validation={}; draft_problem=false
	return result(true,"New empty 16³ asset")

func open(id: String) -> Dictionary:
	if not Source.valid_id(id): return result(false,"Invalid asset ID")
	if root.is_empty():
		root=OS.get_environment("LEYFORGE_FORGE_ROOT")
		if root.is_empty(): root=ProjectSettings.globalize_path("res://").trim_suffix("/")
	var path: String = Source.path_for(id)
	var recovered: Dictionary = Publication.recover(root,path)
	if not recovered.success: return recovered
	var loaded: Dictionary = Source.read_source(root,path)
	if not loaded.success: return loaded
	data=loaded.data; base=data.duplicate(true); initial=data.duplicate(true); base_hash=loaded.source_hash; relative_path=path; history=History.new(); revision=0; validation={}; draft_problem=false
	return result(true,"Opened source. " + recovered.reason)

func dirty() -> bool:
	return data != base

func touch() -> void:
	revision+=1; validation={}

func command(value: Dictionary) -> Dictionary:
	if draft_problem: return result(false,"Resolve/export conflicted draft before editing")
	var applied: Dictionary = apply_command(value,true)
	if not applied.success: return applied
	if applied.get("noop",false): return result(true,"No change")
	history.push(value); touch()
	return result(true)

func apply_command(value: Dictionary, forward: bool) -> Dictionary:
	var candidate: Dictionary = data.duplicate(true)
	var from: String = "before" if forward else "after"; var to: String = "after" if forward else "before"
	match value.get("kind"):
		"cells":
			if value.size()!=3 or not value.get("changes") is Array or value.changes.size()>4096 or not value.get("label") is String: return result(false,"Invalid cell command")
			var map: Dictionary = Source.occupancy(candidate); var seen: Dictionary = {}; var previous: Array = []
			for change: Variant in value.changes:
				if not change is Dictionary or change.size()!=3 or not change.get("cell") is Array or change.cell.size()!=3 or not Source.inside(change.cell) or not change.has_all(["before","after"]): return result(false,"Invalid cell change")
				var key: String = Source.key(change.cell)
				if seen.has(key) or (not previous.is_empty() and not Source.less(previous,change.cell)): return result(false,"Cell changes must be unique and sorted")
				previous=change.cell; seen[key]=true
				if map.get(key,"")!=change[from] or change.before==change.after: return result(false,"Cell command before/after mismatch")
				if not change[to] is String: return result(false,"Invalid swatch value")
				if change[to]=="": map.erase(key)
				else: map[key]=change[to]
			candidate.cells=[]
			for key: String in map:
				var parts: PackedStringArray = key.split(","); candidate.cells.append([int(parts[0]),int(parts[1]),int(parts[2]),map[key]])
		"palette", "display_name":
			var field: String = value.kind
			if value.size()!=4 or not value.has_all(["label","before","after"]) or not value.label is String or candidate[field]!=value[from]: return result(false,"Invalid field command")
			candidate[field]=value[to]
		_: return result(false,"Unsupported history command")
	var checked: Dictionary = Source.check(candidate,relative_path)
	if not checked.success: return checked
	var noop: bool = data==checked.value
	data=checked.value
	return {"success":true,"reason":"","noop":noop}

func edit_cells(targets: Array, tool: String, swatch: String) -> Dictionary:
	if tool not in ["Place","Remove","Paint"]: return result(false,"Choose a cell editing tool")
	var map: Dictionary = Source.occupancy(data); var unique: Dictionary = {}; var ordered: Array = []; var changes: Array = []
	if targets.size()>4096: return result(false,"Operation exceeds 4096 cells")
	for cell: Variant in targets:
		if not cell is Array or cell.size()!=3 or not Source.inside(cell): return result(false,"Out-of-bounds operation rejected atomically")
		var key: String = Source.key(cell)
		if not unique.has(key): unique[key]=true; ordered.append(cell.duplicate())
	ordered.sort_custom(Source.less)
	for cell: Array in ordered:
		var before: String = map.get(Source.key(cell),""); var after: String = before
		if tool=="Place" and before=="": after=swatch
		elif tool=="Remove": after=""
		elif tool=="Paint" and before!="": after=swatch
		if before!=after: changes.append({"cell":cell,"before":before,"after":after})
	if changes.is_empty(): return result(true,"No change")
	return command({"kind":"cells","label":"%s %d cells" % [tool,changes.size()],"changes":changes})

func edit_palette(palette: Array) -> Dictionary:
	return command({"kind":"palette","label":"Palette","before":data.palette.duplicate(true),"after":palette.duplicate(true)})

func rename(display_name: String) -> Dictionary:
	return command({"kind":"display_name","label":"Display name","before":data.display_name,"after":display_name})

func undo() -> Dictionary:
	if draft_problem or history.cursor==0: return result(false,"Nothing to undo / draft conflict")
	var value: Dictionary = history.commands[history.cursor-1]
	var applied: Dictionary = apply_command(value,false)
	if applied.success: history.cursor-=1; touch()
	return applied

func redo() -> Dictionary:
	if draft_problem or history.cursor>=history.commands.size(): return result(false,"Nothing to redo / draft conflict")
	var applied: Dictionary = apply_command(history.commands[history.cursor],true)
	if applied.success: history.cursor+=1; touch()
	return applied

func validate() -> Dictionary:
	validation=preload("res://src/forge_eng/validation/voxel_asset_validation.gd").check(self)
	return validation

func save_draft() -> Dictionary:
	return Publication.save_draft(self)
