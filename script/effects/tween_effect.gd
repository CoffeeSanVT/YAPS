class_name TweenEffect
extends BaseEffect

var _target: Node
var _tween: Tween
var _base_property: StringName
var _base_value: Variant

func activate(target: Node) -> void:
	if target == null:
		return
	_on_activate(target)

func _on_activate(_target_node: Node) -> void:
	pass

func _target_valid() -> bool:
	return is_instance_valid(_target)

func _stop_tween() -> void:
	_tween = NodeUtil.stop_tween(_tween)

func _prepare(target: Node, property: StringName) -> void:
	if _target != target or _tween == null or not _tween.is_valid():
		_target = target
		_base_property = property
		_base_value = target.get(property)
	_stop_tween()
	target.set(property, _base_value)

func _start_on(target: Node, method: Callable, duration: float, loops: bool) -> void:
	_tween = target.create_tween()
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
