class_name LfeGameplayAuthority
extends RefCounted

var characters: Dictionary = {}
var world_resources: LfeWorldResourceState
var creation: LfeCreationState
var overrides: LfeVoxelOverrideStore
var owner_player_id: String
var _catalog: LfeBlockCatalog
var _grids: Dictionary = {}
var _grid_objects: Dictionary = {}
# The live voxel world supplies relevance; focused state tests have no terrain.
var relevant: Callable

func configure(save: LfeWorldSave,catalog: LfeBlockCatalog) -> bool:
	_catalog=catalog;owner_player_id=save.owner_player_id;overrides=save.overrides
	var next: Dictionary={}
	for entry: Dictionary in save.players_state:
		var record: LfePlayerCharacter=LfePlayerCharacter.new(entry["player_id"],catalog)
		if not record.restore(entry):return false
		next[record.player_id]=record
	world_resources=LfeWorldResourceState.new(catalog)
	creation=LfeCreationState.new(catalog)
	if not world_resources.restore(save.world_resource_state) or not creation.restore(save.creation_state,save.world_resource_state):return false
	characters=next;_grids.clear();_grid_objects.clear()
	return true

func character(actor: String) -> LfePlayerCharacter:
	return characters.get(actor)

func add_character(actor: String,spawn: Vector3) -> LfePlayerCharacter:
	if not LfeWorldResourceState._valid_identity(actor) or not spawn.is_finite():return null
	if characters.has(actor):return characters[actor]
	if characters.size()>=LfeWorldSave.MAX_PLAYERS:return null
	var record: LfePlayerCharacter=LfePlayerCharacter.new(actor,_catalog)
	record.transform={"position":[spawn.x,spawn.y,spawn.z],"yaw":0.0,"pitch":0.0,"selected_block":""}
	if not LfePlayerCharacter.valid_transform(record.transform,_catalog):return null
	characters[actor]=record
	return record

func players_snapshot() -> Array:
	var ids: Array=characters.keys();ids.sort()
	var result: Array=[]
	for id: String in ids:result.append(characters[id].snapshot())
	return result

func advance_world(seconds: float) -> bool:
	return creation.advance(seconds)

func near(actor: String,coordinates: Array,distance: float) -> bool:
	var record: LfePlayerCharacter=character(actor)
	if record==null:return false
	var a: Array=record.transform["position"]
	var target: Vector3=Vector3(float(coordinates[0]),float(coordinates[1]),float(coordinates[2]))
	return Vector3(float(a[0]),float(a[1]),float(a[2])).distance_to(target)<=distance and (not relevant.is_valid() or relevant.call(target))

func object_near(actor: String,id: String) -> bool:
	for entry: Dictionary in creation.objects():
		if entry["instance"]==id:
			var p: Array=entry["cell"]
			return near(actor,[float(p[0])+0.5,float(p[1])+0.5,float(p[2])+0.5],4)
	for entry: Dictionary in world_resources.snapshot()["storage"]:
		if entry["instance"]==id:return near(actor,entry["position"],4)
	return false

func open_grid(actor: String,object_id: String="") -> LfeCraftingGrid:
	if character(actor)==null or _grids.has(actor):return null
	if not object_id.is_empty():
		if not object_near(actor,object_id):return null
		var found: bool=false
		for entry: Dictionary in creation.objects():
			if entry["instance"]==object_id and _catalog.content_definition(StringName(entry["content"])).get("function")=="workbench":found=true
		if not found:return null
	var grid: LfeCraftingGrid=LfeCraftingGrid.new(_catalog,creation.recipes,2 if object_id.is_empty() else 3)
	_grids[actor]=grid;_grid_objects[actor]=object_id
	return grid

