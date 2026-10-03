extends SettingsOptionButton

const LOCALES: Array[Dictionary] = [
	{"locale": "en", "key": &"LANG_ENGLISH"},
	{"locale": "pt", "key": &"LANG_PORTUGUESE"},
]

func _populate() -> void:
	for i in LOCALES.size():
		add_item(tr(LOCALES[i].key), i)
		set_item_metadata(i, LOCALES[i].locale)
	selected = NodeUtil.option_index_by_metadata(self, Settings.settings.preferred_locale)

func _on_locale_refresh() -> void:
	for i in LOCALES.size():
		set_item_text(i, tr(LOCALES[i].key))

func _on_item_selected(index: int) -> void:
	SignalBus.locale_changed.emit(LOCALES[index].locale)
