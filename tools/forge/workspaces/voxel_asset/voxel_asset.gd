extends VBoxContainer
## Creator controls over the shared document/compiler and W6.2 viewport.
const Document = preload("res://src/forge_eng/editing/voxel_asset_document.gd")
const Source = preload("res://src/lfe/content/voxel_asset.gd")
const Compiler = preload("res://src/lfe/voxel/voxel_asset_compiler.gd")
const Publication = preload("res://src/forge_eng/import_export/voxel_asset_publication.gd")
const Picking = preload("res://tools/forge/workspaces/voxel_asset/voxel_picking.gd")
var document = Document.new()
var preview: VBoxContainer
var id_edit: LineEdit
var name_edit: LineEdit
var palette_list: OptionButton
var swatch_key: LineEdit
var color_picker: ColorPickerButton
var block_ref: LineEdit
var reference_mode: CheckBox
var status: Label
var coordinates: Label
var technical: RichTextLabel
var sidebar: ScrollContainer
var tool: String = "Place"
var swatch: String = "base"
var plane_axis: int = 1
var plane_index: int = 0
var selection: Dictionary = {}
var box_anchor: Array = []
var box_end: Array = []
var box_mode: CheckBox
var pending: Dictionary = {}
var last_cell: Array = []
var stroke: bool = false
var stroke_tool: String
var stroke_swatch: String
var stroke_pointer: Vector2
var hover: Dictionary = {}
var overlay: MeshInstance3D
var ghost: MeshInstance3D
var confirmation: ConfirmationDialog
var review: RichTextLabel
var discard: ConfirmationDialog
var last_result: Dictionary = {"success":true,"reason":"Create or open an asset"}
var bake_path: String = ""
var populated: bool = false
var export_dialog: FileDialog

func button(parent: Control, text: String, action: Callable) -> Button:
	var value: Button=Button.new();value.text=text;parent.add_child(value);value.pressed.connect(action);return value

func field(parent: Control, label_text: String, placeholder: String) -> LineEdit:
	var label: Label=Label.new();label.text=label_text;parent.add_child(label)
	var value: LineEdit=LineEdit.new();value.placeholder_text=placeholder;parent.add_child(value);return value

