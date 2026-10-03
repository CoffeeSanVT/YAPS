extends SpinBox

func _ready() -> void:
	value = Settings.settings.max_fps

func _on_value_changed(new_value: float) -> void:
	SignalBus.fps_limit_changed.emit(int(new_value))
