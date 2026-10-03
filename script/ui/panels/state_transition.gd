extends SpinBox

func _ready() -> void:
	if ModelLoader.model_loaded == null:
		return
	value = ModelLoader.model_loaded.state_transition_duration

func _on_value_changed(_value: float) -> void:
	if ModelLoader.model_loaded == null:
		return
	ModelLoader.model_loaded.state_transition_duration = value
	ModelLoader.save_model()
