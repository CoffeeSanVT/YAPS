class_name KeyPressed
extends KeyTriggerBase

var _combo_active := false

func _init() -> void:
	trigger_name = &"key_pressed"
	ui_prefab = preload("uid://cgt1kypress00")

func tick(_delta: float, _current_state: ModelStateEntry) -> void:
	if _is_single_key():
		return
	var all_pressed := _combo_keys_pressed()
	if all_pressed and not _combo_active:
		_combo_active = true
		set_enabled(not enabled)
	elif not all_pressed:
		_combo_active = false

func _on_action_pressed(action_name: String) -> void:
	if action_name == action:
		set_enabled(not enabled)
