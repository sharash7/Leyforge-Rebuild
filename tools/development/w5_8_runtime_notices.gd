extends SceneTree
func _initialize() -> void:
	var output: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not output.is_absolute_path(): quit(1); return
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	if file == null: quit(1); return
	file.store_string("Godot shutdown-fixed custom runtime\n\n"+Engine.get_license_text()+"\n\nBundled third-party notices:\n"+JSON.stringify(Engine.get_copyright_info(),"\t")+"\n\nLicense texts:\n"+JSON.stringify(Engine.get_license_info(),"\t"))
	file=null; quit(0)
