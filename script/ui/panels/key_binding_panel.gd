class_name KeyBindingPanel
extends Control

signal shortcut_saved(action_name: String, event: InputEvent, combo_keys: Array[int])

@export_category("UI References")
@export var action_prefix: String
@export var stable_id: String
@export var tile_label: Label
@export var shortcut_text: LineEdit
@export var conflict_icon: TextureRect

var action_name: String
var conflict_exclude_name: String = ""
var conflict_exclude_category: String = ""

func _ready() -> void:
	shortcut_text.focus_exited.connect(_cancel_remapping)

func setup_action_identity() -> void:
	var id := stable_id if not stable_id.is_empty() else tile_label.text
	action_name = action_prefix + "_" + id.to_lower()

func _exit_tree() -> void:
	_cancel_remapping()

func _cancel_remapping() -> void:
	InputMapper.cancel_remapping(get_instance_id())

func _on_remapping_success(event: InputEventKey, combo: Array[int]) -> void:
	set_shortcut(event, combo, true)
	shortcut_text.release_focus()
	shortcut_saved.emit(action_name, event, combo)

func set_shortcut(event: InputEvent, keys: Array[int] = [], notify_conflict := false) -> void:
	if keys.size() > 1:
		var parts: PackedStringArray = []
		var key_event := event as InputEventKey
		var modifiers := key_event.get_modifiers_mask() if key_event != null else 0
		parts.append(OS.get_keycode_string(keys[0] | modifiers))
		for key: int in keys.slice(1):
			parts.append(OS.get_keycode_string(key))
		shortcut_text.text = " + ".join(parts)
	else:
		shortcut_text.text = event.as_text() if event != null else ""
	_check_conflict(event, keys, notify_conflict)

func _check_conflict(event: InputEvent, keys: Array[int], notify: bool) -> void:
	if conflict_icon == null:
		return
	var conflicts := TriggerUtil.find_conflicts(event, keys, conflict_exclude_category, conflict_exclude_name)
	if conflicts.is_empty():
		conflict_icon.visible = false
		conflict_icon.tooltip_text = ""
	else:
		var message: String = tr(&"SHORTCUT_CONFLICT") % [
			TriggerUtil.format_conflict_tooltip(conflicts)
		]
		conflict_icon.visible = true
		conflict_icon.tooltip_text = message
		if notify:
			SignalBus.shortcut_conflict_detected.emit(message)

func _on_line_edit_focus_entered() -> void:
	if action_name.is_empty():
		shortcut_text.release_focus()
		return
	InputMapper.start_remapping(get_instance_id(), _on_remapping_success)

func _on_button_pressed() -> void:
	var keys: Array[int] = []
	set_shortcut(null, keys)
	shortcut_saved.emit(action_name, null, keys)
