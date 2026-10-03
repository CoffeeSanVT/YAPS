extends SpinBox

func _ready() -> void:
	if ModelLoader.model_loaded == null:
		return
	set_value_no_signal(ModelLoader.model_loaded.global_animation_chance)

func _on_value_changed(_value: float) -> void:
	if ModelLoader.model_loaded == null:
		return
	ModelLoader.model_loaded.global_animation_chance = value
	ModelLoader.save_model()
	SignalBus.states_changed.emit()