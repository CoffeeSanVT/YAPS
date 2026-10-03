class_name BackgroundType
extends OptionButton

enum Type {
	GREEN = 0,
	BLUE = 1,
	MAGENTA = 2,
	TRANSPARENT = 3,
	CUSTOM_COLOR = 4,
	IMAGE = 5,
}

@export_category("Background Controls")
@export var image_button: Button
@export var color_button: ColorPickerButton

var localized_items_keys: Array[StringName] = [
	&"BACKGROUND_GREEN",
	&"BACKGROUND_BLUE",
	&"BACKGROUND_MAGENTA",
	&"BACKGROUND_TRANSPARENT",
	&"BACKGROUND_CUSTOM_COLOR",
	&"BACKGROUND_IMAGE"
	]

func _ready() -> void:
	NodeUtil.attach_locale(self, _update_types_text)

	for i in range(localized_items_keys.size()):
		add_item(tr(localized_items_keys[i]), i)

	select(Type.TRANSPARENT)
	_apply_visibility(get_selected_id())

func _on_item_selected(index: int) -> void:
	var type := get_item_id(index)
	SignalBus.background_type_changed.emit(type)
	if type == Type.CUSTOM_COLOR:
		SignalBus.background_color_changed.emit(color_button.color)
	elif type == Type.IMAGE:
		SignalBus.background_color_changed.emit(Color.WHITE)
	_apply_visibility(type)

func _apply_visibility(type: int) -> void:
	image_button.visible = type == Type.IMAGE
	color_button.visible = type == Type.CUSTOM_COLOR

func _update_types_text() -> void:
	for i in range(item_count):
		set_item_text(i, tr(localized_items_keys[i]))
