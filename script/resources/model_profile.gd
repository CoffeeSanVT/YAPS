class_name ModelProfile
extends Resource

@export_category("Profile")
@export var model_name: String = ""

@export_category("Performance")
@export var vram_texture_compression: bool = false

@export_category("States & Emotions")
@export var branches: Array[ModelState] = []
@export var emotions: Array[ModelEmotion] = []
@export var neutral_emotion: ModelEmotion
@export var default_emotion: String = ""
@export var items: Array[Item] = []
@export var state_transition_duration: float = 0.3
@export var global_frame_rate: float = 0.0
@export var global_animation_chance: float = 0.0

@export_category("Effects")
@export var effects: Array[BaseEffect] = []
@export var effects_enabled: bool = true

@export_category("Transform Presets")
@export var transform_presets: Array[TransformPreset] = []

@export_category("Outline")
@export var outline_enabled: bool = false
@export var outline_color: Color = Color.WHITE
@export var outline_width: float = 5.0
@export var outline_softness: float = 2.0
@export var outline_inside: bool = false
@export var outline_alpha_threshold: float = 0.7
@export var outline_halftone: bool = false
@export var outline_halftone_size: float = 6.0
@export var outline_gradient: bool = false
@export var outline_gradient_color: Color = Color(0.0, 0.5, 1.0, 1.0)

func _init(name: String = "") -> void:
	model_name = name

func get_branch(state_name: StringName) -> ModelState:
	for branch in branches:
		if branch.state_name == state_name:
			return branch
	return null

func talking_branch() -> ModelState:
	return ensure_branch(ModelState.TALKING)

func silence_branch() -> ModelState:
	return ensure_branch(ModelState.SILENCE)

func active_branch(is_talking: bool) -> ModelState:
	return get_branch(ModelState.TALKING if is_talking else ModelState.SILENCE)

func ensure_branch(state_name: String) -> ModelState:
	var branch := get_branch(state_name)
	if branch != null:
		return branch
	branch = ModelState.new(state_name)
	branches.append(branch)
	return branch

func get_emotion(emotion_name: String) -> ModelEmotion:
	for emotion in emotions:
		if emotion.emotion_name.to_lower() == emotion_name.to_lower():
			return emotion
	return null

func ensure_emotion(emotion_name: String) -> ModelEmotion:
	var emotion := get_emotion(emotion_name)
	if emotion != null:
		return emotion
	emotion = ModelEmotion.new(emotion_name)
	emotions.append(emotion)
	return emotion

func ensure_neutral_emotion() -> ModelEmotion:
	if neutral_emotion == null:
		neutral_emotion = ModelEmotion.new("neutral")
	return neutral_emotion

func all_entries() -> Array[ModelStateEntry]:
	var entries: Array[ModelStateEntry] = []
	for branch in branches:
		entries.append_array(branch.all_entries())
	return entries

func branch_of(entry: ModelStateEntry) -> ModelState:
	for branch in branches:
		if branch.all_entries().has(entry):
			return branch
	return null

func has_entry_named(entry_name: String, excluding: ModelStateEntry = null) -> bool:
	return _has_name_in(all_entries(), &"state_name", entry_name, excluding)

func has_emotion_named(emotion_name: String, excluding: ModelEmotion = null) -> bool:
	return _has_name_in(emotions, &"emotion_name", emotion_name, excluding)

func has_item_named(item_name: String, excluding: Item = null) -> bool:
	return _has_name_in(items, &"state_name", item_name, excluding)

func has_preset_named(preset_name: String, excluding: TransformPreset = null) -> bool:
	return _has_name_in(transform_presets, &"preset_name", preset_name, excluding)

func _has_name_in(entries: Array, property: StringName, candidate: String, excluding: Variant) -> bool:
	for entry: Variant in entries:
		if entry == excluding:
			continue
		if String(entry.get(property)).to_lower() == candidate.to_lower():
			return true
	return false

