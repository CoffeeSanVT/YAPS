class_name SettingsOptionButton
extends OptionButton

var changed_signal: StringName = &""

func _ready() -> void:
	NodeUtil.attach_locale(self, _on_locale_refresh)
	_populate()

func _populate() -> void:
	pass

func _on_locale_refresh() -> void:
	pass

func _on_item_selected(index: int) -> void:
	if changed_signal.is_empty():
		return
	SignalBus.emit_signal(changed_signal, get_item_id(index))

func _index_of_id(value: int, fallback: int = 0) -> int:
	for i in item_count:
		if get_item_id(i) == value:
			return i
	return fallback

func _repopulate_keeping_selection(fallback: int = 0) -> void:
	var current := get_item_id(selected)
	_populate()
	selected = _index_of_id(current, fallback)