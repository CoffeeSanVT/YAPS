class_name WarpEffect
extends FilterEffect

@export_category("Warp Effect")
@export var duration: float = 0.5
@export var intensity: float = 1.0

const FILTER_MODE_WARP: int = 1

func _init() -> void:
	effect_name = &"warp"
	ui_prefab = preload("uid://bfbd2o8lokqmh")

func _on_activate(target: Node) -> void:
	_target = target
	_stop_tween()
	_set_warp(0.0)

	_tween = target.create_tween()
	_tween.tween_method(_set_warp, 0.0, intensity, duration * 0.5)
	_tween.tween_method(_set_warp, intensity, 0.0, duration * 0.5)

func deactivate() -> void:
	_stop_tween()
	_set_warp(0.0)

func _set_warp(value: float) -> void:
	_set_filter(FILTER_MODE_WARP, value)
