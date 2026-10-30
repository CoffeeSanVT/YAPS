class_name ItemPresetPanel
extends PresetPanel

var item: Item
var expression_option: OptionButton

func _ready() -> void:
	super()
	_setup_expression_options()
	SignalBus.states_changed.connect(_populate_expression_options)

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"states_changed", _populate_expression_options)
	super()

func setup_item(new_preset: ItemTransformPreset, new_item: Item) -> void:
	item = new_item
	setup(new_preset)

func _populate() -> void:
	super()
	_populate_expression_options()

func _setup_expression_options() -> void:
	var expression_row := default_toggle.get_parent() as HBoxContainer
	var expression_label := expression_row.get_child(0) as Label
	expression_label.text = tr(&"EXPRESSION")
	expression_label.set_meta(&"localization_key", &"EXPRESSION")
	default_toggle.visible = false

	expression_option = OptionButton.new()
	expression_option.custom_minimum_size = Vector2(120.0, 0.0)
	expression_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	expression_option.fit_to_longest_item = false
	expression_option.item_selected.connect(_on_expression_selected)
	expression_row.add_child(expression_option)

	var trigger_foldable := trigger_ui.get_parent().get_parent() as Control
	trigger_foldable.visible = false
	_populate_expression_options()

func _populate_expression_options() -> void:
	if expression_option == null:
		return
	var selected_name := ""
	if preset is ItemTransformPreset:
		selected_name = (preset as ItemTransformPreset).expression_name

	expression_option.clear()
	expression_option.add_item(tr(&"NONE"))
	expression_option.set_item_metadata(0, "")
	var selected_index := 0
	var seen: Dictionary[String, bool] = {}
	var excluding := preset as ItemTransformPreset
	if ModelLoader.model_loaded != null:
		for entry in ModelLoader.model_loaded.all_entries():
			var expression_name := String(entry.state_name)
			var key := expression_name.to_lower()
			if seen.has(key):
				continue
			seen[key] = true
			var index := expression_option.item_count
			expression_option.add_item(expression_name.capitalize())
			expression_option.set_item_metadata(index, expression_name)
			if item != null and item.has_preset_for_expression(expression_name, excluding):
				expression_option.set_item_disabled(index, true)
			if key == selected_name.to_lower():
				selected_index = index

	if selected_index == 0 and not selected_name.is_empty():
		expression_option.add_item(selected_name.capitalize())
		selected_index = expression_option.item_count - 1
		expression_option.set_item_metadata(selected_index, selected_name)
	expression_option.select(selected_index)

func _on_expression_selected(index: int) -> void:
	if item == null or not preset is ItemTransformPreset:
		return
	var expression_name := String(expression_option.get_item_metadata(index))
	if item.has_preset_for_expression(expression_name, preset as ItemTransformPreset):
		_populate_expression_options()
		return
	(preset as ItemTransformPreset).expression_name = expression_name
	commit()
	_refresh_sibling_options()
	var machine := get_tree().get_first_node_in_group(&"model_state_machine") as ModelStateMachine
	if machine != null:
		item.apply_expression(machine.current_entry.state_name if machine.current_entry != null else "")

func refresh_expression_options() -> void:
	_populate_expression_options()

func _refresh_sibling_options() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for child in parent.get_children():
		if child is ItemPresetPanel and child != self:
			(child as ItemPresetPanel).refresh_expression_options()

func _is_preset_name_taken(candidate: String) -> bool:
	return item != null and item.has_preset_named(candidate, preset as ItemTransformPreset)

func _on_locale_change() -> void:
	super()
	_populate_expression_options()
