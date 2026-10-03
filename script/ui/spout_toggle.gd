extends SettingsCheckButton

func _init() -> void:
	settings_field = &"spout_enabled"
	changed_signal = &"spout_enabled_changed"

func _ready() -> void:
	if not ClassDB.class_exists(&"SpoutViewport"):
		button_pressed = false
		disabled = true
		return
	_init_from_settings()