class_name ColorPickerUtil
extends RefCounted

const HEADER_HOVER_COLOR := Color(1.0, 0.439216, 0.545098, 1.0)
const HEADER_TEXTS: PackedStringArray = ["Swatches", "Recent Colors"]

static func apply_header_hover_theme(picker_button: ColorPickerButton) -> void:
	var picker: ColorPicker = picker_button.get_picker()
	if picker == null:
		return
	for child in picker.find_children("*", "Button", true, false):
		var button := child as Button
		if button == null or not button.flat or not button.toggle_mode:
			continue
		if not button.text in HEADER_TEXTS:
			continue
		button.add_theme_color_override("font_hover_color", HEADER_HOVER_COLOR)
		button.add_theme_color_override("font_hover_pressed_color", HEADER_HOVER_COLOR)
