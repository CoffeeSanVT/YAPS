extends "res://script/ui/model/transform_panel.gd"

@export_category("UI References")
@export var x_spinbox: SpinBox
@export var y_spinbox: SpinBox

func _on_x_axis_value_changed(value: float) -> void:
	if _syncing:
		return
	_request_position(Vector2(value, y_spinbox.value * -1))

func _on_y_axis_value_changed(value: float) -> void:
	if _syncing:
		return
	_request_position(Vector2(x_spinbox.value, value * -1))

func _apply_transform_values(pos: Vector2, _sc: float, _rot: float) -> void:
	x_spinbox.set_value_no_signal(pos.x)
	y_spinbox.set_value_no_signal(pos.y * -1)
