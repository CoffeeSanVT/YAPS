class_name EffectLayerResolver

enum EffectLayer {
	GLOBAL = 0,
	EMOTION = 1,
}

enum Category {
	MOVEMENT = 0,
	FILTER = 1,
}

static func category_of(effect: BaseEffect) -> int:
	if effect is MovementEffect:
		return Category.MOVEMENT
	if effect is FilterEffect:
		return Category.FILTER
	return -1

static func find_in(effects: Array[BaseEffect], category: int, id: StringName = &"") -> BaseEffect:
	for effect: BaseEffect in effects:
		if effect == null:
			continue
		if id != &"" and effect.effect_name != id:
			continue
		if category_of(effect) == category:
			return effect
	return null

static func resolve(machine: ModelStateMachine) -> Array[BaseEffect]:
	var layers: Dictionary = {}

	var profile := ModelLoader.model_loaded
	if profile == null:
		return [] as Array[BaseEffect]

	if profile.effects_enabled:
		layers[EffectLayer.GLOBAL] = profile.effects

	var emotion: ModelEmotion = null
	if machine != null:
		emotion = machine.active_emotion
	if emotion == null:
		emotion = profile.neutral_emotion
	if emotion != null:
		var emotion_effects := emotion.get_effects()
		if not emotion_effects.is_empty():
			layers[EffectLayer.EMOTION] = emotion_effects

	var resolved: Array[BaseEffect] = []
	for category: int in [Category.MOVEMENT, Category.FILTER]:
		var effect := _resolve_category(layers, category)
		if effect != null:
			resolved.append(effect)

	return _filter_talking(resolved, machine)

static func _resolve_category(layers: Dictionary, category: int) -> BaseEffect:
	for layer: EffectLayer in [EffectLayer.EMOTION, EffectLayer.GLOBAL]:
		if not layers.has(layer):
			continue
		var effect := find_in(layers[layer], category)
		if effect != null:
			return effect
	return null

static func _filter_talking(effects: Array[BaseEffect], machine: ModelStateMachine) -> Array[BaseEffect]:
	if machine == null:
		return effects
	var filtered: Array[BaseEffect] = []
	for effect: BaseEffect in effects:
		if effect.active_for_talking(machine.is_talking):
			filtered.append(effect)
	return filtered
