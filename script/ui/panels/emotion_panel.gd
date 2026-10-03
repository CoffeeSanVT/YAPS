extends ModelEntityPanel

signal trigger_option_changed(emotion_name: String, trigger: BaseTrigger)

const EMOTION_EXCLUDED_TRIGGERS: Array[StringName] = [&"start_talking", &"twitch_event"]

@export_category("Trigger")
@export var trigger_foldable: FoldableContainer
@export var options_button: OptionButton
@export var trigger_options: Container

@export_category("Twitch")
@export var twitch_foldable: TwitchEventFoldable

@export_category("Effects")
@export var effects_hint: Label
@export var movement_option: OptionButton
@export var movement_options: Container
@export var filter_option: OptionButton
@export var filter_options: Container

@export_category("Actions")
@export var tile_text: Label
@export var rename_button: TextureButton
@export var default_button: CheckButton

var current_emotion: ModelEmotion
var current_trigger: BaseTrigger
var _loading: bool = false
var _is_neutral: bool = false

var _volume_min: SpinBox
var _volume_max: SpinBox
var _volume_delay: SpinBox
var _volume_activation: SpinBox

var _trigger_options: Array[Dictionary] = []
var _slots := EffectSlotPair.new()

func _ready() -> void:
	_setup_rename_util(rename_button)
	_slots.setup(movement_option, movement_options, filter_option, filter_options)
	_slots.param_changed.connect(_on_slot_param_changed)
	_populate_options()
	NodeUtil.attach_locale(self, _on_locale_change)
	NodeUtil.connect_once(twitch_foldable, &"twitch_event_changed", _on_twitch_event_changed)

func set_emotion(emotion: ModelEmotion) -> void:
	_is_neutral = false
	current_emotion = emotion
	tile_text.text = String(emotion.emotion_name).capitalize()
	set_trigger(emotion.trigger)
	set_emotion_effect(emotion)
	if twitch_foldable != null:
		twitch_foldable.setup(emotion.twitch_event)
	_update_default_button_state()

func set_neutral(emotion: ModelEmotion) -> void:
	_is_neutral = true
	current_emotion = emotion
	tile_text.text = tr(&"NEUTRAL")
	rename_button.visible = false
	default_button.visible = false
	if trigger_foldable != null:
		trigger_foldable.visible = false
	if twitch_foldable != null:
		twitch_foldable.visible = false
	set_emotion_effect(emotion)

func _update_default_button_state() -> void:
	var is_default := false
	if current_emotion != null and ModelLoader.model_loaded != null:
		is_default = ModelLoader.model_loaded.default_emotion.to_lower() == current_emotion.emotion_name.to_lower()
	default_button.set_pressed_no_signal(is_default)

func _on_locale_change() -> void:
	if _is_neutral:
		tile_text.text = tr(&"NEUTRAL")
	if options_button.item_count > 0:
		options_button.set_item_text(0, tr(&"NONE"))
	for i in _trigger_options.size():
		options_button.set_item_text(i + 1, BaseTrigger.localize_name(_trigger_options[i].id))
	_slots.refresh_texts()
	_update_effects_hint()

func _populate_options() -> void:
	if options_button.item_count == 0:
		_trigger_options = BaseTrigger.get_available_options()
		var filtered: Array[Dictionary] = []
		for option in _trigger_options:
			if not EMOTION_EXCLUDED_TRIGGERS.has(option.id):
				filtered.append(option)
		_trigger_options = filtered
		TriggerUtil.populate_trigger_options(options_button, _trigger_options)

	_slots.populate()

func set_trigger(trigger: BaseTrigger) -> void:
	options_button.clear()
	_populate_options()
	_loading = true
	current_trigger = trigger
	options_button.select(TriggerUtil.get_trigger_index(trigger, _trigger_options))
	_instantiate_trigger_ui(trigger)
	_loading = false

func _instantiate_trigger_ui(trigger: BaseTrigger) -> void:
	var ui := _show_trigger_ui(trigger, trigger_options)
	if ui != null and trigger is VolumeRange:
		_setup_volume_ui(trigger as VolumeRange, ui)

func _setup_volume_ui(volume_range: VolumeRange, ui: Node) -> void:
	_volume_min = ui.get_node("%VolumeMin")
	_volume_max = ui.get_node("%VolumeMax")
	_volume_delay = ui.get_node("%VolumeDelay")
	_volume_activation = ui.get_node("%VolumeActivation")
	_volume_min.value_changed.connect(_on_volume_value_changed)
	_volume_max.value_changed.connect(_on_volume_value_changed)
	_volume_delay.value_changed.connect(_on_volume_value_changed)
	_volume_activation.value_changed.connect(_on_volume_value_changed)
	_volume_min.value = volume_range.min_db
	_volume_max.value = volume_range.max_db
	_volume_delay.value = volume_range.revert_delay
	_volume_activation.value = volume_range.activation_delay

