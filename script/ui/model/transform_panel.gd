extends Node


var _syncing: bool = false

func _ready() -> void:
	SignalBus.model_transform_values.connect(_on_transform_values)

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"model_transform_values", _on_transform_values)

func _request_position(value: Vector2) -> void:
	var controller := _transform_controller()
	if controller != null:
		controller.apply_position(value)

func _request_scale(value: float) -> void:
	var controller := _transform_controller()
	if controller != null:
		controller.apply_scale(value)

func _request_rotation(value: float) -> void:
	var controller := _transform_controller()
	if controller != null:
		controller.apply_rotation(value)

func _request_preset(preset: TransformPreset) -> void:
	var controller := _transform_controller()
	if controller != null:
		controller.apply_preset(preset)

func _transform_controller() -> UpdateModelTransform:
	return UpdateModelTransform.find_controller(get_tree())

func _on_transform_values(pos: Vector2, sc: float, rot: float) -> void:
	_syncing = true
	_apply_transform_values(pos, sc, rot)
	_syncing = false

func _apply_transform_values(_pos: Vector2, _sc: float, _rot: float) -> void:
	pass