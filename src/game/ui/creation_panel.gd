class_name LeyforgeCreationPanel
extends CanvasLayer

var _world: LeyforgeWave1Playground
var _hud: Label
var _context: Label

func configure(world: LeyforgeWave1Playground) -> void:
	_world=world;layer=4
	var base: Control = Control.new();base.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(base)
	_hud=Label.new();_hud.position=Vector2(950,20);base.add_child(_hud)
	_context=Label.new();_context.position=Vector2(330,370)
	_context.custom_minimum_size=Vector2(620,35);_context.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	base.add_child(_context)

func _process(_delta: float) -> void:
	if _world==null:return
	var v: Dictionary = _world.survival_system.owner_view()
	if v.is_empty():
		_hud.text = "Synchronizing survival"
		return
	var water: String = "  |  Water %.0f" % v["thirst"] if v["thirst_enabled"] else ""
	_hud.text="Health %.0f  |  Stamina %.0f\nFood %.1f%s\nFatigue %.1f  |  Exposure %.1f\n%s" % [v["health"],v["stamina"],v["hunger"],water,v["fatigue"],v["exposure"],"Resting in shelter; move to stop" if v["resting"] else "Sheltered" if v["sheltered"] else "Outdoors"]
	_context.text=_world.player.context_text();_context.visible=not _world.player.inventory_open
