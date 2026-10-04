class_name LfeTestCreationView
extends RefCounted
var world: LfeCreationState
var survival: LfeCharacterSurvival=LfeCharacterSurvival.new()
var _catalog: LfeBlockCatalog
var recipes: LfeRecipeCatalog:
	get:return world.recipes
var content_error: String:
	get:return world.content_error
func _init(catalog: LfeBlockCatalog) -> void:
	_catalog=catalog;world=LfeCreationState.new(catalog)
static func view(w: LfeCreationState,s: LfeCharacterSurvival) -> LfeTestCreationView:
	var v: LfeTestCreationView=LfeTestCreationView.new(w._catalog);v.world=w;v.survival=s;return v
func snapshot() -> Dictionary:
	var s: Dictionary=world.snapshot();s["survival"]=survival.snapshot();return s
func restore(data: Variant,resources: Dictionary={}) -> bool:
	if not data is Dictionary or data.size()!=5:return false
	var next: LfeCreationState=LfeCreationState.new(_catalog)
	var biology: LfeCharacterSurvival=LfeCharacterSurvival.new()
	var c: Dictionary=data.duplicate(true);c.erase("survival")
	var w: Dictionary={} if resources.is_empty() else {"drops":resources["drops"],"storage":resources["storage"]}
	if not biology.restore(data.get("survival")) or not next.restore(c,w):return false
	var slots: Array=[]
	if not resources.is_empty():slots=resources["inventory"]+resources["equipment"]
	var seen: Dictionary={}
	for e: Dictionary in resources.get("drops",[]):seen[e["instance"]]=true;slots.append(e["stack"])
	for e: Dictionary in resources.get("storage",[]):seen[e["instance"]]=true;slots.append_array(e["slots"])
	for e: Dictionary in next.objects():
		if seen.has(e["instance"]):return false
		seen[e["instance"]]=true
		if e.has("slots"):slots.append_array(e["slots"])
		if e.has("station"):
			for channel: String in ["input","fuel","output"]:slots.append_array(e["station"][channel])
	for e: Dictionary in next.sources():
		if seen.has(e["instance"]):return false
		seen[e["instance"]]=true
	if not LfeWorldResourceState.unique_instances(slots,seen):return false
	world=next;survival=biology;return true
func initialize_sources(seed: int,version: int=1) -> bool:return world.initialize_sources(seed,version)
func validate_source_layout(seed: int,version: int=1) -> bool:return world.validate_source_layout(seed,version)
func sources() -> Array:return world.sources()
func source(id: String) -> Dictionary:return world.source(id)
func source_definition(id: String) -> Dictionary:return world.source_definition(id)
func harvest_source(id: String,r: LfeTestResourceView) -> bool:return world.harvest_source(id,r.personal,survival)
func objects() -> Array:return world.objects()
func object_at(cell: Vector3i) -> String:return world.object_at(cell)
func add_object(content: StringName,cell: Vector3i,orientation: int) -> bool:return world.add_object(content,cell,orientation)
func can_remove(cell: Vector3i) -> bool:return world.can_remove(cell)
func remove_object(cell: Vector3i) -> bool:return world.remove_object(cell)
func station(id: String) -> LfeWorkstation:return world.station(id)
func storage(id: String) -> LfeInventory:return world.storage(id)
func advance(seconds: float,sheltered: bool,resting: bool,sprinting: bool) -> bool:
	if not world.advance(seconds):return false
	survival.advance(seconds,sheltered,resting,sprinting);return true
