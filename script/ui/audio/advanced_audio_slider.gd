extends HSlider

@export var value_label: Label
@export var signal_name: StringName
@export var format_string: String = "%s"

func _ready() -> void:
	value = Settings.settings.get(_settings_property())
	value_label.text = _format(value)

func _on_value_changed(new_value: float) -> void:
	SignalBus.get(signal_name).emit(new_value)
	value_label.text = _format(new_value)

func _settings_property() -> String:
	return String(signal_name).trim_suffix("_changed")

func _format(new_value: float) -> String:
	return format_string % new_value
