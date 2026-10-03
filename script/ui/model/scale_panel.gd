extends "res://script/ui/model/transform_panel.gd"

@export_category("UI References")
@export var spinbox: SpinBox

func _on_scale_value_changed(value: float) -> void:
	if _syncing:
		return
	_request_scale(value)

func _apply_transform_values(_pos: Vector2, sc: float, _rot: float) -> void:
	spinbox.set_value_no_signal(sc)
