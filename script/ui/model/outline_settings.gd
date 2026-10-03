extends VBoxContainer

@export_category("Outline")
@export var enable_toggle: CheckButton
@export var color_picker: ColorPickerButton
@export var width_spinbox: SpinBox
@export var softness_spinbox: SpinBox
@export var inside_toggle: CheckButton
@export var threshold_spinbox: SpinBox
@export var halftone_toggle: CheckButton
@export var dot_size_spinbox: SpinBox
@export var gradient_toggle: CheckButton
@export var gradient_color_picker: ColorPickerButton

func _ready() -> void:
	var model := ModelLoader.model_loaded
	if model == null:
		return

	ColorPickerUtil.apply_header_hover_theme(color_picker)
	ColorPickerUtil.apply_header_hover_theme(gradient_color_picker)

	enable_toggle.button_pressed = model.outline_enabled
	color_picker.color = model.outline_color
	width_spinbox.value = model.outline_width
	softness_spinbox.value = model.outline_softness
	inside_toggle.button_pressed = model.outline_inside
	threshold_spinbox.value = model.outline_alpha_threshold
	halftone_toggle.button_pressed = model.outline_halftone
	dot_size_spinbox.value = model.outline_halftone_size
	gradient_toggle.button_pressed = model.outline_gradient
	gradient_color_picker.color = model.outline_gradient_color

	enable_toggle.toggled.connect(_apply_field.bind(&"outline_enabled"))
	color_picker.color_changed.connect(_apply_field.bind(&"outline_color"))
	width_spinbox.value_changed.connect(_apply_field.bind(&"outline_width"))
	softness_spinbox.value_changed.connect(_apply_field.bind(&"outline_softness"))
	inside_toggle.toggled.connect(_apply_field.bind(&"outline_inside"))
	threshold_spinbox.value_changed.connect(_apply_field.bind(&"outline_alpha_threshold"))
	halftone_toggle.toggled.connect(_apply_field.bind(&"outline_halftone"))
	dot_size_spinbox.value_changed.connect(_apply_field.bind(&"outline_halftone_size"))
	gradient_toggle.toggled.connect(_apply_field.bind(&"outline_gradient"))
	gradient_color_picker.color_changed.connect(_apply_field.bind(&"outline_gradient_color"))

func _apply_field(value: Variant, field: StringName) -> void:
	var model := ModelLoader.model_loaded
	if model == null:
		return
	model.set(field, value)
	ModelLoader.save_model()
	SignalBus.outline_settings_changed.emit()
