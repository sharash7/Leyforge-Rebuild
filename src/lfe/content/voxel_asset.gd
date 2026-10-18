extends RefCounted
## Schema 1 spatial assets. Fine cells never allocate world voxel IDs.
const MAX_BYTES = 1048576
const FIELDS = ["schema_version", "id", "asset_version", "display_name", "dimensions", "voxels_per_metre", "origin", "palette", "cells", "collision"]
const CATALOG = "content/blocks/wave_1_blocks.json"

static func fail(reason: String) -> Dictionary:
	return {"success": false, "reason": reason}

static func integer(value: Variant) -> bool:
	return value is int and abs(value) <= 2147483647

static func matches(pattern: String, value: String) -> bool:
	var regex: RegEx = RegEx.new(); regex.compile(pattern)
	return regex.search(value) != null

static func valid_id(id: String) -> bool:
	if id.length() > 129 or not matches("^[a-z][a-z0-9_]{0,63}:[a-z][a-z0-9_]{0,63}$", id): return false
	for part: String in id.split(":"):
		if part.to_upper() in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]: return false
	return true

static func path_for(id: String) -> String:
	return "content/voxel_assets/" + id.replace(":", "/") + ".voxel.json" if valid_id(id) else ""

static func parse(raw: PackedByteArray, limit: int = MAX_BYTES) -> Dictionary:
	if raw.is_empty() or raw.size() > limit: return fail("source: empty or exceeds byte limit")
	var text: String = raw.get_string_from_utf8()
	if text.to_utf8_buffer() != raw or text.begins_with("\uFEFF"): return fail("encoding: strict UTF-8 without BOM required")
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK: return fail("JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
	var objects: Array = []; var index: int = 0
	while index < text.length():
		var c: String = text[index]
		if c == "{": objects.append({})
		elif c == "}": objects.pop_back()
		elif c == '"':
			var start: int = index; index += 1
			while index < text.length():
				if text[index] == "\\": index += 2; continue
				if text[index] == '"': break
				index += 1
			var end: int = index + 1
			while end < text.length() and text[end] in [" ", "\n", "\r", "\t"]: end += 1
			if end < text.length() and text[end] == ":" and not objects.is_empty():
				var key: String = JSON.parse_string(text.substr(start, index - start + 1))
				if objects.back().has(key): return fail("Duplicate JSON key: " + key)
				objects.back()[key] = true
		elif c in [".", "e", "E"]: return fail("numbers: integer tokens required; floating coordinates/metadata rejected")
		index += 1
	return {"success": true, "value": integer_tree(parser.data)}

static func integer_tree(value: Variant) -> Variant:
	if value is float and is_finite(value) and value==floor(value) and abs(value)<=2147483647: return int(value)
	if value is Array:
		var result: Array=[]
		for item: Variant in value: result.append(integer_tree(item))
		return result
	if value is Dictionary:
		var result: Dictionary={}
		for key: String in value: result[key]=integer_tree(value[key])
		return result
	return value

static func bytes(data: Dictionary) -> String:
	return JSON.stringify(data, "  ", true, true) + "\n"

static func canonical(data: Dictionary) -> Dictionary:
	var value: Dictionary = data.duplicate(true)
	value.cells.sort_custom(func(a: Array, b: Array) -> bool: return less(a, b))
	value.palette.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.key < b.key)
	for swatch: Dictionary in value.palette:
		if swatch.has("color"): swatch.color = swatch.color.to_upper()
	return value

static func less(a: Array, b: Array) -> bool:
	for axis: int in 3:
		if a[axis] != b[axis]: return a[axis] < b[axis]
	return false

static func key(cell: Array) -> String:
	return "%d,%d,%d" % [cell[0], cell[1], cell[2]]

static func inside(cell: Array) -> bool:
	return cell.size() >= 3 and integer(cell[0]) and integer(cell[1]) and integer(cell[2]) and cell[0] >= 0 and cell[0] < 16 and cell[1] >= 0 and cell[1] < 16 and cell[2] >= 0 and cell[2] < 16

static func occupancy(data: Dictionary) -> Dictionary:
	var cells: Dictionary = {}
	for cell: Array in data.cells: cells[key(cell)] = cell[3]
	return cells

