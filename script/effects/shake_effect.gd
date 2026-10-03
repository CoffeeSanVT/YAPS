class_name ShakeEffect
extends MovementEffect

@export_category("Shake Effect")
@export var duration: float = 0.3
@export var amplitude: float = 8.0

func _init() -> void:
	effect_name = &"shake"
	ui_prefab = preload("uid://bfa8863lnksmh")

func _on_activate(target: Node) -> void:
	_prepare(target, &"position")
	_start_on(target, _apply_shake, duration, false)

func deactivate() -> void:
	_restore_base(false)

func _apply_shake(t: float) -> void:
	if not _target_valid():
		return
	var envelope := (1.0 - t) * (1.0 - t)
	var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amplitude * envelope
	_target.position = (_base_value as Vector2) + offset