func _endpoint(actor: String,name: String,writing: bool) -> LfeInventory:
	var record: LfePlayerCharacter=character(actor)
	if record==null:return null
	match name:
		"inventory":return record.resources.inventory
		"equipment":return record.resources.equipment
		"grid":
			if not _grids.has(actor):return null
			var target: String=_grid_objects[actor]
			if not target.is_empty() and not object_near(actor,target):return null
			return _grids[actor].inventory
	var fields: PackedStringArray=name.split("/")
	if fields.size()==2 and fields[0]=="storage" and object_near(actor,fields[1]):
		var stored: LfeInventory=world_resources.storage_inventory(fields[1])
		return creation.storage(fields[1]) if stored==null else stored
	if fields.size()==3 and fields[0]=="station" and object_near(actor,fields[1]):
		var station: LfeWorkstation=creation.station(fields[1])
		if station==null:return null
		match fields[2]:
			"input":return station.input
			"fuel":return station.fuel
			"output":return null if writing else station.output
	return null

# UI may query inventories by reference; mutation resolves endpoint ownership again.
func endpoint_name(actor: String,inventory: LfeInventory) -> String:
	if character(actor)==null or inventory==null:return ""
	for name: String in ["inventory","equipment","grid"]:
		if _endpoint(actor,name,false)==inventory:return name
	for entry: Dictionary in world_resources.snapshot()["storage"]+creation.objects():
		var id: String=entry["instance"]
		var stored: String="storage/"+id
		if _endpoint(actor,stored,false)==inventory:return stored
		for channel: String in ["input","fuel","output"]:
			var name: String="station/"+id+"/"+channel
			if _endpoint(actor,name,false)==inventory:return name
	return ""

func execute(actor: String,operation: String,args: Dictionary={}) -> LfeCommandResult:
	var record: LfePlayerCharacter=character(actor)
	if record==null:return LfeCommandResult.rejected("invalid_actor")
	for field: String in ["target","recipe","source","destination"]:
		if args.has(field) and not args[field] is String:return LfeCommandResult.rejected("invalid_target")
	for field: String in ["sheltered","resting","sprinting"]:
		if args.has(field) and not args[field] is bool:return LfeCommandResult.rejected("invalid_target")
	var personal: LfePlayerResourceState=record.resources
	match operation:
		"select":
			if not LfeWorldSave._is_integer(args.get("slot")) or not personal.select(int(args["slot"])):return LfeCommandResult.rejected("invalid_target")
			return LfeCommandResult.accepted()
		"pickup":
			var id: String=args.get("target","")
			var drop: Dictionary=world_resources.drop(id)
			if drop.is_empty():return LfeCommandResult.rejected("invalid_target")
			if not near(actor,drop["position"],2):return LfeCommandResult.rejected("out_of_range")
			var count: int=world_resources.pickup(personal,id)
			return LfeCommandResult.accepted({"quantity":count}) if count>0 else LfeCommandResult.rejected("inventory_full")
		"drop":
			if not args.get("position") is Vector3 or not LfeWorldSave._is_integer(args.get("slot")) or not LfeWorldSave._is_integer(args.get("quantity")):return LfeCommandResult.rejected("invalid_target")
			var p: Vector3=args["position"]
			if not near(actor,[p.x,p.y,p.z],4):return LfeCommandResult.rejected("out_of_range")
			var id: String=world_resources.drop_from_inventory(personal,int(args["slot"]),int(args["quantity"]),p)
			return LfeCommandResult.accepted({"drop_id":id}) if not id.is_empty() else LfeCommandResult.rejected("insufficient_resources")
		"transfer","swap":
			var source: LfeInventory=_endpoint(actor,args.get("source",""),false)
			var target: LfeInventory=_endpoint(actor,args.get("destination",""),true)
			if source==null or target==null:return LfeCommandResult.rejected("invalid_target")
			if not LfeWorldSave._is_integer(args.get("source_slot")) or not LfeWorldSave._is_integer(args.get("destination_slot",-1)):return LfeCommandResult.rejected("invalid_target")
			var slot: int=int(args["source_slot"])
			if args.has("expected") and source.stack_at(slot)!=args["expected"]:return LfeCommandResult.rejected("stale_state")
			if operation=="swap":
				# Both endpoints receive items. Output cannot be a swap destination.
				if _endpoint(actor,args.get("source",""),true)==null:return LfeCommandResult.rejected("invalid_target")
				return LfeCommandResult.accepted() if LfeItemTransactions.swap(source,slot,target,int(args["destination_slot"])) else LfeCommandResult.rejected("blocked")
			if not LfeWorldSave._is_integer(args.get("quantity")):return LfeCommandResult.rejected("invalid_target")
			var count: int=LfeItemTransactions.transfer(source,slot,target,int(args["quantity"]),int(args.get("destination_slot",-1)),true)
			return LfeCommandResult.accepted({"quantity":count}) if count>0 else LfeCommandResult.rejected("blocked")
		"craft":
			if not record.survival.alive() or not _grids.has(actor) or _endpoint(actor,"grid",true)==null:return LfeCommandResult.rejected("not_ready")
			return LfeCommandResult.accepted() if _grids[actor].take(personal.inventory,args.get("recipe","")) else LfeCommandResult.rejected("insufficient_resources")
		"close_grid":
			if not _grids.has(actor):return LfeCommandResult.accepted()
			# Returning staging is allowed even after its world context vanished.
			if not _grids[actor].release(personal.inventory):return LfeCommandResult.rejected("inventory_full")
			_grids.erase(actor);_grid_objects.erase(actor)
			return LfeCommandResult.accepted()
		"consume":
			return LfeCommandResult.accepted() if record.survival.consume(personal.inventory,personal.selected_slot()) else LfeCommandResult.rejected("blocked")
		"damage":
			if not LfeWorldSave._finite_in_range(args.get("amount"),100):return LfeCommandResult.rejected("invalid_target")
			return LfeCommandResult.accepted() if record.survival.damage(float(args["amount"])) else LfeCommandResult.rejected("blocked")
		"recover":
			if record.survival.alive() or not args.get("spawn") is Vector3 or not args["spawn"].is_finite():return LfeCommandResult.rejected("blocked")
			var p: Vector3=args["spawn"]
			if not LfeWorldResourceState._valid_position([p.x,p.y,p.z]):return LfeCommandResult.rejected("invalid_target")
			record.transform["position"]=[p.x,p.y,p.z];record.survival.respawn()
			return LfeCommandResult.accepted()
		"advance_player":
			if not LfeWorldSave._finite_in_range(args.get("seconds"),60) or float(args["seconds"])<0:return LfeCommandResult.rejected("invalid_target")
			record.survival.advance(float(args["seconds"]),bool(args.get("sheltered",false)),bool(args.get("resting",false)),bool(args.get("sprinting",false)))
			return LfeCommandResult.accepted()
		"start_process":
			var id: String=args.get("target","")
			if not object_near(actor,id):return LfeCommandResult.rejected("out_of_range")
			var station: LfeWorkstation=creation.station(id)
			if station==null:return LfeCommandResult.rejected("invalid_target")
			return LfeCommandResult.accepted() if station.start(args.get("recipe","")) else LfeCommandResult.rejected("blocked")
	return LfeCommandResult.rejected("invalid_target")

