extends RefCounted
## Discardable locations only. Definitions remain owned by the runtime catalogs.
static func collect(document: Dictionary, catalog: LfeBlockCatalog, path: String, location: String = "") -> Array:
	var result: Array = []
	_walk(document, catalog, path, location, result)
	return result

static func _walk(value: Variant, catalog: LfeBlockCatalog, path: String, location: String, result: Array) -> void:
	if value is Dictionary:
		var keys: Array = value.keys(); keys.sort()
		for key: String in keys:
			var child: Variant = value[key]
			var field: String = location + "/" + key
			if key in ["content", "drop_content"] and child is String and not child.is_empty():
				result.append({"source": path, "field": field, "id": child, "resolved": catalog.has_content(StringName(child))})
			_walk(child, catalog, path, field, result)
	elif value is Array:
		for index: int in value.size(): _walk(value[index], catalog, path, location + "/" + str(index), result)
