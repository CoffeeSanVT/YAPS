class_name BaseEffect
extends Resource

const TAG := "[BaseEffect] "

var effect_name: StringName
var ui_prefab: PackedScene

var _target: Node
var _tween: Tween
var _base_property: StringName
var _base_value: Variant

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

func retrigger_on_talking() -> bool:
	return false

func activate(_target_node: Node) -> void:
	pass

func deactivate() -> void:
	pass

func _target_valid() -> bool:
	return is_instance_valid(_target)

func _stop_tween() -> void:
	_tween = NodeUtil.stop_tween(_tween)

func _prepare(target: Node, property: StringName) -> void:
	if target == null:
		_target = null
		return
	if _target != target or _tween == null or not _tween.is_valid():
		_target = target
		_base_property = property
		_base_value = target.get(property)
	_stop_tween()
	target.set(property, _base_value)

func _start_on(method: Callable, duration: float, loops: bool) -> void:
	if not _target_valid():
		return
	_tween = _target.create_tween()
	if loops:
		_tween.set_loops()
	_tween.tween_method(method, 0.0, 1.0, duration)
	if not loops:
		_tween.tween_callback(_snap_to_base)

func _snap_to_base() -> void:
	if _target_valid():
		_target.set(_base_property, _base_value)
	_tween = null

func _restore_base(smooth: bool, duration: float = 0.0) -> void:
	_stop_tween()
	if not _target_valid():
		_target = null
		return
	if smooth:
		_tween = _target.create_tween()
		_tween.set_trans(Tween.TRANS_SINE)
		_tween.set_ease(Tween.EASE_IN_OUT)
		_tween.tween_property(_target, String(_base_property), _base_value, duration)
	else:
		_target.set(_base_property, _base_value)