func _ready() -> void:
	document.root=OS.get_environment("LEYFORGE_FORGE_ROOT")
	if document.root.is_empty(): document.root=ProjectSettings.globalize_path("res://").trim_suffix("/")
	var actions: HFlowContainer=HFlowContainer.new();add_child(actions)
	button(actions,"New",func() -> void: _load("new"))
	button(actions,"Open source",func() -> void: _load("source"))
	button(actions,"Reopen draft",func() -> void: _load("draft"))
	button(actions,"Voxel Undo",func() -> void: cancel();_changed(document.undo()))
	button(actions,"Voxel Redo",func() -> void: cancel();_changed(document.redo()))
	button(actions,"Save voxel draft",func() -> void: cancel();_result(document.save_draft()))
	button(actions,"Validate",func() -> void: cancel();_result(document.validate());_details())
	button(actions,"Review / Publish…",_review)
	button(actions,"Bake",func() -> void:
		cancel();var baked: Dictionary=Publication.bake(document);_result(baked)
		if baked.success: bake_path=baked.path)
	button(actions,"Runtime test",_runtime)
	button(actions,"Export bake…",func() -> void:cancel();export_dialog.popup_centered_ratio(0.7))
	button(actions,"Inspector",func() -> void: sidebar.visible=not sidebar.visible)
	var tools: HFlowContainer=HFlowContainer.new();add_child(tools)
	for label: String in ["Select","Place","Remove","Paint"]:
		button(tools,label,func() -> void: cancel();tool=label;_feedback())
	box_mode=CheckBox.new();box_mode.text="Box anchors";tools.add_child(box_mode);box_mode.toggled.connect(func(_value: bool) -> void:cancel())
	button(tools,"Apply box",_apply_box)
	button(tools,"Cancel",func() -> void:cancel();box_anchor=[];box_end=[];_feedback())
	var plane: OptionButton=OptionButton.new()
	for label: String in ["Plane X","Plane Y","Plane Z"]: plane.add_item(label)
	plane.selected=1;tools.add_child(plane);plane.item_selected.connect(func(index: int) -> void:cancel();plane_axis=index;_feedback())
	var height: SpinBox=SpinBox.new();height.min_value=0;height.max_value=15;height.step=1;height.custom_minimum_size.x=70;tools.add_child(height)
	height.value_changed.connect(func(value: float) -> void:cancel();plane_index=int(value);_feedback())
	for label: String in ["Front","Top","Side"]: button(tools,label,func() -> void:cancel();preview.set_view(label))
	coordinates=Label.new();coordinates.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;add_child(coordinates)
	var split: HSplitContainer=HSplitContainer.new();split.size_flags_vertical=Control.SIZE_EXPAND_FILL;add_child(split)
	sidebar=ScrollContainer.new();sidebar.custom_minimum_size.x=220;split.add_child(sidebar)
	var inspector: VBoxContainer=VBoxContainer.new();inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL;sidebar.add_child(inspector)
	id_edit=field(inspector,"Stable asset ID","namespace:name")
	name_edit=field(inspector,"Display name","Voxel asset")
	button(inspector,"Apply display name",func() -> void:
		if not document.data.is_empty(): _changed(document.rename(name_edit.text)))
	palette_list=OptionButton.new();inspector.add_child(palette_list);palette_list.item_selected.connect(func(index: int) -> void: swatch=document.data.palette[index].key;_palette_fields();_feedback())
	swatch_key=field(inspector,"Swatch key (stable)","trim")
	color_picker=ColorPickerButton.new();color_picker.custom_minimum_size.y=30;color_picker.edit_alpha=false;inspector.add_child(color_picker)
	reference_mode=CheckBox.new();reference_mode.text="Use block colour reference";inspector.add_child(reference_mode)
	block_ref=field(inspector,"Existing solid block ID","leyforge:stone")
	button(inspector,"Apply swatch",_apply_swatch)
	button(inspector,"Recover backup draft",func() -> void:_result(Publication.resume_draft(document,id_edit.text,true));_refresh())
	button(inspector,"Export recovery draft",_export)
	button(inspector,"Discard saved draft…",func() -> void:discard.popup_centered())
	technical=RichTextLabel.new();technical.custom_minimum_size=Vector2(200,140);technical.fit_content=true;technical.selection_enabled=true;inspector.add_child(technical)
	preview=preload("res://tools/forge/workspaces/preview_test/preview_viewport.gd").new();preview.size_flags_horizontal=Control.SIZE_EXPAND_FILL;split.add_child(preview)
	preview.asset_mode=true;preview.asset_input.connect(_input_view);preview.capture_cancelled.connect(cancel)
	button(preview.get_child(0),"Frame model",func() -> void:cancel();selection={};_frame_bounds();preview.frame_selection();_feedback())
	preview.get_child(preview.get_child_count()-1).text="LMB tool · RMB orbit · MMB pan · Wheel zoom · F frame · XYZ axes"
	preview.asset_mode=true
	overlay=MeshInstance3D.new();preview.preview_root.add_child(overlay)
	ghost=MeshInstance3D.new();ghost.mesh=BoxMesh.new();ghost.mesh.size=Vector3.ONE/16;preview.preview_root.add_child(ghost);ghost.visible=false
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.y=36;add_child(status)
	confirmation=ConfirmationDialog.new();confirmation.title="Publish voxel source (bake separately)";confirmation.ok_button_text="Publish voxel source";add_child(confirmation)
	review=RichTextLabel.new();review.custom_minimum_size=Vector2(540,240);review.selection_enabled=true;confirmation.add_child(review)
	confirmation.confirmed.connect(func() -> void:_result(Publication.publish(document,true));_refresh())
	discard=ConfirmationDialog.new();discard.title="Discard voxel draft?";discard.dialog_text="Export first if needed. Remove this asset's draft and recovery files?";add_child(discard)
	export_dialog=FileDialog.new();export_dialog.title="Export published bake to an external directory";export_dialog.file_mode=FileDialog.FILE_MODE_OPEN_DIR;export_dialog.access=FileDialog.ACCESS_FILESYSTEM;add_child(export_dialog)
	export_dialog.dir_selected.connect(func(directory: String) -> void:_result(Publication.export_bake(document,bake_path,directory)))
	discard.confirmed.connect(func() -> void:
		if Source.valid_id(id_edit.text):
			for suffix: String in ["",".bak",".pending"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(Publication.draft_path(id_edit.text)+suffix))
			document.draft_problem=false;_result({"success":true,"reason":"Saved voxel draft explicitly discarded; open source or create again"}))
	get_window().focus_exited.connect(cancel)
	visibility_changed.connect(cancel)
	_feedback()

