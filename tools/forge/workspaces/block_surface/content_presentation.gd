extends HSplitContainer
signal selected(id: String)
signal edited(id: String, field: String, value: String)
var document: RefCounted
var search: LineEdit
var browser: ItemList
var name_edit: LineEdit
var color: ColorPickerButton
var identity: Label
var selected_id: String = "leyforge:stone"
var ids: Array[String] = []

func _ready() -> void:
	split_offset = 260
	var list: VBoxContainer = VBoxContainer.new(); list.custom_minimum_size.x = 190; add_child(list)
	search = LineEdit.new(); search.placeholder_text = "Search canonical IDs / names"; list.add_child(search); search.text_changed.connect(func(_text: String) -> void: populate())
	browser = ItemList.new(); browser.size_flags_vertical = Control.SIZE_EXPAND_FILL; list.add_child(browser); browser.item_selected.connect(_choose)
	var editor: VBoxContainer = VBoxContainer.new(); editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL; add_child(editor)
	identity = Label.new(); identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; editor.add_child(identity)
	var label: Label = Label.new(); label.text = "Display name"; editor.add_child(label)
	name_edit = LineEdit.new(); editor.add_child(name_edit); name_edit.text_submitted.connect(func(_text: String) -> void: commit_name())
	var apply: Button = Button.new(); apply.text = "Apply name"; apply.pressed.connect(commit_name); editor.add_child(apply)
	var color_label: Label = Label.new(); color_label.text = "Block colour · #RRGGBBAA"; editor.add_child(color_label)
	color = ColorPickerButton.new(); color.custom_minimum_size.y = 38; color.edit_alpha = true; editor.add_child(color)
	# Keep the native colour surface and hex/alpha entry usable at 960x540.
	color.get_picker().presets_visible = false
	color.get_picker().sliders_visible = false
	color.get_picker().sampler_visible = false
	color.get_picker().color_modes_visible = false
	# A whole picker interaction commits once when the popup closes.
	color.get_popup().popup_hide.connect(func() -> void:
		if not color.disabled: edited.emit(selected_id, "color", "#" + color.color.to_html(true).to_upper()))
	var note: Label = Label.new(); note.text = "IDs and voxel mappings are immutable.\nItem-only and non-solid entries are read-only.\nApply the name before changing selection."; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; editor.add_child(note)

func commit_name() -> void:
	if name_edit.editable: edited.emit(selected_id, "display_name", name_edit.text)

func populate() -> void:
	if document == null: return
	browser.clear(); ids.clear()
	for entry: Dictionary in document.data.get("blocks", []) + document.data.get("items", []):
		if not search.text.is_empty() and not (str(entry.id) + " " + str(entry.display_name)).to_lower().contains(search.text.to_lower()): continue
		ids.append(entry.id); browser.add_item(entry.id + (" [read-only]" if not entry.get("solid", false) else ""))
		if entry.id == selected_id: browser.select(ids.size() - 1)
	refresh()

func _choose(index: int) -> void:
	selected_id = ids[index]; refresh(); selected.emit(selected_id)

func refresh() -> void:
	if document == null: return
	var entry: Dictionary = document.definition(selected_id)
	var editable: bool = entry.get("solid", false) and entry.get("kind") == "block"
	identity.text = "%s\nVoxel mapping: %s · %s" % [selected_id, str(entry.get("voxel_id", "item-only")), "Editable presentation" if editable else "Read-only"]
	name_edit.text = entry.get("display_name", ""); name_edit.editable = editable
	color.disabled = not editable; color.color = Color.from_string(entry.get("color", "#FFFFFFFF"), Color.WHITE)
