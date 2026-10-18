extends RefCounted
const Source = preload("res://src/lfe/content/voxel_asset.gd")

static func check(doc: RefCounted) -> Dictionary:
	var checked: Dictionary = Source.check(doc.data,doc.relative_path,true)
	if checked.success: checked=Source.resolve(doc.data,doc.root)
	if checked.success:
		var target: String = doc.root.path_join(doc.relative_path)
		var current: String = FileAccess.get_sha256(target) if FileAccess.file_exists(target) else "ABSENT"
		if current!=doc.base_hash: checked=Source.fail("Canonical base conflict; export draft or reopen source")
	checked.revision=doc.revision
	checked.diagnostics=[] if checked.success else [{"severity":"error","code":"VOXEL_ASSET","source":doc.relative_path,"id":doc.data.get("id",""),"field":checked.reason.get_slice(":",0),"message":checked.reason}]
	if checked.success:
		var boxes: int=preload("res://src/lfe/voxel/voxel_asset_compiler.gd").collision_boxes(doc.data).size()
		checked.collision_boxes=boxes
		checked.reason="Validation PASS · %d collision boxes" % boxes
		if boxes>256:
			checked.reason+=" · WARNING: high collision-box cost"
			checked.diagnostics.append({"severity":"warning","code":"COLLISION_BOX_COST","source":doc.relative_path,"id":doc.data.id,"field":"collision","message":"%d boxes exceeds the 256-box advisory; review runtime cost" % boxes})
	return checked
