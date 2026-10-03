extends ColorPickerButton

func _ready() -> void:
	if color.a <= 0.0:
		color = Color(0.15686275, 0.15294118, 0.15686275, 1)
	ColorPickerUtil.apply_header_hover_theme(self)

func _on_color_changed(_color: Color) -> void:
	SignalBus.background_color_changed.emit(_color)
