extends "res://tests/forge/w6_2_process.gd"
## Normal event injection inherited from W6.2; only observation/report differs.
var read_retries: int=0

func walk(node: Node, widgets: Array) -> void:
	if node is SpinBox and node.is_visible_in_tree():
		var rect: Rect2=node.get_global_rect()
		widgets.append({"class":"SpinBox","text":str(node.value),"path":str(node.get_path()),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
	super.walk(node,widgets)

func execute(command: Dictionary) -> void:
	if command.op not in ["hold","release","move"]:
		await super.execute(command);return
	if command.op=="move":
		var event: InputEventMouseMotion=InputEventMouseMotion.new();event.position=Vector2(command.x,command.y);event.relative=Vector2.ZERO;Input.parse_input_event(event)
	else:mouse(Vector2(command.x,command.y),int(command.get("button",1)),command.op=="hold")
	await process_frame;await process_frame;processed+=1;write_report();busy=false

func _process(_delta: float) -> bool:
	if app==null:return false
	if FileAccess.file_exists(proof+".stop"):app._close();return false
	var path: String=proof+".command.json"
	if not busy and FileAccess.file_exists(path):
		# Read the flushed command before claiming it; Windows may briefly deny a
		# newly renamed file. Retry sharing failures only, never malformed inputs.
		var file: FileAccess=FileAccess.open(path,FileAccess.READ)
		if file==null:
			read_retries+=1
			if read_retries>120:push_error("Command transport cannot read flushed file");quit(2)
			return false
		var payload: String=file.get_as_text();file.close();read_retries=0
		var parser: JSON=JSON.new()
		if parser.parse(payload)!=OK or not parser.data is Dictionary:
			push_error("Malformed W6.3 command retained at "+path);quit(2);return false
		if DirAccess.remove_absolute(path)!=OK:return false
		busy=true;call_deferred("execute",parser.data)
	return false
func write_report() -> void:
	var widgets: Array=[];walk(app,widgets)
	var tabs: Array=[];var bar: TabBar=app.pages.get_tab_bar()
	for index: int in bar.tab_count:
		var rect: Rect2=bar.get_tab_rect(index);rect.position+=bar.global_position;tabs.append([rect.position.x,rect.position.y,rect.size.x,rect.size.y])
	var workspace: VBoxContainer=app.voxel_workspace;var doc: RefCounted=workspace.document;var view: VBoxContainer=workspace.preview
	var sidebar_rect: Rect2=workspace.sidebar.get_global_rect()
	# Pending presentation is observed separately from canonical data/history.
	var ghost_visible: bool=workspace.ghost.visible
	var projections: Dictionary={}
	for x: int in 16:
		for z: int in 16:
			for y: int in [0,2,5,7,8,15]:
				var pixel: Vector2=view.camera.unproject_position((Vector3(x,y,z)+Vector3(0.5,0,0.5))/16.0)
				var point: Vector2=view.surface.global_position+pixel*view.surface.size/Vector2(view.viewport.size)
				projections["%d,%d,%d" % [x,y,z]]=[point.x,point.y]
	var file: FileAccess=FileAccess.open(proof+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"ready":true,"pid":OS.get_process_id(),"processed":processed,"window_size":[root.size.x,root.size.y],"tabs":tabs,"widgets":widgets,"sidebar":[sidebar_rect.position.x,sidebar_rect.position.y,sidebar_rect.size.x,sidebar_rect.size.y],"data":doc.data,"revision":doc.revision,"undo":doc.history.cursor,"redo":doc.history.commands.size()-doc.history.cursor,"dirty":doc.dirty(),"draft_problem":doc.draft_problem,"last_result":workspace.last_result,"yaw":view.yaw,"pitch":view.pitch,"distance":view.distance,"focus":[view.focus.x,view.focus.y,view.focus.z],"projections":projections,"tool":workspace.tool,"swatch":workspace.swatch,"hover":workspace.hover,"ghost_visible":ghost_visible,"pending":workspace.pending.size(),"stroke":workspace.stroke,"selection":workspace.selection.size(),"box_count":0 if workspace.box_anchor.is_empty() or workspace.box_end.is_empty() else workspace.Picking.box(workspace.box_anchor,workspace.box_end).size(),"bake_path":workspace.bake_path,"mesh":view.content!=null,"source_root":doc.root,"relative_path":doc.relative_path},"  "));file.close()
