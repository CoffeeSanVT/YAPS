extends ModelEntityPanel

signal changed(item: Item)

@export_category("UI References")
@export var thumbnail: TextureRect
@export var item_name_label: Label
@export var enable_toggle: CheckButton
@export var fixed_toggle: CheckButton
@export var trigger_option: OptionButton
@export var trigger_ui: Container
@export var rename_button: TextureButton
@export_category("UI Transform")
@export var position_x: SpinBox
@export var position_y: SpinBox
@export var scale_value: SpinBox
@export var rotation_value: SpinBox
@export var z_value: SpinBox
@export var anim_controls: ItemAnimControls
@export_category("Fade/hide")
@export var fade_spin: SpinBox
@export var hide_spin: SpinBox
@export_category("Twitch")
@export var twitch_foldable: TwitchEventFoldable

var item: Item

func _ready() -> void:
	_setup_rename_util(rename_button)
	if fade_spin != null:
		fade_spin.value_changed.connect(_on_fade_duration_changed)
	if hide_spin != null:
		hide_spin.value_changed.connect(_on_auto_hide_changed)
	NodeUtil.connect_once(twitch_foldable, &"twitch_event_changed", _on_twitch_event_changed)

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(item, &"enabled_changed", _on_item_enabled_changed)

func setup(new_item: Item) -> void:
	NodeUtil.safe_disconnect(item, &"transform_changed", _on_item_transform_changed)
	NodeUtil.safe_disconnect(item, &"enabled_changed", _on_item_enabled_changed)
	item = new_item
	_populate()
	if item != null:
		item.transform_changed.connect(_on_item_transform_changed)
		item.enabled_changed.connect(_on_item_enabled_changed)

func _populate() -> void:
	if item == null:
		return
	thumbnail.texture = item.load_image()
	item_name_label.text = String(item.state_name).capitalize()
	enable_toggle.set_pressed_no_signal(item.enabled)
	fixed_toggle.set_pressed_no_signal(item.is_fixed_to_model)
	if twitch_foldable != null:
		twitch_foldable.setup(item.twitch_event)
	_populate_transform()
	_populate_triggers()
	_populate_animation()

func _populate_transform() -> void:
	if item == null:
		return
	_mirror_transform_to_ui()
	if z_value != null:
		z_value.set_value_no_signal(item.z_index)

func _mirror_transform_to_ui() -> void:
	position_x.set_value_no_signal(item.position.x)
	position_y.set_value_no_signal(item.position.y)
	scale_value.set_value_no_signal(item.effective_scale())
	rotation_value.set_value_no_signal(item.rotation)

func _populate_triggers() -> void:
	var key_options := BaseTrigger.get_key_trigger_options()
	TriggerUtil.populate_trigger_options(trigger_option, key_options)
	trigger_option.selected = TriggerUtil.get_trigger_index(item.state_trigger, key_options)
	_refresh_trigger_ui(item.state_trigger)

func _refresh_trigger_ui(trigger: BaseTrigger) -> void:
	_show_trigger_ui(trigger, trigger_ui)
	_refresh_fade_and_hide_options()

func _refresh_fade_and_hide_options() -> void:
	var trigger := _settings_trigger()
	if trigger == null:
		trigger = BaseTrigger.new()
	if fade_spin != null:
		fade_spin.set_value_no_signal(trigger.fade_duration)
	if hide_spin != null:
		hide_spin.set_value_no_signal(trigger.auto_hide_after)

func _settings_trigger() -> BaseTrigger:
	if item == null:
		return null
	return item.state_trigger if item.state_trigger != null else item.twitch_event

func _on_fade_duration_changed(value: float) -> void:
	var trigger := _settings_trigger()
	if item == null or trigger == null:
		return
	trigger.fade_duration = value
	commit()

