extends VBoxContainer

@export_category("UI References")
@export var effects_toggle: CheckButton
@export var movement_option: OptionButton
@export var movement_options: Container
@export var filter_option: OptionButton
@export var filter_options: Container

var _slots := EffectSlotPair.new()
var _loading := false

func _ready() -> void:
	_slots.setup(movement_option, movement_options, filter_option, filter_options)
	_slots.param_changed.connect(_on_slot_param_changed)
	_slots.populate()
	NodeUtil.attach_locale(self, _on_locale_change)
	_reload()

func _on_locale_change() -> void:
	_slots.refresh_texts()

func _reload() -> void:
	if ModelLoader.model_loaded == null:
		return

	_loading = true
	effects_toggle.button_pressed = ModelLoader.model_loaded.effects_enabled
	var effects := ModelLoader.model_loaded.effects
	var movement := EffectLayerResolver.find_in(effects, EffectLayerResolver.Category.MOVEMENT)
	var filter := EffectLayerResolver.find_in(effects, EffectLayerResolver.Category.FILTER)
	_slots.set_selected(movement, filter)
	_loading = false

func _persist(movement: BaseEffect, filter: BaseEffect) -> void:
	if _loading or ModelLoader.model_loaded == null:
		return
	var profile := ModelLoader.model_loaded
	var kept: Array[BaseEffect] = []
	for effect in profile.effects:
		if effect == null:
			continue
		if effect == movement or effect == filter:
			kept.append(effect)
			continue
		effect.deactivate()

	if movement != null and movement not in kept:
		kept.append(movement)
	if filter != null and filter not in kept:
		kept.append(filter)
	profile.effects = kept

	ModelLoader.save_model()

func _persist_from_profile() -> void:
	if ModelLoader.model_loaded == null:
		return
	_persist(
		EffectLayerResolver.find_in(ModelLoader.model_loaded.effects, EffectLayerResolver.Category.MOVEMENT),
		EffectLayerResolver.find_in(ModelLoader.model_loaded.effects, EffectLayerResolver.Category.FILTER))

func _on_effects_toggle_toggled(toggled: bool) -> void:
	if _loading or ModelLoader.model_loaded == null:
		return
	ModelLoader.model_loaded.effects_enabled = toggled
	ModelLoader.save_model()
	SignalBus.model_effects_changed.emit()

func _on_movement_type_item_selected(_index: int) -> void:
	_on_effect_type_selected(EffectLayerResolver.Category.MOVEMENT)

func _on_filter_type_item_selected(_index: int) -> void:
	_on_effect_type_selected(EffectLayerResolver.Category.FILTER)

func _on_effect_type_selected(category: int) -> void:
	if _loading or ModelLoader.model_loaded == null:
		return
	var selected_effect := _slots.effect_from_selected(category)
	var other_category := EffectLayerResolver.Category.FILTER if category == EffectLayerResolver.Category.MOVEMENT else EffectLayerResolver.Category.MOVEMENT
	var other_effect := EffectLayerResolver.find_in(ModelLoader.model_loaded.effects, other_category)
	_loading = true
	_slots.setup_slot(selected_effect, category)
	_loading = false
	if category == EffectLayerResolver.Category.MOVEMENT:
		_persist(selected_effect, other_effect)
	else:
		_persist(other_effect, selected_effect)
	SignalBus.model_effects_changed.emit()

func _on_slot_param_changed(value: Variant, param_name: String, effect: BaseEffect, _category: int) -> void:
	if _loading or effect == null:
		return
	EffectUIHelper.set_param_value(effect, param_name, value)
	_persist_from_profile()
	SignalBus.model_effects_changed.emit()
