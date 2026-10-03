class_name ClassScanner

static func _find_scripts_extending(target_class_name: StringName) -> Array[Script]:
	var result: Array[Script] = []
	var global_classes: Array[Dictionary] = ProjectSettings.get_global_class_list()
	for info in global_classes:
		var script_res := load(info["path"]) as Script
		if script_res != null and _inherits_from(script_res, target_class_name):
			result.append(script_res)
	return result

static func scan_inheriters(target_class_name: StringName, id_property: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for script_res in _find_scripts_extending(target_class_name):
		var instance: Object = script_res.new()
		if instance == null:
			continue
		var id: Variant = instance.get(id_property)
		if id == null or String(id).is_empty():
			continue
		result.append({
			"script": script_res,
			"id": StringName(id),
			"name": String(id).capitalize(),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	return result

static func _inherits_from(script_res: Script, target_class_name: StringName) -> bool:
	var current_base: Script = script_res.get_base_script()
	while current_base != null:
		if current_base.get_global_name() == target_class_name:
			return true
		current_base = current_base.get_base_script()
	return false
