class_name DarkenEffect
extends FilterEffect

const FILTER_MODE_DARKEN: int = 2

@export_category("Darken Effect")
@export var duration: float = 0.3
@export var intensity: float = 0.5

func _init() -> void:
	effect_name = &"darken"
	ui_prefab = preload("uid://b8jn0h5wlt3wd")

func active_for_talking(is_talking: bool) -> bool:
	return not is_talking

func _on_activate(target: Node) -> void:
	_target = target
	_fade_filter(FILTER_MODE_DARKEN, intensity, duration)

func deactivate() -> void:
	_fade_filter(FILTER_MODE_DARKEN, 0.0, duration)