func _load(mode: String) -> void:
	cancel()
	if not document.data.is_empty() and document.dirty() and not document.draft_problem:
		var saved: Dictionary=document.save_draft()
		if not saved.success:_result(saved);return
	var outcome: Dictionary
	match mode:
		"new":
			if Source.valid_id(id_edit.text) and FileAccess.file_exists(Publication.draft_path(id_edit.text)): _result(Source.fail("Saved draft exists; reopen or explicitly discard"));return
			outcome=document.create(id_edit.text,name_edit.text)
		"source":
			if Source.valid_id(id_edit.text) and FileAccess.file_exists(Publication.draft_path(id_edit.text)):_result(Source.fail("Saved voxel draft exists; reopen it or explicitly discard before opening source"));return
			outcome=document.open(id_edit.text)
		_: outcome=Publication.resume_draft(document,id_edit.text)
	_result(outcome);selection={};box_anchor=[];box_end=[];bake_path="";_refresh();preview.frame_selection()

func _result(outcome: Dictionary) -> void:
	last_result=outcome
	status.text=("✓ " if outcome.success else "Error: ")+str(outcome.get("reason",""))
	if status.text=="✓ ":status.text+="Voxel operation committed"

func _changed(outcome: Dictionary) -> void:
	_result(outcome)
	if outcome.success:
		bake_path=""
		var saved: Dictionary=document.save_draft()
		if not saved.success:_result(saved)
	_refresh()

func _refresh() -> void:
	if document.data.is_empty():return
	id_edit.text=document.data.id;name_edit.text=document.data.display_name
	palette_list.clear()
	for entry: Dictionary in document.data.palette:
		palette_list.add_item(entry.key)
		if entry.key==swatch:palette_list.select(palette_list.item_count-1)
	if not document.data.palette.any(func(entry: Dictionary) -> bool:return entry.key==swatch):swatch=document.data.palette[0].key
	_palette_fields()
	var resolved: Dictionary=Source.resolve(document.data,document.root)
	var bundle: Dictionary={}
	if resolved.success and not document.data.cells.is_empty():bundle=Compiler.compile(document.data,resolved,"").get("bundle",{})
	preview.show_asset(bundle,document.data.id,document.revision)
	_frame_bounds();_details();_feedback()

func _details() -> void:
	if document.data.is_empty():return
	technical.text="%s\nVersion %d · revision %d\n%d occupied / 4096\n%s\nUndo %d · redo %d\n%s\n%s" % [document.data.id,document.data.asset_version,document.revision,document.data.cells.size(),"Unpublished" if document.dirty() else "Matches published source",document.history.cursor,document.history.commands.size()-document.history.cursor,"Current validation PASS" if document.validation.get("success",false) and document.validation.get("revision")==document.revision else "Validate before publication",document.relative_path]

func _palette_fields() -> void:
	if document.data.is_empty():return
	for entry: Dictionary in document.data.palette:
		if entry.key!=swatch:continue
		swatch_key.text=entry.key;reference_mode.button_pressed=entry.has("block_ref");block_ref.text=entry.get("block_ref","leyforge:stone");color_picker.color=Color(entry.get("color","#FFFFFFFF"))

func _apply_swatch() -> void:
	if document.data.is_empty():return
	cancel()
	var value: Dictionary={"key":swatch_key.text}
	if reference_mode.button_pressed:value.block_ref=block_ref.text
	else:value.color="#"+color_picker.color.to_html(false).to_upper()+"FF"
	var palette: Array=document.data.palette.duplicate(true);var found: bool=false
	for index: int in palette.size():
		if palette[index].key==value.key:palette[index]=value;found=true
	if not found:palette.append(value)
	var outcome: Dictionary=document.edit_palette(palette)
	if outcome.success:swatch=value.key
	_changed(outcome)

func cancel() -> void:
	stroke=false;pending={};last_cell=[];hover={}
	if ghost!=null:ghost.visible=false
	_feedback()

