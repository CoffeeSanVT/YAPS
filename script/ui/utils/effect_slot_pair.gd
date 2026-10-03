class_name EffectSlotPair
extends RefCounted


signal param_changed(value: Variant, param_name: String, effect: BaseEffect, category: int)

const ZERO_TEXT := "EFFECT_USE_GLOBAL"

var movement_option: OptionButton
var movement_container: Container
var filter_option: OptionButton
var filter_container: Container
var movement_effects: PackedStringArray
var filter_effects: PackedStringArray

func setup(p_movement_option: OptionButton, p_movement_container: Container, p_filter_option: OptionButton, p_filter_container: Container) -> void:
	movement_option = p_movement_option
	movement_container = p_movement_container
	filter_option = p_filter_option
	filter_container = p_filter_container

func populate() -> void:
	if movement_option.item_count == 0:
		movement_effects = EffectUIHelper.populate_effect_options(movement_option, EffectLayerResolver.Category.MOVEMENT, ZERO_TEXT)
	if filter_option.item_count == 0:
		filter_effects = EffectUIHelper.populate_effect_options(filter_option, EffectLayerResolver.Category.FILTER, ZERO_TEXT)

func refresh_texts() -> void:
	EffectUIHelper.set_effect_option_texts(movement_option, movement_effects, ZERO_TEXT)
	EffectUIHelper.set_effect_option_texts(filter_option, filter_effects, ZERO_TEXT)

func set_selected(movement: BaseEffect, filter: BaseEffect) -> void:
	movement_option.selected = EffectUIHelper.find_effect_index(movement_effects, movement)
	filter_option.selected = EffectUIHelper.find_effect_index(filter_effects, filter)
	setup_slot(movement, EffectLayerResolver.Category.MOVEMENT)
	setup_slot(filter, EffectLayerResolver.Category.FILTER)

func setup_slot(effect: BaseEffect, category: int) -> void:
	EffectUIHelper.setup_slot_ui(effect, _container_for(category), _on_slot_param.bind(effect, category))

func effect_from_selected(category: int) -> BaseEffect:
	var options := _options_for(category)
	if ModelLoader.model_loaded == null or options.is_empty() or _option_for(category).selected <= 0:
		return null
	var id: StringName = options[_option_for(category).selected - 1]
	var found := EffectLayerResolver.find_in(ModelLoader.model_loaded.effects, category, id)
	if found != null:
		return found
	return BaseEffect.instantiate_effect_by_name(String(id))

func on_option_selected(category: int, index: int) -> BaseEffect:
	var options := _options_for(category)
	var effect: BaseEffect = null
	if index > 0:
		effect = BaseEffect.instantiate_effect_by_name(options[index - 1])
	setup_slot(effect, category)
	return effect

func _container_for(category: int) -> Container:
	return movement_container if category == EffectLayerResolver.Category.MOVEMENT else filter_container

func _option_for(category: int) -> OptionButton:
	return movement_option if category == EffectLayerResolver.Category.MOVEMENT else filter_option

func _options_for(category: int) -> PackedStringArray:
	return movement_effects if category == EffectLayerResolver.Category.MOVEMENT else filter_effects

func _on_slot_param(value: Variant, param_name: String, effect: BaseEffect, category: int) -> void:
	param_changed.emit(value, param_name, effect, category)
