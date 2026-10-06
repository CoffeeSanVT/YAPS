extends HSlider

@export var value_label: Label

func _ready() -> void:
	value = Settings.settings.mic_gain_db
	_update_label(value)

func _on_value_changed(new_value: float) -> void:
	SignalBus.mic_gain_changed.emit(new_value)
	_update_label(new_value)

func _update_label(new_value: float) -> void:
	value_label.text = "%d dB" % int(new_value)