func _input_view(event: InputEvent) -> void:
	if document.data.is_empty() or document.draft_problem:return
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE:cancel();return
		if event.ctrl_pressed and event.keycode==KEY_Z:_changed(document.undo());return
		if event.ctrl_pressed and event.keycode==KEY_Y:_changed(document.redo());return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if preview.dragging!=0:return
		var ray: Dictionary=preview.asset_ray(event.position)
		hover=Picking.target(ray.origin,ray.direction,Source.occupancy(document.data),"Select" if box_mode.button_pressed else tool,plane_axis,plane_index)
		if event is InputEventMouseMotion and stroke:
			if not hover.valid:cancel()
			else:_sweep(event.position)
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not hover.valid:_result(Source.fail("Invalid/out-of-bounds target; no edit"))
				elif box_mode.button_pressed:
					if box_anchor.is_empty() or not box_end.is_empty():box_anchor=hover.cell.duplicate();box_end=[]
					else:box_end=hover.cell.duplicate()
				elif tool=="Select":
					if not event.shift_pressed:selection={}
					var key: String=Source.key(hover.cell)
					if event.shift_pressed and selection.has(key):selection.erase(key)
					else:selection[key]=hover.cell.duplicate()
					_frame_bounds()
				else:stroke=true;stroke_tool=tool;stroke_swatch=swatch;stroke_pointer=event.position;pending={};last_cell=[];_sample(hover.cell)
			elif stroke:
				_sweep(event.position)
				if not stroke:return
				var cells: Array=pending.values();var active_tool: String=stroke_tool;var active_swatch: String=stroke_swatch;cancel();_changed(document.edit_cells(cells,active_tool,active_swatch))
		_feedback()

func _sample(cell: Array) -> void:
	if not Source.inside(cell):cancel();return
	pending[Source.key(cell)]=cell.duplicate()
	last_cell=cell.duplicate()

func _sweep(position: Vector2) -> void:
	# Sample intervening viewport pixels so depth discontinuities never connect
	# through hidden interiors. Targets still use the immutable stroke document.
	var steps: int=maxi(1,int(ceil(position.distance_to(stroke_pointer))))
	if steps>4096:cancel();return
	var occupied: Dictionary=Source.occupancy(document.data)
	for index: int in range(1,steps+1):
		var point: Vector2=stroke_pointer.lerp(position,float(index)/steps)
		var ray: Dictionary=preview.asset_ray(point)
		var target: Dictionary=Picking.target(ray.origin,ray.direction,occupied,stroke_tool,plane_axis,plane_index)
		if not target.valid:cancel();return
		_sample(target.cell)
	stroke_pointer=position

func _frame_bounds() -> void:
	var cells: Array=selection.values()
	if cells.is_empty() and not document.data.is_empty():cells=document.data.cells
	if cells.is_empty():preview.bounds=AABB(Vector3.ZERO,Vector3.ONE);return
	var minimum: Vector3=Vector3(16,16,16);var maximum: Vector3=Vector3.ZERO
	for cell: Array in cells:
		minimum=minimum.min(Vector3(cell[0],cell[1],cell[2]));maximum=maximum.max(Vector3(cell[0]+1,cell[1]+1,cell[2]+1))
	preview.bounds=AABB(minimum/16,(maximum-minimum)/16)

func _apply_box() -> void:
	cancel()
	if box_anchor.is_empty() or box_end.is_empty():_result(Source.fail("Choose two bounded box anchors"));return
	var cells: Array=Picking.box(box_anchor,box_end)
	if tool=="Select":
		selection={}
		for cell: Array in cells:selection[Source.key(cell)]=cell
		_frame_bounds();_feedback()
	else:_changed(document.edit_cells(cells,tool,swatch))

