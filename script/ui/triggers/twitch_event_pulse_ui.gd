class_name TwitchEventPulseUi
extends TwitchEventUi

@export var pulse_check: CheckButton
@export var pulse_duration_row: HBoxContainer
@export var pulse_duration_spinbox: SpinBox

func _ready() -> void:
	super._ready()
	pulse_check.toggled.connect(_on_pulse_toggled)
	pulse_duration_spinbox.value_changed.connect(_on_pulse_duration_changed)

func setup(trigger: TwitchEvent) -> void:
	super.setup(trigger)
	pulse_check.set_pressed_no_signal(trigger.pulse_mode)
	pulse_duration_spinbox.set_value_no_signal(trigger.pulse_duration)
	_update_pulse_duration_row_visible()

func _on_pulse_toggled(pressed: bool) -> void:
	if _loading or _trigger == null:
		return
	_trigger.pulse_mode = pressed
	if not pressed:
		_trigger.cancel_pulse()
	_update_pulse_duration_row_visible()
	ModelLoader.save_model()

func _on_pulse_duration_changed(value: float) -> void:
	if _loading or _trigger == null:
		return
	_trigger.pulse_duration = value
	ModelLoader.save_model()

func _update_pulse_duration_row_visible() -> void:
	if pulse_duration_row == null:
		return
	pulse_duration_row.visible = _trigger != null and _trigger.pulse_mode
