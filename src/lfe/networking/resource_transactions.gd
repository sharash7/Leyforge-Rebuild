class_name LfeResourceTransactions
extends RefCounted

const RETAIN: int = 256
var authority: LfeGameplayAuthority
var catalog: LfeBlockCatalog
var adapter: Callable
var revisions: Dictionary = {}
var hashes: Dictionary = {}
var completed: Dictionary = {}
var owners: Dictionary = {}
var sequences: Dictionary = {}
var rates: Dictionary = {}
var commits: int = 0

func configure(a: LfeGameplayAuthority, c: LfeBlockCatalog, world_adapter: Callable) -> void:
	authority = a; catalog = c; adapter = world_adapter

func streams() -> Dictionary:
	var result: Dictionary = {}
	for actor: String in authority.characters:
		result["player/"+actor] = authority.character(actor).resources.snapshot()
		if authority._grids.has(actor):
			var g: LfeCraftingGrid = authority._grids[actor]
			result["grid/"+actor] = {"size":g.size,"slots":g.inventory.snapshot(),"context":authority._grid_objects[actor]}
	for s: Dictionary in authority.world_resources.drops(): result["drop/"+s["instance"]] = s
	for s: Dictionary in authority.world_resources.snapshot()["storage"]: result["storage/"+s["instance"]] = s
	for s: Dictionary in authority.creation.sources(): result["source/"+s["instance"]] = s
	for s: Dictionary in authority.creation.objects(): result["object/"+s["instance"]] = s
	return result

func observe() -> Dictionary:
	var all: Dictionary = streams()
	for key: String in all:
		var logical: Dictionary = all[key].duplicate(true)
		# Drop positions travel separately, without invalidating pickup revisions.
		if key.begins_with("drop/"): logical.erase("position")
		var hash_value: String = LfeResourceProtocol.normalized(logical).sha256_text()
		if hashes.get(key,"") != hash_value:
			revisions[key] = int(revisions.get(key,0))+1; hashes[key] = hash_value
	return all

static func stream_for(actor: String, endpoint: String) -> String:
	if endpoint in ["inventory","equipment"]: return "player/"+actor
	if endpoint == "grid": return "grid/"+actor
	if endpoint.begins_with("station/"): return "object/"+endpoint.get_slice("/",1)
	return endpoint

