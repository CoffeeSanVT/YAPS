class_name FilterEffect
extends TweenEffect

const MODE_PARAM: StringName = &"_Filter"
const AMOUNT_PARAM: StringName = &"_FilterAmount"

func _fade_filter(mode: int, to_value: float, fade_duration: float) -> void:
	_stop_tween()
	if not _target_valid():
		_target = null
		return
	var mat := _target.material as ShaderMaterial
	if mat == null:
		push_warning(TAG + "Target has no ShaderMaterial; filter effect skipped.")
		return
	_tween = _target.create_tween()
	_tween.tween_method(func(value: float) -> void: _set_filter(mode, value), _filter_amount(mat), clampf(to_value, 0.0, 1.0), maxf(fade_duration, 0.01))

func _filter_amount(mat: ShaderMaterial) -> float:
	var value: Variant = mat.get_shader_parameter(AMOUNT_PARAM)
	return float(value) if value != null else 0.0

func _set_filter(mode: int, amount: float) -> void:
	if not _target_valid():
		return
	var mat := _target.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(MODE_PARAM, mode)
		mat.set_shader_parameter(AMOUNT_PARAM, amount)
