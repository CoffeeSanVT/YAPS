class_name KeyHolding
extends KeyTriggerBase

func _init() -> void:
	trigger_name = &"key_holding"
	ui_prefab = preload("uid://cgt1kyholdd00")

func _listens_release() -> bool:
	return true

func tick(_delta: float, _current_state: ModelStateEntry) -> void:
	if _is_single_key():
		return
	set_enabled(_combo_keys_pressed())

func _on_action_pressed(action_name: String) -> void:
	if action_name == action:
		set_enabled(true)

func _on_action_released(action_name: String) -> void:
	if action_name == action:
		set_enabled(false)
