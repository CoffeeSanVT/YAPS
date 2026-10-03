extends OptionButton

func _ready() -> void:
	_populate()
	selected = NodeUtil.option_index_by_metadata(self, Settings.settings.window_resolution)

func _populate() -> void:
	clear()
	var resolutions: Array[Vector2i] = _available_resolutions()
	for res: Vector2i in resolutions:
		add_item("%d x %d" % [res.x, res.y])
		set_item_metadata(item_count - 1, res)

func _available_resolutions() -> Array[Vector2i]:
	var list: Array[Vector2i] = []
	var screen_size: Vector2i = DisplayServer.screen_get_size(DisplayServer.SCREEN_OF_MAIN_WINDOW)
	if screen_size.x > 0 and screen_size.y > 0:
		list.append(screen_size)
	for res: Vector2i in [
		Vector2i(1920, 1080),
		Vector2i(1600, 900),
		Vector2i(1366, 768),
		Vector2i(1280, 720),
		Vector2i(1024, 768),
	]:
		if res not in list:
			list.append(res)
	var current: Vector2i = Settings.settings.window_resolution
	if current not in list:
		list.append(current)
	return list

func _on_item_selected(index: int) -> void:
	SignalBus.window_resolution_changed.emit(get_item_metadata(index))
