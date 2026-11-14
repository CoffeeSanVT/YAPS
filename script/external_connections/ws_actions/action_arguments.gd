class_name ActionArguments
extends RefCounted

static func apply_transform_options(value: float, parts: PackedStringArray, current: float) -> Dictionary:
	return TransformOptions.parse(value, parts, current)

static func parse_bool(text: String) -> Variant:
	match text.strip_edges().to_lower():
		"true", "1", "on":
			return true
		"false", "0", "off":
			return false
	return null

static func find_named(entries: Array, prop: StringName, value: String) -> Variant:
	for entry: Variant in entries:
		if entry.get(prop) == value:
			return entry
	return null

static func name_list(entries: Array, prop: StringName) -> Array[String]:
	var names: Array[String] = []
	for entry: Variant in entries:
		names.append(String(entry.get(prop)))
	return names
