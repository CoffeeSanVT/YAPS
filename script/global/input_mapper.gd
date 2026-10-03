extends Node

signal action_just_pressed(action_name: String)
signal action_just_released(action_name: String)

var _last_action_name: String

var _pending_event: InputEventKey = null
var _held_keys: Dictionary = {}

const _MODIFIER_KEYS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]

func _ready() -> void:
	SignalBus.remapping_started.connect(func(action_name: String) -> void:
		_last_action_name = action_name
		_pending_event = null
		_held_keys.clear())
	ModelLoader.model_loaded_changed.connect(sync_global_shortcut_keys)
	SignalBus.model_triggers_changed.connect(sync_global_shortcut_keys, CONNECT_DEFERRED)
	SignalBus.items_changed.connect(sync_global_shortcut_keys, CONNECT_DEFERRED)
	SignalBus.remapping_success.connect(func(_a: String, _b: String) -> void: sync_global_shortcut_keys(), CONNECT_DEFERRED)

func _input(event: InputEvent) -> void:
	if _handle_remap_input(event):
		return
	_dispatch_actions(event)

func _handle_remap_input(event: InputEvent) -> bool:
	if ApplicationState.get_state() != ApplicationState.AppState.RE_MAPPING_INPUT or _last_action_name.is_empty():
		return false
	if not (event is InputEventKey):
		return true

	if event.pressed and event.keycode == KEY_ESCAPE:
		cancel_remapping()
		return true

	if event.pressed:
		if event.keycode in _MODIFIER_KEYS:
			return true
		_held_keys[event.keycode] = true
		if _pending_event == null:
			_pending_event = event
	else:
		_held_keys.erase(event.keycode)
		if _held_keys.is_empty() and _pending_event != null:
			_apply_remap(_pending_event)
			_pending_event = null
	return true

func _dispatch_actions(event: InputEvent) -> void:
	if event.is_echo():
		return
	if ApplicationState.get_state() == ApplicationState.AppState.LOADING:
		return

	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return

	var trigger_actions := KeyTriggerBase.registered_actions()
	if trigger_actions.is_empty():
		return
	for action: StringName in trigger_actions:
		if not InputMap.has_action(action):
			continue
		if event.is_action_pressed(action):
			action_just_pressed.emit(action)
		elif event.is_action_released(action):
			action_just_released.emit(action)

func get_captured_combo_keys() -> Array[int]:
	var keys: Array[int] = []
	for k: int in _held_keys.keys():
		keys.append(k)
	return keys

func sync_global_shortcut_keys() -> void:
	var keys: Dictionary = {}
	var profile := ModelLoader.model_loaded
	if profile != null:
		for emotion in profile.emotions:
			_collect_trigger_keys(emotion.trigger, keys)
		for item in profile.items:
			_collect_trigger_keys(item.state_trigger, keys)
		for preset in profile.transform_presets:
			_collect_trigger_keys(preset.trigger, keys)
	var global_input := get_node(^"/root/GlobalInput")
	global_input.SetAllowedKeys(keys.keys())

func _collect_trigger_keys(trigger: BaseTrigger, keys: Dictionary) -> void:
	var key_trigger := trigger as KeyTriggerBase
	if key_trigger == null:
		return
	var key_event := key_trigger.shortcut as InputEventKey
	if key_event != null:
		var keycode: int = key_event.keycode
		if keycode == KEY_NONE:
			keycode = key_event.physical_keycode
		if keycode != KEY_NONE:
			keys[keycode] = true
	for combo_key: int in key_trigger.combo_keys:
		if combo_key != KEY_NONE:
			keys[combo_key] = true

func cancel_remapping() -> void:
	if ApplicationState.get_state() != ApplicationState.AppState.RE_MAPPING_INPUT or _last_action_name.is_empty():
		return
	_last_action_name = ""
	_pending_event = null
	_held_keys.clear()
	ApplicationState.set_state(ApplicationState.AppState.NORMAL)

func _apply_remap(event: InputEventKey) -> void:
	if not InputMap.has_action(_last_action_name):
		InputMap.add_action(_last_action_name)
	InputMap.action_erase_events(_last_action_name)
	InputMap.action_add_event(_last_action_name, event)
	SignalBus.remapping_success.emit(_last_action_name, event.as_text())
	_last_action_name = ""
	ApplicationState.set_state(ApplicationState.AppState.NORMAL)
