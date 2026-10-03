class_name BaseEffect
extends Resource

const TAG := "[BaseEffect] "

var effect_name: StringName
var ui_prefab: PackedScene

static var _available_options: PackedStringArray
static var _scripts_by_name: Dictionary = {}
static var _options_scanned := false

static func get_available_options() -> PackedStringArray:
	if not _options_scanned:
		_options_scanned = true
		_available_options = PackedStringArray()
		for option in ClassScanner.scan_inheriters(&"BaseEffect", &"effect_name"):
			_available_options.append(option.id)
			_scripts_by_name[String(option.id)] = option.script

	return _available_options

static func instantiate_effect_by_name(effect_id: String) -> BaseEffect:
	if not _options_scanned:
		get_available_options()
	var script_res: Script = _scripts_by_name.get(effect_id)
	if script_res != null and script_res.can_instantiate():
		var instance: BaseEffect = script_res.new() as BaseEffect
		if instance != null:
			return instance

	push_error(TAG + "Could not find or instantiate effect: " + effect_id)
	return null

static func localize_name(id: StringName) -> String:
	var key := "EFFECT_" + String(id).to_upper()
	var translated := String(TranslationServer.translate(key))
	if translated.is_empty() or translated == key:
		return String(id).capitalize()
	return translated

func active_for_talking(_is_talking: bool) -> bool:
	return true

func activate(_target: Node) -> void:
	pass

func deactivate() -> void:
	pass
