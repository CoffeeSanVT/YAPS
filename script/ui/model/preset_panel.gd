class_name PresetPanel
extends ModelEntityPanel

signal apply_requested(preset: TransformPreset)
signal update_requested(preset: TransformPreset)
signal delete_requested(preset: TransformPreset)

@export_category("UI References")
@export var name_label: Label
@export var default_toggle: CheckButton
@export var trigger_option: OptionButton
@export var trigger_ui: VBoxContainer
@export var interpolate_toggle: CheckButton
@export var duration_spin: SpinBox
@export var transition_option: OptionButton
@export var ease_option: OptionButton

const TRANSITION_KEYS: Array[StringName] = [
	&"TRANS_LINEAR", &"TRANS_SINE", &"TRANS_QUINT", &"TRANS_QUART", &"TRANS_QUAD",
	&"TRANS_EXPO", &"TRANS_ELASTIC", &"TRANS_CUBIC", &"TRANS_CIRC", &"TRANS_BACK", &"TRANS_BOUNCE",
]
const EASE_KEYS: Array[StringName] = [&"EASE_IN", &"EASE_OUT", &"EASE_IN_OUT", &"EASE_OUT_IN"]

var preset: TransformPreset

func _ready() -> void:
	_setup_rename_util(null)
	NodeUtil.attach_locale(self, _on_locale_change)

func _process(delta: float) -> void:
	if preset != null and preset.trigger != null:
		preset.trigger.tick(delta, null)

func _exit_tree() -> void:
	_deactivate_trigger()

func setup(new_preset: TransformPreset) -> void:
	if preset != null and preset.trigger != null:
		_deactivate_trigger()
	preset = new_preset
	_populate()

func _populate() -> void:
	if preset == null:
		return
	name_label.text = preset.preset_name
	default_toggle.set_pressed_no_signal(preset.is_default)
	_populate_trigger_options()
	_update_trigger_panel()
	_populate_interpolation_options()
	interpolate_toggle.set_pressed_no_signal(preset.interpolate)
	duration_spin.set_value_no_signal(preset.duration)
	transition_option.select(preset.trans_type)
	ease_option.select(preset.ease_type)
	_update_interpolation_enabled()

func _populate_interpolation_options() -> void:
	if transition_option.item_count == 0:
		for key in TRANSITION_KEYS:
			transition_option.add_item(tr(key))
	if ease_option.item_count == 0:
		for key in EASE_KEYS:
			ease_option.add_item(tr(key))

func _populate_trigger_options() -> void:
	var key_options := BaseTrigger.get_key_trigger_options()
	var selected := TriggerUtil.get_trigger_index(preset.trigger, key_options)
	TriggerUtil.populate_trigger_options(trigger_option, key_options)
	trigger_option.selected = selected

func _on_locale_change() -> void:
	if preset != null:
		_populate_trigger_options()
	for i in TRANSITION_KEYS.size():
		if i < transition_option.item_count:
			transition_option.set_item_text(i, tr(TRANSITION_KEYS[i]))
	for i in EASE_KEYS.size():
		if i < ease_option.item_count:
			ease_option.set_item_text(i, tr(EASE_KEYS[i]))

func _on_interpolate_toggled(pressed: bool) -> void:
	if preset == null:
		return
	preset.interpolate = pressed
	_update_interpolation_enabled()
	commit()

func _on_duration_changed(value: float) -> void:
	if preset == null:
		return
	preset.duration = value
	commit()

func _on_transition_selected(index: int) -> void:
	if preset == null:
		return
	preset.trans_type = index
	commit()

func _on_ease_selected(index: int) -> void:
	if preset == null:
		return
	preset.ease_type = index
	commit()

func _update_interpolation_enabled() -> void:
	if preset == null:
		return
	var enabled := preset.interpolate
	duration_spin.editable = enabled
	transition_option.disabled = not enabled
	ease_option.disabled = not enabled

func _on_default_toggled(pressed: bool) -> void:
	if preset == null or ModelLoader.model_loaded == null:
		return
	preset.is_default = pressed
	if pressed:
		for other in ModelLoader.model_loaded.transform_presets:
			if other != preset:
				other.is_default = false
	commit()
	SignalBus.presets_changed.emit()

func _on_apply_pressed() -> void:
	apply_requested.emit(preset)

func _on_update_pressed() -> void:
	update_requested.emit(preset)

func _on_delete_pressed() -> void:
	delete_requested.emit(preset)

func _on_rename_pressed() -> void:
	if preset == null:
		return
	_rename_util.rename_property(name_label, preset, &"preset_name", _is_preset_name_taken, RenameUtil.LabelMode.RAW)

func _is_preset_name_taken(candidate: String) -> bool:
	return ModelLoader.model_loaded != null and ModelLoader.model_loaded.has_preset_named(candidate, preset)

func _deactivate_trigger() -> void:
	if preset == null or preset.trigger == null:
		return
	preset.trigger.unbind_changed(_on_trigger_enabled)

func _on_trigger_selected(index: int) -> void:
	if preset == null:
		return
	var trigger := TriggerUtil.trigger_from_index(index, BaseTrigger.get_key_trigger_options())
	if trigger != null:
		var new_key := trigger as KeyTriggerBase
		if new_key != null:
			var old_key := preset.trigger as KeyTriggerBase
			if old_key != null:
				new_key.action = old_key.action
				new_key.shortcut = old_key.shortcut
				new_key.combo_keys = old_key.combo_keys.duplicate()
			else:
				new_key.action = StringName("preset_" + preset.preset_name.to_lower())
	_set_trigger(trigger)

func _set_trigger(new_trigger: BaseTrigger) -> void:
	if new_trigger == preset.trigger:
		return
	_deactivate_trigger()
	var old := preset.trigger
	preset.trigger = new_trigger
	if old != null:
		old.deactivate()
	_update_trigger_panel()
	commit()
	InputMapper.sync_global_shortcut_keys()

func _activate_trigger() -> void:
	if preset == null or preset.trigger == null:
		return
	preset.trigger.bind_changed(_on_trigger_enabled)

func _update_trigger_panel() -> void:
	_clear_trigger_ui()
	if preset.trigger == null:
		return
	_activate_trigger()
	_refresh_trigger_panel_ui()

func _refresh_trigger_panel_ui() -> void:
	_show_trigger_ui(preset.trigger, trigger_ui)

func _clear_trigger_ui() -> void:
	if _trigger_slot != null:
		_trigger_slot.clear()

func _on_shortcut_saved(action_name: String, event: InputEvent, combo_keys: Array[int]) -> void:
	if preset == null or preset.trigger == null:
		return
	TriggerUtil.commit_shortcut(preset.trigger, action_name, event, combo_keys)

func _on_trigger_enabled(_trigger: BaseTrigger) -> void:
	if _trigger.enabled:
		apply_requested.emit(preset)

func _trigger_category() -> String:
	return TriggerUtil.CATEGORY_PRESET

func _trigger_stable_id() -> String:
	return preset.preset_name if preset != null else ""

func _trigger_tile_label() -> Label:
	return name_label

func _trigger_action_prefix() -> String:
	return "preset"

