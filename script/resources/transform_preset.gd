class_name TransformPreset
extends Resource

@export_category("Transform Preset")
@export var preset_name: String = ""
@export var position: Vector2 = Vector2.ZERO
@export var scale_value: float = 0.0
@export var rotation: float = 0.0
@export var is_default: bool = false
@export var trigger: BaseTrigger = null

@export_category("Interpolation")
@export var interpolate: bool = true
@export var duration: float = 0.3
@export var trans_type: int = Tween.TRANS_EXPO
@export var ease_type: int = Tween.EASE_IN_OUT

func _init(p_name: String = "", pos: Vector2 = Vector2.ZERO, sc: float = 0.0, rot: float = 0.0) -> void:
	preset_name = p_name
	position = pos
	scale_value = sc
	rotation = rot
