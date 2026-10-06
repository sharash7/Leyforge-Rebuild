class_name LeyforgeCraftingManual
extends Control

# Read-only presentation of the same validated catalogue used for crafting.
var catalog: LfeBlockCatalog
var recipes: LfeRecipeCatalog
var _panel: PanelContainer
var _list: VBoxContainer
var _details: VBoxContainer
var selected_recipe: String = ""
var listed_ids: Array[String] = []
const CONTEXTS: Dictionary = {"hand":"Personal · 2×2", "workbench":"Workbench · 3×3", "kiln":"Kiln"}

func configure(c: LfeBlockCatalog, source: LfeRecipeCatalog) -> void:
	catalog=c; recipes=source
	name="CraftingManual"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	_panel=PanelContainer.new(); _panel.position=Vector2(220,70); _panel.custom_minimum_size=Vector2(840,500)
	var style: StyleBoxFlat = StyleBoxFlat.new(); style.bg_color=Color(0.055,0.07,0.09,1)
	style.set_content_margin_all(14); style.set_border_width_all(2); style.border_color=Color(0.65,0.5,0.3)
	_panel.add_theme_stylebox_override("panel",style); add_child(_panel)
	var body: VBoxContainer = VBoxContainer.new(); _panel.add_child(body)
	var heading: HBoxContainer = HBoxContainer.new(); body.add_child(heading)
	var title: Label = Label.new(); title.text="Crafting Manual"; title.add_theme_font_size_override("font_size",22)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; heading.add_child(title)
	var close_button: Button = Button.new(); close_button.name="CloseManual"; close_button.text="Back to inventory"
	close_button.pressed.connect(close); heading.add_child(close_button)
	var columns: HBoxContainer = HBoxContainer.new(); columns.add_theme_constant_override("separation",18); body.add_child(columns)
	var scroll: ScrollContainer = ScrollContainer.new(); scroll.custom_minimum_size=Vector2(270,430)
	columns.add_child(scroll); _list=VBoxContainer.new(); _list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(_list)
	var detail_scroll: ScrollContainer = ScrollContainer.new(); detail_scroll.custom_minimum_size=Vector2(500,430); columns.add_child(detail_scroll)
	_details=VBoxContainer.new(); _details.size_flags_horizontal=Control.SIZE_EXPAND_FILL; detail_scroll.add_child(_details)
	hide()

func open() -> void:
	for child: Node in _list.get_children(): _list.remove_child(child); child.queue_free()
	listed_ids.clear()
	for context: String in CONTEXTS:
		_label(_list,CONTEXTS[context],17)
		for recipe: Dictionary in recipes.all():
			if recipe["context"] != context: continue
			var id: String = recipe["id"]; listed_ids.append(id)
			var button: Button = Button.new(); button.name=id.trim_prefix("leyforge:"); button.text=entries(recipe["outputs"])
			button.custom_minimum_size=Vector2(250,30); button.add_theme_font_size_override("font_size",13)
			button.pressed.connect(func() -> void: select_recipe(id)); _list.add_child(button)
	show()
	if not listed_ids.is_empty(): select_recipe(selected_recipe if selected_recipe in listed_ids else listed_ids[0])

func close() -> void: hide()

func entries(values: Array) -> String:
	var parts: PackedStringArray = []
	for item: Dictionary in values:
		parts.append("%d %s" % [int(item["quantity"]),catalog.content_definition(StringName(item["content"]))["display_name"]])
	return ", ".join(parts)

func _label(parent: Node, value: String, size: int = 14) -> Label:
	var label: Label = Label.new(); label.text=value; label.add_theme_font_size_override("font_size",size)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.custom_minimum_size.x=460 if parent==_details else 250
	parent.add_child(label); return label

func select_recipe(id: String) -> void:
	var recipe: Dictionary = recipes.definition(id)
	if recipe.is_empty(): return
	selected_recipe=id
	for child: Node in _details.get_children(): _details.remove_child(child); child.queue_free()
	_label(_details,entries(recipe["outputs"]),20)
	_label(_details,"Context: "+CONTEXTS[recipe["context"]])
	_label(_details,"Ingredients: "+entries(recipe["inputs"]))
	if recipe["context"] == "kiln":
		_label(_details,"Fuel: "+entries(recipe["fuel"]))
		_label(_details,"Process time: %s seconds" % str(recipe["seconds"]))
		return
	var pattern: Dictionary = recipe.get("grid",{})
	if pattern.get("type","") != "shaped":
		_label(_details,"Shapeless — arrange these quantities anywhere in the available grid.")
		return
	_label(_details,"Shaped — empty cells must stay empty.")
	var grid: GridContainer = GridContainer.new(); grid.name="RecipePattern"; grid.columns=int(pattern["size"]); _details.add_child(grid)
	for y: int in int(pattern["size"]):
		for x: int in int(pattern["size"]):
			var symbol: String = " "
			if y < pattern["pattern"].size() and x < String(pattern["pattern"][y]).length(): symbol=String(pattern["pattern"][y])[x]
			var cell: Label = Label.new(); cell.custom_minimum_size=Vector2(145,55); cell.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; cell.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
			cell.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; cell.add_theme_font_size_override("font_size",13)
			cell.text="Empty" if symbol==" " else catalog.content_definition(StringName(pattern["keys"][symbol]))["display_name"]
			var style: StyleBoxFlat = StyleBoxFlat.new(); style.bg_color=Color(0.12,0.15,0.18); style.set_border_width_all(1); style.border_color=Color(0.4,0.4,0.4)
			cell.add_theme_stylebox_override("normal",style); grid.add_child(cell)
	_label(_details,"Horizontal mirror accepted." if pattern["mirror"] else "Use the shown orientation; horizontal mirroring is not enabled.")
	_label(_details,"The pattern may move within the grid; surrounding cells must stay empty.",12)
