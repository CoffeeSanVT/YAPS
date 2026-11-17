class_name TriggerUtil

const CATEGORY_EMOTION := "Emotion"
const CATEGORY_ITEM := "Item"
const CATEGORY_PRESET := "Preset"


static func instantiate_trigger_ui(ui_prefab: PackedScene, container: Container, trigger: BaseTrigger, configure_key_bind: Callable) -> Node:
	var warning_context := "null"
	if trigger != null:
		warning_context = "trigger '%s'" % trigger.trigger_name
	var ui := NodeUtil.instantiate_into(ui_prefab, container, warning_context)
	if ui == null:
		return null
	if ui is KeyBindingPanel:
		var key_bind := ui as KeyBindingPanel
		if configure_key_bind.is_valid():
			configure_key_bind.call(key_bind)
		_apply_saved_shortcut(key_bind, trigger)
	return ui

static func setup_key_bind(key_bind: KeyBindingPanel, category: String, stable_id: String, tile_label: Label, on_shortcut_saved: Callable, action_prefix: String = "") -> void:
	if not action_prefix.is_empty():
		key_bind.action_prefix = action_prefix
	key_bind.tile_label = tile_label
	key_bind.stable_id = stable_id
	key_bind.conflict_exclude_category = category
	key_bind.conflict_exclude_name = stable_id
	key_bind.shortcut_saved.connect(on_shortcut_saved)
	key_bind.setup_action_identity()

static func _apply_saved_shortcut(key_bind: KeyBindingPanel, trigger: BaseTrigger) -> void:
	var key_trigger := trigger as KeyTriggerBase
	if key_trigger == null:
		return
	key_bind.set_shortcut(key_trigger.shortcut, key_trigger.combo_keys)

static func apply_shortcut_to_trigger(trigger: BaseTrigger, action_name: String, event: InputEvent, combo_keys: Array[int]) -> void:
	var key_trigger := trigger as KeyTriggerBase
	if key_trigger == null:
		return
	key_trigger.configure_shortcut(action_name, event, combo_keys)

static func commit_shortcut(trigger: BaseTrigger, action_name: String, event: InputEvent, combo_keys: Array[int]) -> void:
	apply_shortcut_to_trigger(trigger, action_name, event, combo_keys)
	trigger.activate()
	ModelLoader.save_model()
	InputMapper.sync_global_shortcut_keys()

static func get_trigger_index(trigger: BaseTrigger, options: Array[Dictionary]) -> int:
	if trigger == null or trigger.trigger_name == &"":
		return 0
	for i in options.size():
		if options[i].id == trigger.trigger_name:
			return i + 1
	return 0

static func populate_trigger_options(option: OptionButton, options: Array[Dictionary]) -> void:
	option.clear()
	option.add_item(TranslationServer.translate(&"NONE"))
	for candidate in options:
		option.add_item(BaseTrigger.localize_name(candidate.id))

static func trigger_from_index(index: int, options: Array[Dictionary]) -> BaseTrigger:
	if index <= 0 or index - 1 >= options.size():
		return null
	var script: GDScript = options[index - 1].script
	return script.new()



static func _key_signature(shortcut: InputEvent, combo_keys: Array[int]) -> String:
	var event := shortcut as InputEventKey
	var modifiers := event.get_modifiers_mask() if event != null else 0
	var keys: Array[int] = []
	if combo_keys.size() > 1:
		for key: int in combo_keys:
			keys.append(_logical_key(key))
	elif event != null:
		if event.keycode != KEY_NONE:
			keys.append(event.keycode)
		elif event.physical_keycode != KEY_NONE:
			keys.append(_logical_key(event.physical_keycode))
		elif event.key_label != KEY_NONE:
			return "label:%d:%d" % [modifiers, event.key_label]
	if not keys.is_empty():
		keys.sort()
		return "%d:%s" % [modifiers, str(keys)]
	return ""

static func _logical_key(physical_key: int) -> int:
	var key := DisplayServer.keyboard_get_keycode_from_physical(physical_key)
	return key if key != KEY_NONE else physical_key

static func _collect_key_triggers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var model := ModelLoader.model_loaded
	if model == null:
		return result

	var sources := [
		[CATEGORY_EMOTION, model.emotions, "trigger", "emotion_name"],
		[CATEGORY_ITEM, model.items, "state_trigger", "state_name"],
		[CATEGORY_PRESET, model.transform_presets, "trigger", "preset_name"],
	]
	for source: Array in sources:
		for entry: Object in source[1]:
			var trigger := entry.get(source[2]) as KeyTriggerBase if entry != null else null
			if trigger == null:
				continue
			var sig := _key_signature(trigger.shortcut, trigger.combo_keys)
			if sig.is_empty():
				continue
			result.append({
				"signature": sig,
				"category": source[0],
				"name": entry.get(source[3]),
			})

	return result

static func find_conflicts(shortcut: InputEvent, combo_keys: Array[int], ignore_category: String, ignore_name: String) -> Array[String]:
	var sig := _key_signature(shortcut, combo_keys)
	if sig.is_empty():
		return []
	var conflicts: Array[String] = []
	for owner in _collect_key_triggers():
		if owner["signature"] != sig:
			continue
		if not ignore_category.is_empty() and owner["category"] == ignore_category \
				and not ignore_name.is_empty() and owner["name"].to_lower() == ignore_name.to_lower():
			continue
		conflicts.append(_describe_owner(owner))
	return conflicts

static func _describe_owner(owner: Dictionary) -> String:
	return "%s '%s'" % [owner["category"], owner["name"]]

static func format_conflict_tooltip(conflicts: Array[String]) -> String:
	if conflicts.is_empty():
		return ""
	var lines: PackedStringArray = []
	for conflict in conflicts:
		lines.append("- " + conflict)
	return "\n".join(lines)
