class_name EffectUIHelper
extends RefCounted

const _PARAM_NAMES := {
	&"bounce": ["BounceDuration", "BounceIntensity"],
	&"shake": ["ShakeDuration", "ShakeAmplitude"],
	&"bob": ["BobDuration", "BobAmplitude"],
	&"warp": ["WarpDuration", "WarpIntensity"],
	&"darken": ["DarkenDuration", "DarkenIntensity"],
}

const _PARAM_PROPERTIES := {
	"Duration": &"duration",
	"Intensity": &"intensity",
	"Amplitude": &"amplitude",
}

static func populate_effect_options(option_button: OptionButton, category: int = -1, zero_text: String = "NONE") -> PackedStringArray:
	option_button.add_item(TranslationServer.translate(zero_text))
	var options: PackedStringArray = []
	for opt in BaseEffect.get_available_options():
		if category >= 0:
			var effect := BaseEffect.instantiate_effect_by_name(opt)
			if effect == null or EffectLayerResolver.category_of(effect) != category:
				continue
		option_button.add_item(BaseEffect.localize_name(opt))
		options.append(opt)
	return options

static func set_effect_option_texts(option: OptionButton, options: PackedStringArray, zero_text: String = "NONE") -> void:
	if option.item_count == 0:
		return
	option.set_item_text(0, TranslationServer.translate(zero_text))
	for i in options.size():
		option.set_item_text(i + 1, BaseEffect.localize_name(options[i]))

static func find_effect_index(effect_options: PackedStringArray, effect: BaseEffect) -> int:
	if effect == null:
		return 0
	var idx := effect_options.find(String(effect.effect_name))
	return idx + 1 if idx >= 0 else 0

static func setup_slot_ui(effect: BaseEffect, container: Container, on_param_changed: Callable) -> Node:
	clear_slot_ui(container)
	if effect == null:
		return null
	var ui := instantiate_effect_ui(effect, container)
	if ui == null:
		return null
	connect_effect_params(ui, on_param_changed)
	load_effect_params(effect, ui)
	return ui

static func clear_slot_ui(container: Container) -> void:
	NodeUtil.clear_children(container)

static func instantiate_effect_ui(effect: BaseEffect, container: Container) -> Node:
	if effect == null:
		return null
	return NodeUtil.instantiate_into(effect.ui_prefab, container, "effect '%s'" % effect.effect_name)

static func connect_effect_params(ui: Node, callable: Callable) -> void:
	if ui == null:
		return
	for spin in ui.find_children("*", "SpinBox", true, false):
		spin.value_changed.connect(callable.bind(spin.name))

static func load_effect_params(effect: BaseEffect, ui: Node) -> void:
	if effect == null or ui == null:
		return
	for param_name in _param_names(effect.effect_name):
		var spin := ui.find_child(param_name, true, false) as SpinBox
		if spin != null:
			spin.value = get_param_value(effect, param_name)

static func get_param_value(effect: BaseEffect, param_name: String) -> float:
	if effect == null:
		return 0.0
	var prop := _property_for(param_name)
	if prop.is_empty():
		return 0.0
	return effect.get(prop)

static func set_param_value(effect: BaseEffect, param_name: String, value: float) -> void:
	var prop := _property_for(param_name)
	if effect != null and not prop.is_empty():
		effect.set(prop, value)

static func _property_for(param_name: String) -> StringName:
	for suffix: String in _PARAM_PROPERTIES:
		if param_name.ends_with(suffix):
			return _PARAM_PROPERTIES[suffix]
	return &""

static func _param_names(effect_name: StringName) -> Array[String]:
	var names: Array[String] = []
	for entry: String in _PARAM_NAMES.get(effect_name, []):
		names.append(entry)
	return names
