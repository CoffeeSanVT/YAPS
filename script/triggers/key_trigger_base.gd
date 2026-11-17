class_name KeyTriggerBase
extends BaseTrigger

@export_category("Trigger")
@export var action: StringName
@export var shortcut: InputEvent
@export var combo_keys: Array[int] = []

var _pressed_key := KEY_NONE

func activate() -> void:
	NodeUtil.connect_once(InputMapper, &"key_changed", _on_key_changed)
	NodeUtil.connect_once(InputMapper, &"keys_reset", _reset_shortcut)

func deactivate() -> void:
	NodeUtil.safe_disconnect(InputMapper, &"key_changed", _on_key_changed)
	NodeUtil.safe_disconnect(InputMapper, &"keys_reset", _reset_shortcut)
	_reset_shortcut()

func configure_shortcut(action_name: String, event: InputEvent, keys: Array[int]) -> void:
	_reset_shortcut()
	action = action_name
	shortcut = event
	combo_keys = keys

func _on_key_changed(event: InputEventKey, allow_press: bool) -> void:
	var binding := shortcut as InputEventKey
	var key := InputMapper.physical_key(event)
	var is_combo := combo_keys.size() > 1
	var matches_key := key in combo_keys if is_combo else _matches_key(binding, event)

	if _pressed_key != KEY_NONE:
		if not event.pressed and (key == _pressed_key or (is_combo and matches_key) \
				or _released_required_modifier(binding, key)):
			_reset_shortcut()
		return

	if not allow_press or not matches_key or not _modifiers_match(binding, event):
		return
	if is_combo and not combo_keys.all(InputMapper.is_key_down):
		return
	_pressed_key = key
	_on_shortcut_pressed()

func _reset_shortcut() -> void:
	if _pressed_key != KEY_NONE:
		_pressed_key = KEY_NONE
		_on_shortcut_released()

static func _matches_key(binding: InputEventKey, event: InputEventKey) -> bool:
	if binding == null:
		return false
	if binding.keycode != KEY_NONE:
		return binding.keycode == event.keycode
	if binding.physical_keycode != KEY_NONE:
		return binding.physical_keycode == event.physical_keycode
	return binding.key_label != KEY_NONE and binding.key_label == event.key_label

static func _modifiers_match(binding: InputEventKey, event: InputEventKey) -> bool:
	return binding == null or binding.get_modifiers_mask() == event.get_modifiers_mask()

static func _released_required_modifier(binding: InputEventKey, key: int) -> bool:
	if binding == null:
		return false
	match key:
		KEY_SHIFT:
			return binding.shift_pressed
		KEY_CTRL:
			return binding.ctrl_pressed
		KEY_ALT:
			return binding.alt_pressed
		KEY_META:
			return binding.meta_pressed
	return false

func _on_shortcut_pressed() -> void:
	pass

func _on_shortcut_released() -> void:
	pass
