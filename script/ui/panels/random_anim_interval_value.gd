extends SpinBox

const LIMIT_MIN := 0.5
const LIMIT_MAX := 60.0

@export var is_max: bool = false
@export var opposite_spin: SpinBox

func _ready() -> void:
	if ModelLoader.model_loaded == null:
		return
	var profile := ModelLoader.model_loaded
	set_value_no_signal(profile.random_anim_interval_max if is_max else profile.random_anim_interval_min)
	_constrain()

func _on_value_changed(value: float) -> void:
	if ModelLoader.model_loaded == null:
		return
	var profile := ModelLoader.model_loaded
	if is_max:
		profile.random_anim_interval_max = value
		if profile.random_anim_interval_min > value:
			_set_opposite_value(value)
			profile.random_anim_interval_min = value
	else:
		profile.random_anim_interval_min = value
		if profile.random_anim_interval_max < value:
			_set_opposite_value(value)
			profile.random_anim_interval_max = value
	ModelLoader.save_model()
	_constrain()

func _constrain() -> void:
	if ModelLoader.model_loaded == null:
		return
	var profile := ModelLoader.model_loaded
	if is_max:
		min_value = maxf(LIMIT_MIN, profile.random_anim_interval_min)
	else:
		max_value = minf(LIMIT_MAX, profile.random_anim_interval_max)

func _set_opposite_value(value: float) -> void:
	if opposite_spin != null:
		opposite_spin.set_value_no_signal(value)