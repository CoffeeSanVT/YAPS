extends CheckButton

@export var interval_row: Control
@export var interval_spin: SpinBox
@export var value_container: Control

func _ready() -> void:
	if ModelLoader.model_loaded == null:
		return
	set_pressed_no_signal(ModelLoader.model_loaded.random_anim_interval_enabled)
	_apply_state(button_pressed)

func _on_toggled(pressed: bool) -> void:
	if ModelLoader.model_loaded == null:
		return
	ModelLoader.model_loaded.random_anim_interval_enabled = pressed
	ModelLoader.save_model()
	_apply_state(pressed)

func _apply_state(enabled: bool) -> void:
	if interval_spin != null:
		interval_spin.editable = not enabled
	if interval_row != null:
		interval_row.modulate.a = 0.5 if enabled else 1.0
	if value_container != null:
		value_container.visible = enabled