extends Node

@export_category("Background")
@export var texture_rect: TextureRect
@export var color_rect: ColorRect

var custom_color: Color

func _enter_tree() -> void:
	NodeUtil.connect_once(SignalBus, &"background_type_changed", _on_background_type_changed)
	NodeUtil.connect_once(SignalBus, &"background_image_changed", _on_background_image_changed)
	NodeUtil.connect_once(SignalBus, &"background_color_changed", _on_background_color_changed)

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"background_type_changed", _on_background_type_changed)
	NodeUtil.safe_disconnect(SignalBus, &"background_image_changed", _on_background_image_changed)
	NodeUtil.safe_disconnect(SignalBus, &"background_color_changed", _on_background_color_changed)

func _on_background_type_changed(value: int) -> void:
	_update_background(value)

func _on_background_image_changed(image_texture: Texture2D) -> void:
	texture_rect.texture = image_texture

func _on_background_color_changed(color: Color) -> void:
	custom_color = color
	color_rect.color = custom_color

func _update_background(type: int) -> void:
	if type == BackgroundType.Type.IMAGE:
		texture_rect.show()
		color_rect.hide()
		return

	color_rect.show()
	texture_rect.hide()

	match type:
		BackgroundType.Type.GREEN:
			color_rect.color = Color.GREEN
		BackgroundType.Type.BLUE:
			color_rect.color = Color.BLUE
		BackgroundType.Type.MAGENTA:
			color_rect.color = Color.MAGENTA
		BackgroundType.Type.TRANSPARENT:
			color_rect.color = Color.TRANSPARENT
		BackgroundType.Type.CUSTOM_COLOR:
			color_rect.color = custom_color
