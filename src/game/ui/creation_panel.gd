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
	var v: Dictionary = _world.active_character.survival.snapshot()
	var water: String = "  |  Water %.0f" % v["thirst"] if _world.active_character.survival.thirst_enabled() else ""
	_hud.text="Health %.0f  |  Stamina %.0f\nFood %.0f%s\nFatigue %.1f\n%s" % [v["health"],v["stamina"],v["hunger"],water,v["fatigue"],"Sheltered" if _world._sheltered else "Outdoors"]
	_context.text=_world.player.context_text();_context.visible=not _world.player.inventory_open
