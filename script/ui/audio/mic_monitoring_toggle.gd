extends SettingsCheckButton

func _init() -> void:
	settings_field = &"mic_monitoring"
	changed_signal = &"mic_monitoring_changed"
