class_name KeyTriggerBase
extends BaseTrigger

const TAG := "[KeyTriggerBase] "

@export_category("Trigger")
@export var action: StringName
@export var shortcut: InputEvent
@export var combo_keys: Array[int] = []

static var _action_refs: Dictionary[StringName, int] = {}

var _action_acquired := false
var _acquired_action: StringName

func activate() -> void:
	_register_shortcut_action()
	NodeUtil.connect_once(InputMapper, &"action_just_pressed", _on_action_pressed)
	if _listens_release():
		NodeUtil.connect_once(InputMapper, &"action_just_released", _on_action_released)

func deactivate() -> void:
	_release_shortcut_action()
	NodeUtil.safe_disconnect(InputMapper, &"action_just_pressed", _on_action_pressed)
	NodeUtil.safe_disconnect(InputMapper, &"action_just_released", _on_action_released)

func sync_action_identity(action_name: String) -> void:
	if action_name.is_empty() or action == action_name:
		return
	action = action_name
	if _action_acquired:
		_register_shortcut_action()

func _listens_release() -> bool:
	return false

func _on_action_pressed(_action_name: String) -> void:
	pass

func _on_action_released(_action_name: String) -> void:
	pass

func _register_shortcut_action() -> void:
	if not (combo_keys.size() <= 1 and shortcut != null):
		return
	if _action_acquired:
		if _acquired_action == action and InputMap.action_has_event(action, shortcut):
			return
		_release_shortcut_action()
	_action_acquired = true
	_acquired_action = action
	_acquire_action(action)
	if not InputMap.action_has_event(action, shortcut):
		InputMap.action_add_event(action, shortcut)

func _release_shortcut_action() -> void:
	if not _action_acquired:
		return
	_action_acquired = false
	_release_action(_acquired_action)
	_acquired_action = &""

static func _acquire_action(action_name: StringName) -> void:
	_action_refs[action_name] = _action_refs.get(action_name, 0) + 1
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

static func _release_action(action_name: StringName) -> void:
	if not _action_refs.has(action_name):
		push_warning(TAG + "Release without acquire for action '%s'." % [action_name])
		return
	var refs: int = _action_refs[action_name] - 1
	if refs > 0:
		_action_refs[action_name] = refs
		return
	_action_refs.erase(action_name)
	if InputMap.has_action(action_name):
		InputMap.erase_action(action_name)

static func registered_actions() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_action_refs.keys())
	return result

func _combo_keys_pressed() -> bool:
	return combo_keys.all(func(key_code: int) -> bool: 
		return Input.is_physical_key_pressed(key_code))

func _is_single_key() -> bool:
	return combo_keys.size() <= 1
