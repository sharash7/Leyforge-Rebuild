extends Control

const VOXEL_CLASS_NAME := &"VoxelTerrain"

@onready var status: Label = $Status


func _ready() -> void:
	print("LEYFORGE_WAVE_0_BOOTSTRAP_READY")

	if not ClassDB.class_exists(VOXEL_CLASS_NAME):
		_fail("Voxel Tools is not registered: missing class %s" % VOXEL_CLASS_NAME)
		return

	var voxel_instance: Object = ClassDB.instantiate(VOXEL_CLASS_NAME)
	if voxel_instance == null:
		_fail("Voxel Tools class could not be instantiated: %s" % VOXEL_CLASS_NAME)
		return

	voxel_instance.free()
	status.text = "Leyforge\nWave 0 environment ready"
	print("LEYFORGE_VOXEL_PLUGIN_READY class=%s" % VOXEL_CLASS_NAME)

	if _is_headless():
		get_tree().quit(0)


func _fail(message: String) -> void:
	status.text = "Leyforge\nWave 0 environment error"
	push_error(message)

	if _is_headless():
		get_tree().quit(1)


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"