func _feedback() -> void:
	if coordinates==null:return
	var metric: String=""
	if hover.get("cell",[]).size()==3:
		var cell: Array=hover.cell;metric=" (%.4f, %.4f, %.4f m)" % [float(cell[0])/16,float(cell[1])/16,float(cell[2])/16]
	coordinates.text="%s · %s · plane %s=%d · %s%s · %d selected · box %d · stroke %d" % [tool,swatch,["X","Y","Z"][plane_axis],plane_index,str(hover.get("cell",[])),metric,selection.size(),0 if box_anchor.is_empty() or box_end.is_empty() else Picking.box(box_anchor,box_end).size(),pending.size()]
	if overlay==null:return
	var lines: ImmediateMesh=ImmediateMesh.new();var material: StandardMaterial3D=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.vertex_color_use_as_albedo=true
	lines.surface_begin(Mesh.PRIMITIVE_LINES,material)
	_wire_box(lines,Vector3.ZERO,Vector3.ONE,Color("94a9b5"))
	for n: int in 17:
		var a: Vector3=Vector3.ZERO;var b: Vector3=Vector3.ZERO;var u: int=(plane_axis+1)%3;var v: int=(plane_axis+2)%3
		a[plane_axis]=float(plane_index)/16;a[u]=float(n)/16;b=a;b[v]=1
		_line(lines,a,b,Color("415b68"));a[v]=float(n)/16;a[u]=0;b=a;b[u]=1;_line(lines,a,b,Color("415b68"))
	for cell: Array in selection.values():_wire_box(lines,Vector3(cell[0],cell[1],cell[2])/16,Vector3.ONE/16,Color("f2d67d"))
	for cell: Array in pending.values():_wire_box(lines,Vector3(cell[0],cell[1],cell[2])/16,Vector3.ONE/16,Color("72ecb2"))
	if not box_anchor.is_empty():
		var end: Array=box_anchor if box_end.is_empty() else box_end
		var low: Vector3=Vector3(mini(box_anchor[0],end[0]),mini(box_anchor[1],end[1]),mini(box_anchor[2],end[2]))
		var high: Vector3=Vector3(maxi(box_anchor[0],end[0])+1,maxi(box_anchor[1],end[1])+1,maxi(box_anchor[2],end[2])+1)
		_wire_box(lines,low/16,(high-low)/16,Color("ffe57a"))
	lines.surface_end();overlay.mesh=lines
	ghost.visible=hover.get("cell",[]).size()==3
	if ghost.visible:
		var cell: Array=hover.cell;ghost.position=(Vector3(cell[0],cell[1],cell[2])+Vector3.ONE/2)/16
		var tint: Color=Color("5edca6") if hover.get("valid",false) else Color("ff3344")
		if hover.get("valid",false) and tool=="Remove":tint=Color("ff8866")
		elif hover.get("valid",false) and tool=="Paint":
			var resolved: Dictionary=Source.resolve(document.data,document.root)
			if resolved.success:tint=Color(resolved.colors.get(swatch,"#FFFFFFFF"))
		var ghost_material: StandardMaterial3D=StandardMaterial3D.new();ghost_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;ghost_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;tint.a=0.55;ghost_material.albedo_color=tint;ghost_material.no_depth_test=true;ghost.material_override=ghost_material

func _line(mesh: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	mesh.surface_set_color(color);mesh.surface_add_vertex(a);mesh.surface_add_vertex(b)

func _wire_box(mesh: ImmediateMesh, minimum: Vector3, extent: Vector3, color: Color) -> void:
	for axis: int in 3:
		for a: int in 2:
			for b: int in 2:
				var start: Vector3=minimum;start[(axis+1)%3]+=extent[(axis+1)%3]*a;start[(axis+2)%3]+=extent[(axis+2)%3]*b
				var end: Vector3=start;end[axis]+=extent[axis];_line(mesh,start,end,color)

func _review() -> void:
	cancel()
	if document.data.is_empty():return
	var checked: Dictionary=document.validate();_result(checked);_details()
	if not checked.success:return
	review.text="%s\n%s\nVersion %d → %d\n16³ cells · 16 cells/metre · lower corner\n%d occupied · %d swatches\n\nSource publication changes canonical content compatibility. Bake separately.\n\n%s" % ["Create" if document.base_hash=="ABSENT" else "Update",document.root.path_join(document.relative_path),0 if document.base.is_empty() else document.base.asset_version,1 if document.base.is_empty() else document.base.asset_version+(1 if document.dirty() else 0),document.data.cells.size(),document.data.palette.size(),Source.bytes({"before":document.base,"after":document.data})]
	review.text=checked.reason+"\n"+review.text
	confirmation.popup_centered(Vector2i(mini(700,get_window().size.x-60),mini(460,get_window().size.y-80)))

func _runtime() -> void:
	cancel()
	if bake_path.is_empty():_result(Source.fail("Bake the current published source first"));return
	var runner: String=preload("res://src/forge_eng/import_export/content_publication.gd").RUNNER.replace(".console.exe",".exe")
	var pid: int=OS.create_process(runner,["--path",ProjectSettings.globalize_path("res://"),"res://scenes/testing/voxel_asset_runtime.tscn","--",document.root,document.relative_path,bake_path])
	_result({"success":pid>0,"reason":"Separate LFE runtime process "+str(pid)})

func _export() -> void:
	if not Source.valid_id(id_edit.text):return
	var source: String=Publication.draft_path(id_edit.text)
	var folder: String=ProjectSettings.globalize_path(Publication.DRAFT_ROOT.path_join("exports"));DirAccess.make_dir_recursive_absolute(folder)
	var destination: String=folder.path_join(id_edit.text.replace(":","_")+"-"+str(Time.get_ticks_usec())+".draft.json")
	var code: Error=DirAccess.copy_absolute(ProjectSettings.globalize_path(source),destination)
	_result({"success":code==OK,"reason":"Recovery export: "+destination})

func close_document() -> bool:
	cancel()
	if document.data.is_empty() or document.draft_problem:return true
	var saved: Dictionary=document.save_draft();_result(saved);return saved.success
