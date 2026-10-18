extends SceneTree
const Source = preload("res://src/lfe/content/voxel_asset.gd")
var runtime: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	runtime=load("res://scenes/testing/voxel_asset_runtime.tscn").instantiate();root.add_child(runtime)
	await process_frame;await physics_frame;await physics_frame
	var checks: Array=[]
	checks.append({"label":"LFE runtime load/reconstruct","passed":runtime.loaded.get("success",false) and runtime.instance!=null and runtime.collision!=null})
	if runtime.loaded.get("success",false):
		var source: Dictionary=Source.read_source(args[0],args[1]);var occupancy: Dictionary=Source.occupancy(source.data)
		var probe: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new();probe.shape=SphereShape3D.new();probe.shape.radius=0.005
		var mismatches: Array=[];var occupied_count: int=0;var empty_count: int=0
		for x: int in 16:
			for y: int in 16:
				for z: int in 16:
					probe.transform=Transform3D(Basis.IDENTITY,(Vector3(x,y,z)+Vector3.ONE/2)/16)
					var hit: bool=not runtime.get_world_3d().direct_space_state.intersect_shape(probe,1).is_empty()
					var expected: bool=occupancy.has(Source.key([x,y,z]))
					if expected:occupied_count+=1
					else:empty_count+=1
					if hit!=expected:mismatches.append([x,y,z])
		checks.append({"label":"native collision all 4096 cell centres, holes empty","passed":mismatches.is_empty(),"mismatches":mismatches,"occupied":occupied_count,"empty":empty_count})
		checks.append({"label":"fine voxel world scale","passed":runtime.instance.mesh.get_aabb().end.x<=1.00001 and runtime.loaded.bundle.voxels_per_metre==16})
		var used_colors: Dictionary={}
		for cell: Array in source.data.cells:used_colors[source.colors[cell[3]]]=true
		checks.append({"label":"two distinct occupied palette colours","passed":used_colors.size()>=2})
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[3]+".png")
	var passed: bool=checks.all(func(item: Dictionary)->bool:return item.passed)
	var file: FileAccess=FileAccess.open(args[3]+".json",FileAccess.WRITE);file.store_string(JSON.stringify({"passed":passed,"pid":OS.get_process_id(),"checks":checks,"bundle":args[2],"source":args[1]},"  "));file.close();quit(0 if passed else 1)