func _on_shortcut_saved(action_name: String, event: InputEvent, combo_keys: Array[int]) -> void:
	if options_button.selected == 0:
		return
	var script: GDScript = _trigger_options[options_button.selected - 1].script
	var trigger: BaseTrigger = current_trigger
	if trigger == null or trigger.get_script() != script:
		trigger = script.new()
	TriggerUtil.apply_shortcut_to_trigger(trigger, action_name, event, combo_keys)
	current_trigger = trigger
	trigger_option_changed.emit(current_emotion.emotion_name, trigger)

func set_emotion_effect(emotion: ModelEmotion) -> void:
	_populate_options()
	_loading = true
	_slots.set_selected(emotion.movement_effect, emotion.filter_effect)
	_update_effects_hint()
	_loading = false

func _on_movement_option_item_selected(index: int) -> void:
	_on_slot_option_selected(index, EffectLayerResolver.Category.MOVEMENT)

func _on_filter_option_item_selected(index: int) -> void:
	_on_slot_option_selected(index, EffectLayerResolver.Category.FILTER)

func _on_slot_option_selected(index: int, category: int) -> void:
	if _loading:
		return
	var effect := _slots.on_option_selected(category, index)
	_update_effects_hint()
	if current_emotion != null:
		SignalBus.model_emotion_effects_changed.emit(current_emotion, effect, category)

func _global_effect_name() -> String:
	if ModelLoader.model_loaded == null:
		return tr(&"NONE")
	var names: PackedStringArray = []
	for effect in ModelLoader.model_loaded.effects:
		if effect != null:
			names.append(BaseEffect.localize_name(effect.effect_name))
	if names.is_empty():
		return tr(&"NONE")
	return " + ".join(names)

func _update_effects_hint() -> void:
	effects_hint.text = String(tr(&"GLOBAL_EFFECT_HINT")) % _global_effect_name()

func _on_slot_param_changed(value: Variant, param_name: String, effect: BaseEffect, category: int) -> void:
	if _loading or effect == null:
		return

	EffectUIHelper.set_param_value(effect, param_name, value)

	if current_emotion != null:
		SignalBus.model_emotion_effects_changed.emit(current_emotion, effect, category)

func _on_default_toggled(pressed: bool) -> void:
	if current_emotion == null or ModelLoader.model_loaded == null:
		return
	if pressed:
		ModelLoader.model_loaded.default_emotion = current_emotion.emotion_name
	else:
		if ModelLoader.model_loaded.default_emotion.to_lower() == current_emotion.emotion_name.to_lower():
			ModelLoader.model_loaded.default_emotion = ""
	commit()
	SignalBus.states_changed.emit()

func _on_option_button_item_selected(index: int) -> void:
	if index == 0:
		current_trigger = null
		_instantiate_trigger_ui(null)
		trigger_option_changed.emit(current_emotion.emotion_name, null)
		return

	if index > _trigger_options.size():
		return

	current_trigger = TriggerUtil.trigger_from_index(index, _trigger_options)
	_instantiate_trigger_ui(current_trigger)
	trigger_option_changed.emit(current_emotion.emotion_name, current_trigger)

func _on_volume_value_changed(_value: float) -> void:
	if _loading:
		return
	if current_trigger is VolumeRange:
		var volume_range := current_trigger as VolumeRange
		volume_range.min_db = _volume_min.value
		volume_range.max_db = _volume_max.value
		volume_range.revert_delay = _volume_delay.value
		volume_range.activation_delay = _volume_activation.value
		commit()

func _on_twitch_event_changed(twitch_event: TwitchEvent) -> void:
	if current_emotion == null:
		return
	ModelStateMachine.replace_emotion_trigger(self, current_emotion, &"twitch_event", twitch_event)
	ModelLoader.save_and_sync_triggers()

func _on_rename_pressed() -> void:
	if current_emotion == null:
		return
	_rename_util.rename_property(tile_text, current_emotion, &"emotion_name", _is_emotion_name_taken)

func _is_emotion_name_taken(candidate: String) -> bool:
	return ModelLoader.model_loaded != null and ModelLoader.model_loaded.has_emotion_named(candidate, current_emotion)

func _trigger_category() -> String:
	return TriggerUtil.CATEGORY_EMOTION

func _trigger_stable_id() -> String:
	return current_emotion.emotion_name if current_emotion != null else ""

func _trigger_tile_label() -> Label:
	return tile_text
