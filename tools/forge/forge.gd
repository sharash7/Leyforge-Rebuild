extends Control
const Document = preload("res://src/forge_eng/editing/content_document.gd")
const Publication = preload("res://src/forge_eng/import_export/content_publication.gd")
var document = Document.new()
var home: VBoxContainer
var presentation: HSplitContainer
var validation_view: VBoxContainer
var preview: VBoxContainer
var pages: TabContainer
var status: Label
var undo_button: Button
var redo_button: Button
var confirmation: ConfirmationDialog
var publish_review: RichTextLabel
var discard_dialog: ConfirmationDialog
var draft_problem: bool = false
var selected_id: String = "leyforge:stone"
var last_result: Dictionary = {}
var voxel_workspace: VBoxContainer
var catalog_actions: HBoxContainer

func _ready() -> void:
	get_window().title = "Leyforge — The Forge"
	get_window().min_size = Vector2i(960, 540)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_size = Vector2i.ZERO
	get_window().gui_embed_subwindows = true
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(_close)
	var backdrop: ColorRect = ColorRect.new(); backdrop.color = Color("15212c"); backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE; backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(backdrop)
	var margin: MarginContainer = MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(margin)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	var shell: VBoxContainer = VBoxContainer.new(); margin.add_child(shell)
	var title: Label = Label.new(); title.text = "THE FORGE  /  Content authoring"; title.add_theme_font_size_override("font_size", 24); shell.add_child(title)
	var actions: HBoxContainer = HBoxContainer.new(); shell.add_child(actions)
	catalog_actions=actions
	undo_button = _button(actions, "Undo", func() -> void: _result(document.undo()); document.validate(); _refresh())
	redo_button = _button(actions, "Redo", func() -> void: _result(document.redo()); document.validate(); _refresh())
	_button(actions, "Save draft", func() -> void:
		if draft_problem: _result(document.result(false, "Saved draft conflict: export or explicitly discard before saving"))
		else: _result(document.save_draft()))
	_button(actions, "Export draft", _export)
	_button(actions, "Discard…", func() -> void: discard_dialog.popup_centered())
	pages = TabContainer.new(); pages.size_flags_vertical = Control.SIZE_EXPAND_FILL; shell.add_child(pages)
	home = preload("res://tools/forge/workspaces/home/home.gd").new(); home.name = "Home"; pages.add_child(home)
	presentation = preload("res://tools/forge/workspaces/block_surface/content_presentation.gd").new(); presentation.name = "Content Presentation"; pages.add_child(presentation)
	validation_view = preload("res://tools/forge/workspaces/validation/validation.gd").new(); validation_view.name = "Validation"; pages.add_child(validation_view)
	preview = preload("res://tools/forge/workspaces/preview_test/preview_viewport.gd").new(); preview.name = "3D Preview"; pages.add_child(preview)
	voxel_workspace = preload("res://tools/forge/workspaces/voxel_asset/voxel_asset.gd").new(); voxel_workspace.name = "Voxel Asset"; pages.add_child(voxel_workspace)
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status.custom_minimum_size.y = 38; shell.add_child(status)
	pages.tab_changed.connect(func(index: int) -> void:catalog_actions.visible=index!=4;status.visible=index!=4)
	confirmation = ConfirmationDialog.new(); confirmation.title = "Publish canonical content"; confirmation.ok_button_text = "Publish"; add_child(confirmation)
	publish_review = RichTextLabel.new(); publish_review.custom_minimum_size = Vector2(580, 240); publish_review.selection_enabled = true; confirmation.add_child(publish_review)
	confirmation.confirmed.connect(func() -> void: _result(document.publish(true)); _refresh())
	discard_dialog = ConfirmationDialog.new(); discard_dialog.title = "Discard unpublished draft?"; discard_dialog.dialog_text = "This explicitly discards local edits and the saved draft. Canonical content is retained."; add_child(discard_dialog)
	discard_dialog.confirmed.connect(func() -> void:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Publication.DRAFT))
		draft_problem = false; _result(document.open()); _validate(); _refresh())
	presentation.document = document
	presentation.edited.connect(_edit)
	presentation.selected.connect(func(id: String) -> void: selected_id = id; _preview())
	validation_view.requested.connect(_validate)
	validation_view.publish_requested.connect(_review_publish)
	var opened: Dictionary = document.open()
	if opened.success:
		var resumed: Dictionary = document.resume_draft(); draft_problem = not resumed.success; _result(resumed)
		if not opened.reason.is_empty(): _result(opened)
		_validate()
	else: _result(opened)
	_refresh()

func _button(parent: Control, text: String, action: Callable) -> Button:
	var button: Button = Button.new(); button.text = text; parent.add_child(button); button.pressed.connect(action); return button

func _result(result: Dictionary) -> void:
	last_result = result
	status.text = ("✓ " if result.success else "Error: ") + str(result.get("reason", ""))
	if status.text == "✓ ": status.text += "Draft updated · canonical unchanged"

func _edit(id: String, field: String, value: String) -> void:
	if draft_problem: _result(document.result(false, "Resolve saved draft conflict: export or explicitly discard")); return
	var edited: Dictionary = document.apply_edit(id, field, value)
	_result(edited)
	if edited.success:
		document.validate()
		document.save_draft()
	_refresh()

func _refresh() -> void:
	home.refresh(document); presentation.populate(); validation_view.refresh(document)
	undo_button.disabled = document.history.cursor == 0 or draft_problem
	redo_button.disabled = document.history.cursor == document.history.commands.size() or draft_problem
	get_window().title = "Leyforge — The Forge" + (" * Draft" if document.dirty() else "")
	_preview()

func _validate() -> void:
	if document.data.is_empty(): return
	var report: Dictionary = document.validate()
	if not draft_problem: _result(document.result(report.success, "Validation PASS" if report.success else "Validation failed; see field diagnostics"))
	validation_view.refresh(document); home.refresh(document); _preview()

func _preview() -> void:
	if not document.validation.get("success", false) or document.validation.get("revision") != document.revision: return
	var catalog: LfeBlockCatalog = LfeBlockCatalog.new()
	if catalog.load_from_path(document.validation.stage.path_join(document.relative_path)) == OK:
		preview.show_selection(catalog, selected_id, document.revision)

func _review_publish() -> void:
	publish_review.text = "Publish only these reviewed fields?\n%s\n\n" % document.root.path_join(document.relative_path)
	for change: Dictionary in document.diff(): publish_review.text += "%s / %s\n%s → %s\n\n" % [change.id, change.field, str(change.before), str(change.after)]
	publish_review.text += "Exclusive authoring required. Running games are not reloaded."
	confirmation.popup_centered(Vector2i(mini(760, get_window().size.x - 48), mini(420, get_window().size.y - 80)))

func _export() -> void:
	var folder: String = ProjectSettings.globalize_path("user://forge/exports")
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join("draft-" + str(Time.get_unix_time_from_system()) + ".json")
	if FileAccess.file_exists(Publication.DRAFT):
		var code: Error = DirAccess.copy_absolute(ProjectSettings.globalize_path(Publication.DRAFT), path)
		_result(document.result(code == OK, "Draft export: " + path))
	else: _result(document.result(false, "Save a draft before exporting"))

func _close() -> void:
	if not voxel_workspace.close_document(): return
	if document.dirty() and not draft_problem:
		var saved: Dictionary = document.save_draft()
		if not saved.success: _result(saved); return
	get_tree().quit()
