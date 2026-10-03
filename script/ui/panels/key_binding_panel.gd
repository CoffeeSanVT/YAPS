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

var _last_event: InputEvent
var _last_combo_keys: Array[int] = []

func _ready() -> void:
	SignalBus.remapping_success.connect(_on_remapping_success)

func setup_action_identity() -> void:
	var id := stable_id if not stable_id.is_empty() else tile_label.text
	action_name = action_prefix + "_" + id.to_lower()

	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"remapping_success", _on_remapping_success)
	InputMapper.cancel_remapping()

func _on_remapping_success(action: String, shortcut_key: String) -> void:
	if action != action_name:
		return

	shortcut_text.text = shortcut_key
	shortcut_text.release_focus()

	var events := InputMap.action_get_events(action_name)
	if not events.is_empty():
		var combo := InputMapper.get_captured_combo_keys()
		_last_event = events[0]
		_last_combo_keys = combo
		_check_conflict()
		shortcut_saved.emit(action_name, events[0], combo)

func set_shortcut(event: InputEvent) -> void:
	if event == null:
		return
	_last_event = event
	_last_combo_keys = []
	shortcut_text.text = event.as_text()
	_check_conflict()

func set_shortcut_combo(event: InputEvent, keys: Array[int]) -> void:
	if event == null:
		return
	_last_event = event
	_last_combo_keys = keys
	if keys.size() > 1:
		var parts: PackedStringArray = []
		for k in keys:
			parts.append(OS.get_keycode_string(k))
		shortcut_text.text = " + ".join(parts)
	else:
		shortcut_text.text = event.as_text()
	_check_conflict()

func _build_probe_trigger() -> BaseTrigger:
	var probe := KeyPressed.new()
	probe.shortcut = _last_event
	probe.combo_keys = _last_combo_keys
	return probe

func _check_conflict() -> void:
	if conflict_icon == null:
		return
	var conflicts := TriggerUtil.find_conflicts(_build_probe_trigger(), conflict_exclude_category, conflict_exclude_name)
	if conflicts.is_empty():
		conflict_icon.visible = false
		conflict_icon.tooltip_text = ""
	else:
		conflict_icon.visible = true
		conflict_icon.tooltip_text = tr(&"SHORTCUT_CONFLICT") % [
			TriggerUtil.format_conflict_tooltip(conflicts)
		]

func _on_line_edit_focus_entered() -> void:
	if action_name.is_empty():
		shortcut_text.release_focus()
		return
	ApplicationState.set_state(ApplicationState.AppState.RE_MAPPING_INPUT)
	SignalBus.remapping_started.emit(action_name)

func _on_button_pressed() -> void:
	if InputMap.has_action(action_name):
		InputMap.action_erase_events(action_name)
	shortcut_text.text = ""
	_last_event = null
	_last_combo_keys = []
	if conflict_icon != null:
		conflict_icon.visible = false
		conflict_icon.tooltip_text = ""
	shortcut_saved.emit(action_name, null, _last_combo_keys)