# Whole-world conservation query. Reservations represent consumed inputs until output.
func total(content: StringName) -> int:
	var count: int=world_resources.total(content)
	for record: LfePlayerCharacter in characters.values():count+=record.resources.total(content)
	for grid: LfeCraftingGrid in _grids.values():count+=grid.inventory.total(content)
	for entry: Dictionary in creation.objects():
		if entry["content"]==String(content):count+=1
		if entry.has("slots"):
			for stack: Variant in entry["slots"]:
				if stack!=null and stack["content"]==String(content):count+=int(stack["quantity"])
		if entry.has("station"):
			var station: LfeWorkstation=creation.station(entry["instance"])
			count+=station.input.total(content)+station.fuel.total(content)+station.output.total(content)
			var active: String=station.snapshot()["active"]
			if not active.is_empty():
				for input: Dictionary in creation.recipes.definition(active)["inputs"]:
					if input["content"]==String(content):count+=int(input["quantity"])
	# Positive sparse overrides represent recoverable placed material; functional
	# construction is already counted above, so it is never counted twice.
	if overrides!=null:
		for edit: Dictionary in overrides.serialized_entries():
			if edit["block"]!=String(content):continue
			var p: Array=edit["position"]
			if creation.object_at(Vector3i(int(p[0]),int(p[1]),int(p[2]))).is_empty():count+=1
	return count
