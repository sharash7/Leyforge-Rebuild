extends SceneTree
const Source = preload("res://src/lfe/content/voxel_asset.gd")
const Document = preload("res://src/forge_eng/editing/voxel_asset_document.gd")
const Publication = preload("res://src/forge_eng/import_export/voxel_asset_publication.gd")
const Compiler = preload("res://src/lfe/voxel/voxel_asset_compiler.gd")
const Loader = preload("res://src/lfe/voxel/voxel_asset_loader.gd")
const Picking = preload("res://tools/forge/workspaces/voxel_asset/voxel_picking.gd")
var checks: Array=[]
var report: Dictionary={"passed":false}
var proof: String

func _initialize() -> void:
	proof=OS.get_cmdline_user_args()[0];call_deferred("run")

func check(value: bool, label: String) -> void:
	checks.append({"label":label,"passed":value})
	if not value:push_error("W6_3_CHECK_FAILED "+label)

func write(path: String, text: String) -> void:
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE);file.store_string(text);file.close()

func run() -> void:
	var project: String=ProjectSettings.globalize_path("res://").trim_suffix("/")
	var doc=Document.new();doc.root=project
	check(doc.create("fixture:focused","Fine voxel study").success,"create empty model")
	var empty: Dictionary=doc.data.duplicate(true)
	check(Source.check(empty).success and not Source.check(empty,"",true).success,"empty draft allowed, finished empty rejected")
	check(Source.parse(Source.bytes(empty).to_utf8_buffer()).success,"canonical integer JSON round trip")
	for id: String in ["../escape:x","bad:name/path","con:test","x:lpt1","Upper:name","x:y.","x:y:z"]:check(not Source.valid_id(id),"unsafe identity "+id)
	check(not Source.check(empty,"content/voxel_assets/other/name.voxel.json").success,"ID path agreement")
	for text: String in ['{"a":1,"a":2}','{"a":1,"\\u0061":2}','{"x":1.0}','{"x":true,','{"x":1e0}']:
		check(not Source.parse(text.to_utf8_buffer()).success,"strict JSON negative "+text)
	check(not Source.parse(PackedByteArray([255])).success,"invalid UTF-8 rejected")
	check(not Source.parse(("\uFEFF"+Source.bytes(empty)).to_utf8_buffer()).success,"BOM rejected")
	check(not Source.parse(" ".repeat(Source.MAX_BYTES+1).to_utf8_buffer()).success,"oversized source rejected")
	for field: String in ["schema_version","asset_version","voxels_per_metre"]:
		for bad: Variant in [true,0,1.5,2147483648]:
			var value: Dictionary=empty.duplicate(true);value[field]=bad;check(not Source.check(value).success,"invalid numeric "+field+str(bad))
	for cell: Array in [[-1,0,0,"base"],[16,0,0,"base"],[0,0.5,0,"base"],[true,0,0,"base"],[0,0,0,"missing"],[0,0,0]]:
		var value: Dictionary=empty.duplicate(true);value.cells=[cell];check(not Source.check(value).success,"bad cell "+str(cell))
	var bad: Dictionary=empty.duplicate(true);bad.cells=[[0,0,0,"base"],[0,0,0,"base"]];check(not Source.check(bad).success,"duplicate cells")
	bad=empty.duplicate(true);bad.palette.append(bad.palette[0]);check(not Source.check(bad).success,"duplicate swatches")
	bad=empty.duplicate(true);bad.extra=1;check(not Source.check(bad).success,"unknown field")
	bad=empty.duplicate(true);bad.dimensions=[16,32,16];check(not Source.check(bad).success,"unsupported bounds")
	bad=empty.duplicate(true);bad.cells=[[0.0,0,0,"base"]];check(not Source.check(bad).success,"floating coordinate API values rejected")
	bad=empty.duplicate(true)
	for index: int in 33:bad.palette.append({"key":"swatch_"+str(index),"color":"#112233FF"})
	check(not Source.check(bad).success,"32 swatch upper bound")
	bad=empty.duplicate(true);bad.palette[0].color="#FF000080";check(not Source.check(bad).success,"transparent material rejected")
	bad=empty.duplicate(true);bad.palette=[{"key":"base","block_ref":"leyforge:air"}];check(not Source.resolve(bad,project).success,"non-solid block reference rejected")
	bad.palette[0].block_ref="leyforge:missing";check(not Source.resolve(bad,project).success,"unknown block reference rejected")
	var targets: Array=[[0,0,0],[1,0,0],[1,0,0],[2,0,0],[2,1,0]]
	check(doc.edit_cells(targets,"Place","base").success and doc.data.cells.size()==4 and doc.history.cursor==1,"deduplicated atomic grouped cells")
	var before: Dictionary=doc.data.duplicate(true)
	check(not doc.edit_cells([[3,0,0],[16,0,0]],"Place","base").success and doc.data==before,"invalid batch has no partial commit")
	doc.edit_cells(targets,"Place","base");check(doc.history.cursor==1,"no-op adds no history")
	doc.undo();check(doc.data==empty,"undo entire stroke")
	doc.redo();check(doc.data==before,"redo exact stroke")
	check(doc.edit_palette([{"key":"base","color":"#B9BFC7FF"},{"key":"trim","color":"#D08030FF"},{"key":"stone","block_ref":"leyforge:stone"}]).success,"literal and reference swatches")
	doc.edit_cells([[2,1,0]],"Paint","trim");doc.undo();doc.edit_cells([[0,0,0]],"Paint","stone");check(doc.history.cursor==doc.history.commands.size(),"new edit clears redo branch")
	doc.undo();var snapshot: Dictionary=doc.data.duplicate(true);var cursor: int=doc.history.cursor;var commands: Array=doc.history.commands.duplicate(true)
	check(doc.save_draft().success,"atomic draft save")
	var resumed=Document.new();resumed.root=project
	var resumed_result: Dictionary=Publication.resume_draft(resumed,"fixture:focused")
	check(resumed_result.success and resumed.data==snapshot and resumed.history.cursor==cursor and resumed.history.commands==commands,"draft exact history/payload/redo cursor replay: "+str(resumed_result))
	check(resumed.redo().success,"reopened redo works")
	var path: String=Publication.draft_path(doc.data.id);var good: String=FileAccess.get_file_as_string(path)
	write(path,"{broken");check(not Publication.resume_draft(resumed,"fixture:focused").success and FileAccess.get_file_as_string(path)=="{broken","corrupt draft preserved")
	write(path,good)
	var corrupt: Dictionary=Source.parse(good.to_utf8_buffer()).value;corrupt.base_hash=5;write(path,Source.bytes(corrupt))
	check(not Publication.resume_draft(resumed,"fixture:focused").success,"typed corrupt draft hash rejected without adopting state")
	corrupt=Source.parse(good.to_utf8_buffer()).value;corrupt.commands[0].changes[0].before="tampered";write(path,Source.bytes(corrupt))
	check(not Publication.resume_draft(resumed,"fixture:focused").success,"corrupt history before-state rejected atomically")
	write(path,good)
	check(not Publication.save_draft(doc,"crash").success and FileAccess.get_file_as_string(path)==good,"interrupted write retains last good draft")
	check(FileAccess.file_exists(path+".pending"),"interrupted draft temp retained")
	check(Publication.resume_draft(resumed,"fixture:focused").success and not FileAccess.file_exists(path+".pending"),"interrupted draft exported before last good reopen")
	doc.redo();doc.validate()
	check(not Publication.publish(doc,false).success,"explicit confirmation mandatory")
	var published: Dictionary=Publication.publish(doc,true)
	check(published.success,"safe new-file source publication: "+str(published))
	if not published.success:finish();return
	var target: String=project.path_join(doc.relative_path);var source_bytes: String=FileAccess.get_file_as_string(target);var source_hash: String=FileAccess.get_sha256(target)
	check(not Publication.guard(project,"content/voxel_assets/../escape.voxel.json").success,"bounded publisher rejects traversal")
	check(not Publication.guard(project,"content/blocks/wave_1_blocks.json").success,"voxel publisher cannot write catalogue")
	var readonly: Dictionary=Publication.IO.windows("$p="+Publication.IO.quote(target)+";$x=Get-Item -LiteralPath $p;$x.IsReadOnly=$true")
	check(readonly.success and not Publication.guard(project,doc.relative_path).success,"read-only canonical target rejected")
	Publication.IO.windows("$p="+Publication.IO.quote(target)+";$x=Get-Item -LiteralPath $p;$x.IsReadOnly=$false")
	var case_folder: String=project.path_join("content/voxel_assets/Mixed");DirAccess.make_dir_recursive_absolute(case_folder)
	check(not Publication.guard(project,"content/voxel_assets/mixed/model.voxel.json").success,"case-fold ancestor collision rejected")
	var junction: String=project.path_join("content/voxel_assets/junction")
	var junction_result: Dictionary=Publication.IO.windows("$ErrorActionPreference='Stop';New-Item -ItemType Junction -Path "+Publication.IO.quote(junction)+" -Target "+Publication.IO.quote(project.path_join("tests"))+" | Out-Null")
	check(junction_result.success and not Publication.guard(project,"content/voxel_assets/junction/model.voxel.json").success,"junction ancestor rejected")
	Publication.IO.windows("[IO.Directory]::Delete("+Publication.IO.quote(junction)+",$false)")
	check(Source.parse(source_bytes.to_utf8_buffer()).success and doc.data.asset_version==1,"published source schema/version")
	var exact_read: Dictionary=Source.read_source(project,doc.relative_path)
	check(exact_read.success and exact_read.source_hash==source_bytes.sha256_text(),"source identity hashes exact raw bytes read")
	doc.validate();check(Publication.publish(doc,true).success and FileAccess.get_sha256(target)==source_hash,"no-op preserves source bytes/version")
	doc.rename("Changed study");doc.validate();check(not Publication.publish(doc,true,"crash").success and FileAccess.get_sha256(target)==source_hash,"interrupted publication retains canonical")
	check(Publication.recover(project,doc.relative_path).success and not FileAccess.file_exists(target+".forge-pending"),"recover pending source outside content")
	doc.validate();check(Publication.publish(doc,true).success and doc.data.asset_version==2,"safe replacement increments version once")
	source_hash=FileAccess.get_sha256(target)
	var baked: Dictionary=Publication.bake(doc);check(baked.success,"published source bake: "+str(baked.get("reason")))
	if not baked.success:finish();return
	var repeat_bake: Dictionary=Publication.bake(doc);check(repeat_bake.success and FileAccess.get_file_as_string(baked.path)==Source.bytes(repeat_bake.bundle),"identical bake bytes/key")
	check(Loader.load_bundle(project,doc.relative_path,baked.path).success,"runtime validates published bake")
	var malformed: Dictionary=baked.bundle.duplicate(true);malformed.indices[0]=99999999
	check(not Loader.shape_check(malformed).success,"decoded index range bounded before resources")
	var oversized: Dictionary=baked.bundle.duplicate(true);oversized.collision_boxes.resize(4097)
	check(not Loader.shape_check(oversized).success,"decoded collision count bounded independently")
	oversized=baked.bundle.duplicate(true);oversized.vertices.resize(4096*6*4+1)
	check(not Loader.shape_check(oversized).success,"decoded vertex count bounded independently")
	var malformed_path: String=ProjectSettings.globalize_path("user://malformed.mesh.json");write(malformed_path,Source.bytes(malformed))
	check(not Loader.load_bundle(project,doc.relative_path,malformed_path).success,"malformed geometry rejected before resources")
	malformed=baked.bundle.duplicate(true);malformed.collision_boxes=[];write(malformed_path,Source.bytes(malformed));check(not Loader.load_bundle(project,doc.relative_path,malformed_path).success,"collision omission rejected")
	malformed=baked.bundle.duplicate(true);malformed.artifact_version=99;write(malformed_path,Source.bytes(malformed));check(not Loader.load_bundle(project,doc.relative_path,malformed_path).success,"artifact version rejection")
	var catalog_path: String=project.path_join(Source.CATALOG);var catalog_bytes: String=FileAccess.get_file_as_string(catalog_path)
	write(catalog_path,catalog_bytes+"\n");check(not Loader.load_bundle(project,doc.relative_path,baked.path).success,"stale dependency rejection");write(catalog_path,catalog_bytes)
	var reopened=Document.new();reopened.root=project;check(Publication.resume_draft(reopened,"fixture:focused").success,"post-publication full history replay")
	write(target,FileAccess.get_file_as_string(target)+"\n");check(not Publication.resume_draft(reopened,"fixture:focused").success and reopened.draft_problem,"external canonical draft conflict")
	check(not Loader.load_bundle(project,doc.relative_path,baked.path).success,"stale raw source hash rejection")
	check(not Publication.publish(doc,true).success,"external source blocks publication")
	write(target,Source.bytes(doc.data))
	# Six exposed faces and inside/parallel/boundary rays against integer occupancy.
	var occupied: Dictionary={"8,8,8":"base"}
	for axis: int in 3:
		for sign_value: int in [-1,1]:
			var origin: Vector3=Vector3(8.5,8.5,8.5)/16;origin[axis]=2 if sign_value<0 else -1
			var direction: Vector3=Vector3.ZERO;direction[axis]=sign_value
			var hit: Dictionary=Picking.ray(origin,direction,occupied)
			check(hit.hit and hit.cell==[8,8,8] and hit.normal[axis]==-sign_value,"six-face DDA %d/%d" % [axis,sign_value])
	check(Picking.ray(Vector3(8.5,8.5,8.5)/16,Vector3.RIGHT,occupied).hit,"inside-origin picking")
	check(not Picking.ray(Vector3(-1,2,0),Vector3.RIGHT,occupied).hit,"parallel ray outside slab")
	check(Picking.ray(Vector3(1,0.53125,0.53125),Vector3.LEFT,occupied).hit,"outer max boundary ray")
	var tie: Dictionary=Picking.ray(Vector3(-1,-1,-1),Vector3.ONE.normalized(),{"0,0,0":"base"});check(tie.hit and tie.normal==[-1,0,0],"corner entry X tie rule")
	check(Picking.plane(Vector3(0.2,2,0.2),Vector3.DOWN,1,0).cell==[3,0,3],"empty construction plane")
	check(not Picking.plane(Vector3(1.1,2,0.2),Vector3.DOWN,1,0).valid,"outside plane invalid, no clamp")
	check(Picking.segment([0,0,0],[15,0,0]).size()==16,"fast stroke fills intervening cells")
	check(Picking.box([0,0,0],[15,15,15]).size()==4096,"bounded full box")
	# Mesh counts, winding, scale and collision union on several shapes.
	var model: Dictionary=empty.duplicate(true);model.cells=[[0,0,0,"base"]]
	var one: Dictionary=Compiler.compile(model,Source.resolve(model,project),"fixture").bundle
	check(one.vertices.size()==24 and one.indices.size()==36 and one.collision_boxes==[{"min":[0,0,0],"size":[1,1,1]}],"one cell: six flat faces/exact collision")
	model.cells.append([1,0,0,"base"])
	var two: Dictionary=Compiler.compile(model,Source.resolve(model,project),"fixture").bundle
	model.cells.reverse();var shuffled: Dictionary=Compiler.compile(model,Source.resolve(model,project),"fixture").bundle
	check(Source.bytes(two)==Source.bytes(shuffled),"cell enumeration does not change deterministic bundle")
	check(two.vertices.size()==40 and two.indices.size()==60,"adjacent cells suppress both interior faces")
	for offset: int in range(0,two.indices.size(),3):
		var a: Array=two.vertices[two.indices[offset]];var b: Array=two.vertices[two.indices[offset+1]];var c: Array=two.vertices[two.indices[offset+2]];var n: Array=two.normals[two.indices[offset]]
		check((Vector3(b[0],b[1],b[2])-Vector3(a[0],a[1],a[2])).cross(Vector3(c[0],c[1],c[2])-Vector3(a[0],a[1],a[2])).dot(Vector3(n[0],n[1],n[2]))<0,"clockwise outward triangle %d" % offset)
	var checker: Dictionary=empty.duplicate(true)
	for x: int in 16:
		for y: int in 16:
			for z: int in 16:
				if (x+y+z)%2==0:checker.cells.append([x,y,z,"base"])
	var started: int=Time.get_ticks_usec();var worst: Dictionary=Compiler.compile(checker,Source.resolve(checker,project),"fixture").bundle
	report.checker_compile_ms=float(Time.get_ticks_usec()-started)/1000;report.checker_boxes=worst.collision_boxes.size()
	check(worst.collision_boxes.size()==2048,"checkerboard collision cost: 2048 disjoint boxes")
	started=Time.get_ticks_usec();var worst_body: StaticBody3D=Loader.body(worst);root.add_child(worst_body)
	report.checker_native_body_creation_ms=float(Time.get_ticks_usec()-started)/1000
	check(worst_body.get_child_count()==2048,"worst-case native shape construction measured")
	worst_body.free()
	var dense: Dictionary=empty.duplicate(true)
	for x: int in 16:
		for y: int in 16:
			for z: int in 16:dense.cells.append([x,y,z,"base"])
	started=Time.get_ticks_usec();var dense_bundle: Dictionary=Compiler.compile(dense,Source.resolve(dense,project),"fixture").bundle
	report.dense_compile_ms=float(Time.get_ticks_usec()-started)/1000
	check(dense_bundle.collision_boxes==[{"min":[0,0,0],"size":[16,16,16]}] and dense_bundle.vertices.size()==6*16*16*4,"full 4096 cell volume compiles to exact exterior and one box")
	var union: Dictionary={}
	for box: Dictionary in baked.bundle.collision_boxes:
		for x: int in int(box.size[0]):
			for y: int in int(box.size[1]):
				for z: int in int(box.size[2]):
					var key: String=Source.key([box.min[0]+x,box.min[1]+y,box.min[2]+z]);check(not union.has(key),"collision boxes disjoint");union[key]=true
	check(union.size()==doc.data.cells.size() and Source.occupancy(doc.data).keys().all(func(key: String) -> bool:return union.has(key)),"collision union exactly occupancy including empty notch")
	report.runtime_source=doc.relative_path;report.runtime_root=project;report.runtime_bundle=baked.path;report.runtime_hash=FileAccess.get_sha256(baked.path)
	finish()

func finish() -> void:
	report.checks=checks;report.passed=checks.all(func(item: Dictionary) -> bool:return item.passed)
	write(proof,JSON.stringify(report,"  "));print("W6_3_FOCUSED ",report.passed," checks=",checks.size());quit(0 if report.passed else 1)
