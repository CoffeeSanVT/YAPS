class_name KeyPressed
extends KeyTriggerBase

signal selection_requested

func _init() -> void:
	trigger_name = &"key_pressed"
	ui_prefab = load("uid://cgt1kypress00")

func _on_shortcut_pressed() -> void:
	if selection_requested.has_connections():
		selection_requested.emit()
	else:
		set_enabled(not enabled)
