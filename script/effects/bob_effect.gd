class_name BobEffect
extends MovementEffect

const RETURN_DURATION := 0.25

@export_category("Bob Effect")
@export var duration: float = 1.2
@export var amplitude: float = 6.0

func _init() -> void:
	effect_name = &"bob"
	ui_prefab = preload("uid://dwky1prn6cbhx")

func _on_activate(target: Node) -> void:
	_prepare(target, &"position")
	_start_on(target, _apply_bob, duration, true)

func deactivate() -> void:
	_restore_base(true, RETURN_DURATION)

func _apply_bob(t: float) -> void:
	if not _target_valid():
		return
	_target.position = (_base_value as Vector2) + Vector2(0.0, -sin(t * TAU) * amplitude)
