extends Node3D
## Standalone LFE consumer. No editor, gameplay, save or network imports.
const Loader = preload("res://src/lfe/voxel/voxel_asset_loader.gd")
var loaded: Dictionary = {}
var instance: MeshInstance3D
var collision: StaticBody3D

func _ready() -> void:
	get_window().title="Leyforge — Voxel asset runtime proof"
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()<3:
		_message("Runtime requires root, source relative path and baked bundle");return
	loaded=Loader.load_bundle(args[0],args[1],args[2])
	if not loaded.success:_message(loaded.reason);return
	instance=MeshInstance3D.new();instance.mesh=Loader.mesh(loaded.bundle);instance.material_override=Loader.material();add_child(instance)
	collision=Loader.body(loaded.bundle);add_child(collision)
	var camera: Camera3D=Camera3D.new();add_child(camera);camera.position=Vector3(-1.5,1.6,-1.8);camera.look_at(Vector3(0.5,0.4,0.5));camera.near=0.01
	var environment: WorldEnvironment=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("18232e");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.7;add_child(environment)
	var light: DirectionalLight3D=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-25,0);add_child(light)
	var ruler: MeshInstance3D=MeshInstance3D.new();ruler.mesh=BoxMesh.new();ruler.mesh.size=Vector3(1,0.01,0.01);ruler.position=Vector3(0.5,-0.04,1.05);add_child(ruler)
	_message("LFE runtime · %s v%d\nOne-metre reference below · %d collision boxes\nPublished source and dependencies verified" % [loaded.bundle.id,loaded.bundle.asset_version,loaded.bundle.collision_boxes.size()])

func _message(text: String) -> void:
	var canvas: CanvasLayer=CanvasLayer.new();add_child(canvas)
	var label: Label=Label.new();label.position=Vector2(20,20);label.text=text;canvas.add_child(label)
