class_name BounceEffect
extends BaseEffect

@export_category("Bounce Effect")
@export var duration: float = 0.35
@export var intensity: float = 0.06

func _init() -> void:
	effect_name = &"bounce"
	ui_prefab = preload("uid://bfarhr6jnksmh")

func activate(target: Node) -> void:
	_prepare(target, &"scale")
	_start_on(_apply_bounce_scale, duration, false)

func retrigger_on_talking() -> bool:
	return true

func deactivate() -> void:
	_restore_base(false)

func _apply_bounce_scale(t: float) -> void:
	if not _target_valid():
		return
	var envelope := exp(-4.0 * t)
	var wobble := sin(t * PI * 5.0) * envelope
	_target.scale = (_base_value as Vector2) * Vector2(1.0 + wobble * intensity, 1.0 - wobble * intensity)
