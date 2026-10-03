class_name SettingsCheckButton
extends CheckButton

var settings_field: StringName = &""
var changed_signal: StringName = &""

func _ready() -> void:
	_init_from_settings()

func _init_from_settings() -> void:
	button_pressed = Settings.settings.get(settings_field)

func _on_toggled(toggled_on: bool) -> void:
	SignalBus.emit_signal(changed_signal, toggled_on)