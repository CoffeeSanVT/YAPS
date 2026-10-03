extends SettingsCheckButton

func _init() -> void:
	settings_field = &"show_mic_visualizer"
	changed_signal = &"mic_visualizer_changed"