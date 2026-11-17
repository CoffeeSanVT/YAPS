extends Node

signal key_changed(event: InputEventKey, allow_press: bool)
signal keys_reset

const _MODIFIER_KEYS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]

var _remap_owner: int
var _remap_callback := Callable()
var _pending_event: InputEventKey
var _captured_keys: Array[int] = []
var _remap_keys: Array[int] = []
var _down_keys: Dictionary[int, bool] = {}

func _ready() -> void:
	ModelLoader.model_loaded_changed.connect(_on_model_changed)
	SignalBus.model_triggers_changed.connect(sync_global_shortcut_keys, CONNECT_DEFERRED)
	SignalBus.items_changed.connect(sync_global_shortcut_keys, CONNECT_DEFERRED)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset_keys()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.is_echo():
		return

	var key_event := event as InputEventKey
	var key := physical_key(key_event)
	if key == KEY_NONE:
		return
	if key_event.pressed:
		if _down_keys.has(key):
			return
		_down_keys[key] = true
	else:
		_down_keys.erase(key)

	var state := ApplicationState.get_state()
	if state == ApplicationState.AppState.RE_MAPPING_INPUT and _remap_owner != 0:
		_handle_remap_input(key_event, key)
		return

	var focused := get_viewport().gui_get_focus_owner()
	var allow_press := key_event.pressed and state != ApplicationState.AppState.LOADING \
		and not focused is LineEdit and not focused is TextEdit
	key_changed.emit(key_event, allow_press)

func physical_key(event: InputEventKey) -> int:
	return event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode

func is_key_down(key: int) -> bool:
	return _down_keys.has(key)

func start_remapping(owner: int, callback: Callable) -> void:
	_remap_owner = owner
	_remap_callback = callback
	_clear_remap_capture()
	keys_reset.emit()
	ApplicationState.set_state(ApplicationState.AppState.RE_MAPPING_INPUT)

func cancel_remapping(owner: int) -> void:
	if _remap_owner != owner:
		return
	_remap_owner = 0
	_remap_callback = Callable()
	_clear_remap_capture()
	if ApplicationState.get_state() == ApplicationState.AppState.RE_MAPPING_INPUT:
		ApplicationState.set_state(ApplicationState.AppState.NORMAL)

func _clear_remap_capture() -> void:
	_pending_event = null
	_captured_keys.clear()
	_remap_keys.clear()

func _handle_remap_input(event: InputEventKey, key: int) -> void:
	get_viewport().set_input_as_handled()
	if event.pressed and key == KEY_ESCAPE:
		var focused := get_viewport().gui_get_focus_owner()
		cancel_remapping(_remap_owner)
		if focused != null:
			focused.release_focus()
		return
	if key in _MODIFIER_KEYS:
		return

	if event.pressed:
		_remap_keys.append(key)
		# Capture the largest set of keys held together, with its modifiers.
		if _remap_keys.size() > _captured_keys.size():
			_captured_keys.assign(_remap_keys)
			_pending_event = event.duplicate() as InputEventKey
			_pending_event.physical_keycode = _captured_keys[0]
			_pending_event.keycode = KEY_NONE
			_pending_event.key_label = KEY_NONE
		return

	_remap_keys.erase(key)
	if _remap_keys.is_empty() and _pending_event != null:
		var callback := _remap_callback
		var binding := _pending_event
		var combo: Array[int] = []
		if _captured_keys.size() > 1:
			combo.assign(_captured_keys)
		cancel_remapping(_remap_owner)
		if callback.is_valid():
			callback.call(binding, combo)

func _on_model_changed() -> void:
	_reset_keys()
	sync_global_shortcut_keys()

func _reset_keys() -> void:
	_down_keys.clear()
	keys_reset.emit()

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
		for code: int in [key_event.keycode, key_event.physical_keycode, key_event.key_label]:
			if code != KEY_NONE:
				keys[code] = true
	for combo_key: int in key_trigger.combo_keys:
		if combo_key != KEY_NONE:
			keys[combo_key] = true
