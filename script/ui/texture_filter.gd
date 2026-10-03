extends SettingsOptionButton

func _init() -> void:
	changed_signal = &"texture_filter_changed"

func _populate() -> void:
	clear()
	add_item(tr(&"TEXTURE_FILTER_NEAREST"), CanvasItem.TEXTURE_FILTER_NEAREST)
	add_item(tr(&"TEXTURE_FILTER_LINEAR"), CanvasItem.TEXTURE_FILTER_LINEAR)
	selected = _index_of_id(Settings.settings.texture_filter, 1)

func _on_locale_refresh() -> void:
	_repopulate_keeping_selection(1)
