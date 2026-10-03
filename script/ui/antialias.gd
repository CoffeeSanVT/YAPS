extends SettingsOptionButton

func _init() -> void:
	changed_signal = &"antialias_changed"

func _populate() -> void:
	clear()
	add_item(tr(&"ANTIALIAS_NONE"), 0)
	add_item(tr(&"ANTIALIAS_FEATHER"), 1)
	add_item(tr(&"ANTIALIAS_SUPERSAMPLE"), 2)
	add_item(tr(&"ANTIALIAS_FXAA"), 3)
	add_item(tr(&"ANTIALIAS_MSAA_2X"), SettingsData.ANTIALIAS_MODE_MSAA_2X)
	add_item(tr(&"ANTIALIAS_MSAA_4X"), SettingsData.ANTIALIAS_MODE_MSAA_4X)
	selected = _index_of_id(Settings.settings.antialias)

func _on_locale_refresh() -> void:
	_repopulate_keeping_selection()