func required(actor: String, op: String, args: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	match op:
		"open_context":
			keys.append("player/"+actor)
			if authority._grids.has(actor): keys.append("grid/"+actor)
		"select","drop","place": keys.append("player/"+actor)
		"pickup": keys.assign(["player/"+actor,"drop/"+args["target"]])
		"transfer","swap":
			keys.append(stream_for(actor,args["source"])); keys.append(stream_for(actor,args["destination"]))
			if keys[0].begins_with("storage/") and authority.creation.storage(args["source"].get_slice("/",1)) != null: keys[0] = "object/"+args["source"].get_slice("/",1)
			if keys[1].begins_with("storage/") and authority.creation.storage(args["destination"].get_slice("/",1)) != null: keys[1] = "object/"+args["destination"].get_slice("/",1)
		"craft": keys.assign(["player/"+actor,"grid/"+actor])
		"close_grid":
			keys.append("player/"+actor)
			if authority._grids.has(actor): keys.append("grid/"+actor)
		"start_process": keys.append("object/"+args["target"])
		"source_hold": keys.append("source/"+args["target"])
	return keys

func allowed(actor: String, key: String, all: Dictionary) -> bool:
	if not all.has(key): return false
	if key.begins_with("player/") or key.begins_with("grid/"): return key.get_slice("/",1) == actor
	var s: Dictionary = all[key]
	var p: Array = s.get("position",[])
	if p.is_empty():
		p = s["cell"].map(func(v: Variant)->float: return float(v)+0.5)
	return authority.near(actor,p,96)

func leave(peer: int, actor: String) -> void:
	sequences.erase(peer); rates.erase(peer)
	authority.execute(actor,"close_grid")
	# Failed release retains the grid. Save explicitly resolves every actor grid.

func execute(peer: int, actor: String, p: Dictionary, now: float) -> Dictionary:
	var result: LfeCommandResult = LfeCommandResult.rejected("invalid_target")
	if not LfeResourceProtocol.request_valid(p,catalog) or authority.character(actor) == null: return {}
	var id: String = p["transaction_id"]
	var fingerprint: String = LfeResourceProtocol.normalized({"operation":p["operation"],"args":p["args"],"expected_revisions":p["expected_revisions"]})
	var rate: Dictionary = rates.get(peer,{"tokens":16.0,"time":now})
	rate["tokens"] = minf(16,float(rate["tokens"])+maxf(0,now-float(rate["time"]))*40)
	rate["time"] = now; rates[peer] = rate
	if float(rate["tokens"]) < 1:
		# Back pressure cannot turn an already committed retry into a failure result.
		if owners.has(id): return {}
		return _result(id,LfeCommandResult.rejected("rate_limited"))
	rate["tokens"] -= 1
	var last: int = int(sequences.get(peer,0))
	if owners.has(id):
		if owners[id] != actor or completed[actor][id]["fingerprint"] != fingerprint: return _result(id,LfeCommandResult.rejected("stale_state"))
		# An exact retry may repeat its old sequence, or use a fresh reconnect sequence.
		if int(p["sequence"]) > last:
			if int(p["sequence"])-last > 4096: return _result(id,LfeCommandResult.rejected("stale_state"))
			sequences[peer] = int(p["sequence"])
		return completed[actor][id]["result"].duplicate(true)
	if int(p["sequence"]) <= last or int(p["sequence"])-last > 4096: return _result(id,LfeCommandResult.rejected("stale_state"))
	sequences[peer] = int(p["sequence"])
	var all: Dictionary = observe()
	var keys: Array[String] = required(actor,p["operation"],p["args"])
	var stale: bool = false
	for key: String in keys:
		if not allowed(actor,key,all) or not p["expected_revisions"].has(key) or int(p["expected_revisions"][key]) != int(revisions.get(key,0)): stale = true
	for key: String in p["expected_revisions"]:
		if not allowed(actor,key,all): stale = true
	if stale: result = LfeCommandResult.rejected("stale_state")
	else:
		var op: String = p["operation"]
		var a: Dictionary = p["args"].duplicate(true)
		if op in ["drop","place"] and authority.character(actor).resources.inventory.stack_at(int(a["slot"])) != a["expected"]: result = LfeCommandResult.rejected("stale_state")
		elif op == "open_context":
			var target: String = a["target"]
			if not target.is_empty() and not authority.object_near(actor,target): result = LfeCommandResult.rejected("out_of_range")
			elif target.is_empty() or _workbench(target):
				if authority._grids.has(actor):
					if not authority.execute(actor,"close_grid").success: result = LfeCommandResult.rejected("inventory_full")
					else: result = _open(actor,target)
				else: result = _open(actor,target)
			elif authority._endpoint(actor,"storage/"+target,false) != null or authority.creation.station(target) != null: result = LfeCommandResult.accepted({"context":target})
			else: result = LfeCommandResult.rejected("context_invalid")
		elif op in ["pickup","drop","place","source_hold"]: result = adapter.call(actor,op,a,now)
		else: result = authority.execute(actor,op,a)
		if result.success: commits += 1
	var response: Dictionary = _result(id,result)
	if not completed.has(actor): completed[actor] = {}
	if completed[actor].size() >= RETAIN:
		var oldest: String = completed[actor].keys()[0]
		completed[actor].erase(oldest); owners.erase(oldest)
	completed[actor][id] = {"fingerprint":fingerprint,"result":response.duplicate(true)}
	owners[id] = actor
	observe()
	return response

func _workbench(id: String) -> bool:
	for s: Dictionary in authority.creation.objects():
		if s["instance"] == id: return catalog.content_definition(StringName(s["content"])).get("function") == "workbench"
	return false
func _open(actor: String, target: String) -> LfeCommandResult:
	return LfeCommandResult.accepted({"context":target}) if authority.open_grid(actor,target) != null else LfeCommandResult.rejected("context_invalid")
func _result(id: String, r: LfeCommandResult) -> Dictionary:
	return {"kind":"resource_result","transaction_id":id,"success":r.success,"reason":r.reason_code if r.reason_code in LfeResourceProtocol.REASONS else "invalid_target","data":r.data}
