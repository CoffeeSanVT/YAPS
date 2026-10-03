extends SettingsCheckButton

func _init() -> void:
	settings_field = &"show_performance_overlay"
	changed_signal = &"performance_overlay_changed"