static func check(value: Variant, relative: String = "", finished: bool = false) -> Dictionary:
	if not value is Dictionary or value.size() != FIELDS.size() or not value.has_all(FIELDS): return fail("source: exact schema fields required")
	if not integer(value.schema_version) or value.schema_version != 1: return fail("schema_version: only 1 supported")
	if not value.id is String or not valid_id(value.id) or (not relative.is_empty() and path_for(value.id) != relative): return fail("id: invalid namespace/name or ID/path mismatch")
	if not integer(value.asset_version) or value.asset_version < 1: return fail("asset_version: positive integer required")
	if not value.display_name is String or value.display_name.strip_edges().is_empty() or value.display_name.length() > 128: return fail("display_name: 1-128 characters required")
	for field: String in ["dimensions", "origin"]:
		if not value[field] is Array or value[field].size() != 3: return fail(field + ": three integers required")
		for n: Variant in value[field]:
			if not integer(n) or n != (16 if field == "dimensions" else 0): return fail(field + ": W6.3 requires 16³ / lower-corner origin")
	if not integer(value.voxels_per_metre) or value.voxels_per_metre != 16: return fail("voxels_per_metre: W6.3 requires 16")
	if value.collision != "occupied_boxes": return fail("collision: occupied_boxes required")
	if not value.palette is Array or value.palette.is_empty() or value.palette.size() > 32: return fail("palette: 1-32 swatches required")
	var palette: Dictionary = {}
	for swatch: Variant in value.palette:
		if not swatch is Dictionary or swatch.size() != 2 or not swatch.get("key") is String or not matches("^[a-z][a-z0-9_]{0,31}$", swatch.key): return fail("palette: stable key and one color/block_ref required")
		if palette.has(swatch.key): return fail("palette: duplicate key " + swatch.key)
		palette[swatch.key] = true
		if swatch.has("color"):
			if not swatch.color is String or not matches("^#[0-9a-fA-F]{6}[fF]{2}$", swatch.color): return fail("palette " + swatch.key + ": opaque #RRGGBBFF required")
		elif not swatch.get("block_ref") is String or not valid_id(swatch.block_ref): return fail("palette " + swatch.key + ": invalid block_ref")
	if not value.cells is Array or value.cells.size() > 4096: return fail("cells: maximum 4096")
	var seen: Dictionary = {}
	for cell: Variant in value.cells:
		if not cell is Array or cell.size() != 4 or not inside(cell): return fail("cell: expected integer [x,y,z,key] within 0..15")
		if not cell[3] is String or not palette.has(cell[3]): return fail("cell " + key(cell) + ": unknown palette key")
		if seen.has(key(cell)): return fail("cell " + key(cell) + ": duplicate position")
		seen[key(cell)] = true
	if finished and value.cells.is_empty(): return fail("cells: finished assets require occupied geometry")
	if bytes(value).to_utf8_buffer().size() > MAX_BYTES: return fail("source: exceeds 1 MiB")
	return {"success": true, "reason": "", "value": canonical(value)}

static func resolve(data: Dictionary, root: String) -> Dictionary:
	var checked: Dictionary = check(data)
	if not checked.success: return checked
	var colors: Dictionary = {}; var dependencies: Dictionary = {}; var catalog: LfeBlockCatalog = null
	for swatch: Dictionary in data.palette:
		if swatch.has("color"): colors[swatch.key] = swatch.color.to_upper(); continue
		if catalog == null:
			catalog = LfeBlockCatalog.new()
			var before: String=FileAccess.get_sha256(root.path_join(CATALOG))
			if catalog.load_from_path(root.path_join(CATALOG)) != OK: return fail("block_ref catalog: " + catalog.get_last_error())
			dependencies[CATALOG] = FileAccess.get_sha256(root.path_join(CATALOG))
			if before!=dependencies[CATALOG]:return fail("block_ref catalog changed while resolving")
		var id: int = catalog.get_voxel_id(StringName(swatch.block_ref))
		if id < 0 or not catalog.is_solid_voxel(id): return fail("palette " + swatch.key + ": unknown/non-solid block_ref " + swatch.block_ref)
		colors[swatch.key] = "#" + catalog.color_for_voxel_id(id).to_html(true).to_upper()
	return {"success": true, "reason": "", "colors": colors, "dependencies": dependencies}

static func read_source(root: String, relative: String, finished: bool = true) -> Dictionary:
	var id: String=relative.trim_prefix("content/voxel_assets/").trim_suffix(".voxel.json").replace("/",":")
	if not valid_id(id) or path_for(id)!=relative:return fail("source: invalid canonical asset path")
	var file: FileAccess = FileAccess.open(root.path_join(relative), FileAccess.READ)
	if file == null: return fail("source: cannot open " + relative)
	var length: int=file.get_length()
	if length > MAX_BYTES: return fail("source: exceeds 1 MiB")
	var raw: PackedByteArray=file.get_buffer(length);file.close()
	var parsed: Dictionary = parse(raw)
	if not parsed.success: return parsed
	var checked: Dictionary = check(parsed.value, relative, finished)
	if not checked.success: return checked
	var resolved: Dictionary = resolve(checked.value, root)
	if not resolved.success: return resolved
	# parse() proved exact UTF-8 round-trip; hash these read bytes, never a later read.
	resolved.data = checked.value; resolved.source_hash = raw.get_string_from_utf8().sha256_text()
	if FileAccess.get_sha256(root.path_join(relative))!=resolved.source_hash:return fail("source changed while loading; retry explicit validation")
	return resolved
