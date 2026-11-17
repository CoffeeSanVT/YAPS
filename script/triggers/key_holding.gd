class_name KeyHolding
extends KeyTriggerBase

func _init() -> void:
	trigger_name = &"key_holding"
	ui_prefab = load("uid://cgt1kyholdd00")

func _on_shortcut_pressed() -> void:
	set_enabled(true)

func _on_shortcut_released() -> void:
	set_enabled(false)
