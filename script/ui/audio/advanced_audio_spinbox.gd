extends SpinBox

@export var signal_name: StringName

func _ready() -> void:
	value = Settings.settings.get(_settings_property())

func _on_value_changed(new_value: float) -> void:
	SignalBus.get(signal_name).emit(int(new_value))

func _settings_property() -> String:
	return String(signal_name).trim_suffix("_changed")
