class_name ContentFitScroll
extends ScrollContainer

var _content: Control

func _ready() -> void:
	_content = _find_content()
	if _content == null:
		return
	_content.minimum_size_changed.connect(_update_min_height)
	_update_min_height()

func _find_content() -> Control:
	for child in get_children():
		if child is Control:
			return child
	return null

func _update_min_height() -> void:
	var content_height := _content.get_combined_minimum_size().y
	custom_minimum_size.y = clampf(content_height, 0.0, custom_maximum_size.y)