func _on_auto_hide_changed(value: float) -> void:
	var trigger := _settings_trigger()
	if item == null or trigger == null:
		return
	trigger.auto_hide_after = value
	item.update_auto_hide_timer()
	commit()

func _populate_animation() -> void:
	if item == null:
		return
	anim_controls.setup(item.get_animation_player(), item.animation_loop)

func _on_anim_loop_toggled(pressed: bool) -> void:
	if item == null:
		return
	item.animation_loop = pressed
	commit()

func _on_item_enabled_changed(value: bool) -> void:
	enable_toggle.set_pressed_no_signal(value)
	anim_controls.set_enabled(value)
	if item == null:
		return
	if value:
		item.play_animation()
	else:
		item.pause_animation()

func _on_enable_toggled(pressed: bool) -> void:
	if item == null:
		return
	item.set_enabled(pressed)

func _on_fixed_toggled(pressed: bool) -> void:
	if item == null:
		return
	item.is_fixed_to_model = pressed
	var main := get_tree().current_scene as DragAndDropManager
	if main != null:
		item.reparent_for_fixed(main.get_free_parent(), main.get_model_parent())
	commit()

func _on_trigger_selected(index: int) -> void:
	if item == null:
		return
	var trigger := TriggerUtil.trigger_from_index(index, BaseTrigger.get_key_trigger_options())
	item.set_trigger(trigger)
	_refresh_trigger_ui(trigger)
	commit()

func _on_twitch_event_changed(twitch_event: TwitchEvent) -> void:
	if item == null:
		return
	item.set_twitch_event(twitch_event)
	commit()
	changed.emit(item)

func _trigger_category() -> String:
	return TriggerUtil.CATEGORY_ITEM

func _trigger_stable_id() -> String:
	return item.state_name if item != null else ""

func _trigger_tile_label() -> Label:
	return item_name_label

func _trigger_action_prefix() -> String:
	return "item"

func _on_shortcut_saved(action_name: String, event: InputEvent, combo_keys: Array[int]) -> void:
	if item == null or item.state_trigger == null:
		return
	TriggerUtil.commit_shortcut(item.state_trigger, action_name, event, combo_keys)

func _on_rename_pressed() -> void:
	if item == null or ApplicationState.get_state() == ApplicationState.AppState.EDITING:
		return
	var target := item
	_rename_util.rename_property(item_name_label, target, &"state_name", _is_item_name_taken, RenameUtil.LabelMode.NONE, func(_new_name: String) -> void:
		changed.emit(target)
	)

func _is_item_name_taken(candidate: String) -> bool:
	return ModelLoader.model_loaded != null and ModelLoader.model_loaded.has_item_named(candidate, item)

func _on_delete_pressed() -> void:
	if item == null:
		return
	item.destroy()
	if ModelLoader.model_loaded != null:
		ModelLoader.model_loaded.items.erase(item)
		ModelLoader.save_model()
	changed.emit(item)
	SignalBus.items_changed.emit()

func _apply_transform_to_instance() -> void:
	if item == null:
		return
	item.apply_transform_to_instance()
	commit()

func _on_item_transform_changed() -> void:
	if item == null:
		return
	_mirror_transform_to_ui()

func _on_position_x_changed(value: float) -> void:
	_mutate_transform(func() -> void: item.position.x = value)

func _on_position_y_changed(value: float) -> void:
	_mutate_transform(func() -> void: item.position.y = value)

func _on_scale_changed(value: float) -> void:
	_mutate_transform(func() -> void: item.scale = Vector2(value, value))

func _on_rotation_changed(value: float) -> void:
	_mutate_transform(func() -> void: item.rotation = value)

func _on_z_changed(value: float) -> void:
	if item == null:
		return
	item.z_index = int(value)
	if z_value != null:
		z_value.set_value_no_signal(item.z_index)
	commit()

func _mutate_transform(mutate: Callable) -> void:
	if item == null:
		return
	mutate.call()
	_apply_transform_to_instance()
