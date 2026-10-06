class_name ModelStateMachine
extends Node

const TAG := "[StateMachine] "

signal entry_changed(previous: ModelStateEntry, current: ModelStateEntry)
signal emotion_changed(previous: ModelEmotion, current: ModelEmotion)
signal talking_changed(exceeded: bool)

var current_entry: ModelStateEntry
var is_talking: bool = false
var active_emotion: ModelEmotion
var _emotion_stack: Array[ModelEmotion] = []

func _ready() -> void:
	add_to_group(&"model_state_machine")
	SignalBus.mic_input_exceed_threshold.connect(_on_mic_threshold)
	SignalBus.model_triggers_changed.connect(_sync_emotion_triggers, CONNECT_DEFERRED)
	_sync_emotion_triggers()

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"mic_input_exceed_threshold", _on_mic_threshold)
	NodeUtil.safe_disconnect(SignalBus, &"model_triggers_changed", _sync_emotion_triggers)
	_unbind_emotion_triggers()

func _process(delta: float) -> void:
	if ApplicationState.get_state() == ApplicationState.AppState.LOADING:
		return
	var profile := ModelLoader.model_loaded
	if profile == null:
		return
	for emotion in profile.emotions:
		_tick_trigger(emotion.trigger, delta)
		_tick_trigger(emotion.twitch_event, delta)
	for item in profile.items:
		_tick_trigger(item.state_trigger, delta)
		_tick_trigger(item.twitch_event, delta)

func _tick_trigger(trigger: BaseTrigger, delta: float) -> void:
	if trigger != null:
		trigger.tick(delta, current_entry)

func _on_mic_threshold(exceeded: bool) -> void:
	if is_talking == exceeded:
		return
	is_talking = exceeded
	if ApplicationState.get_state() == ApplicationState.AppState.LOADING:
		return
	resolve()
	talking_changed.emit(exceeded)

func _sync_emotion_triggers() -> void:
	var profile := ModelLoader.model_loaded
	if profile == null:
		push_warning(TAG + "No model loaded; cannot sync emotion triggers.")
		return

	for emotion in profile.emotions:
		_bind_emotion_trigger(emotion)

	_prune_stale_emotions(profile)

	if active_emotion == null and not profile.default_emotion.is_empty():
		active_emotion = profile.get_emotion(profile.default_emotion)
		if active_emotion == null:
			push_warning(TAG + "Default emotion '%s' not found in profile." % [profile.default_emotion])

	if current_entry == null:
		var initial := get_initial_entry()
		if initial == null:
			push_warning(TAG + "Failed to resolve an initial state entry.")
		current_entry = initial
		entry_changed.emit(null, initial)
	else:
		resolve()

func _prune_stale_emotions(profile: ModelProfile) -> void:
	for i in range(_emotion_stack.size() - 1, -1, -1):
		if profile.get_emotion(_emotion_stack[i].emotion_name) == null:
			_emotion_stack.remove_at(i)
	if active_emotion != null and profile.get_emotion(active_emotion.emotion_name) == null:
		active_emotion = null

func _unbind_emotion_triggers() -> void:
	var profile := ModelLoader.model_loaded
	if profile == null:
		return
	for emotion in profile.emotions:
		_unbind_emotion_trigger(emotion)

func _bind_emotion_trigger(emotion: ModelEmotion) -> void:
	_bind_trigger(emotion.trigger, emotion)
	_bind_trigger(emotion.twitch_event, emotion)
	if emotion.trigger == null and emotion.twitch_event == null:
		push_warning(TAG + "Emotion '%s' has no trigger; it will never activate." % [emotion.emotion_name])

func _unbind_emotion_trigger(emotion: ModelEmotion) -> void:
	unbind_trigger(emotion.trigger, emotion)
	unbind_trigger(emotion.twitch_event, emotion)

func unbind_trigger(trigger: BaseTrigger, emotion: ModelEmotion) -> void:
	if trigger != null:
		trigger.unbind_changed(_on_emotion_trigger_changed.bind(emotion))

static func replace_emotion_trigger(caller: Node, emotion: ModelEmotion, property: StringName, new_trigger: BaseTrigger) -> void:
	var old_trigger: BaseTrigger = emotion.get(property) as BaseTrigger
	if old_trigger != null and old_trigger != new_trigger:
		old_trigger.deactivate()
		var tree := caller.get_tree()
		if tree != null:
			var machine := tree.get_first_node_in_group(&"model_state_machine") as ModelStateMachine
			if machine != null:
				machine.unbind_trigger(old_trigger, emotion)
	emotion.set(property, new_trigger)

func _bind_trigger(trigger: BaseTrigger, emotion: ModelEmotion) -> void:
	if trigger != null:
		trigger.bind_changed(_on_emotion_trigger_changed.bind(emotion))

func _on_emotion_trigger_changed(trigger: BaseTrigger, emotion: ModelEmotion) -> void:
	if trigger.enabled:
		_activate_emotion(emotion)
		return
	_deactivate_emotion(emotion)

func _activate_emotion(emotion: ModelEmotion) -> void:
	_emotion_stack.erase(emotion)
	_emotion_stack.append(emotion)
	_set_active_emotion(emotion)

func _deactivate_emotion(emotion: ModelEmotion) -> void:
	_emotion_stack.erase(emotion)
	if active_emotion != emotion:
		return
	_set_active_emotion(_fallback_emotion())

func _fallback_emotion() -> ModelEmotion:
	for i in range(_emotion_stack.size() - 1, -1, -1):
		var candidate := _emotion_stack[i]
		if _is_emotion_engaged(candidate):
			return candidate
		_emotion_stack.remove_at(i)
	return _default_emotion()

func _default_emotion() -> ModelEmotion:
	var profile := ModelLoader.model_loaded
	if profile == null or profile.default_emotion.is_empty():
		return null
	return profile.get_emotion(profile.default_emotion)

func _is_emotion_engaged(emotion: ModelEmotion) -> bool:
	if emotion == null:
		return false
	if emotion.trigger != null and emotion.trigger.enabled:
		return true
	return emotion.twitch_event != null and emotion.twitch_event.enabled

func _set_active_emotion(emotion: ModelEmotion) -> void:
	if emotion == active_emotion:
		resolve()
		return
	var previous := active_emotion
	active_emotion = emotion
	emotion_changed.emit(previous, emotion)
	resolve()

func resolve() -> void:
	var next := _pick_entry()
	if next == null:
		push_warning(TAG + "Failed to resolve entry while current is '%s'." % [current_entry.state_name if current_entry else "null"])
		return
	if next == current_entry:
		return

	var previous := current_entry
	current_entry = next
	entry_changed.emit(previous, next)

func _pick_entry() -> ModelStateEntry:
	var profile := ModelLoader.model_loaded
	if profile == null:
		return null
	var branch := profile.active_branch(is_talking)
	if branch == null and not profile.branches.is_empty():
		branch = profile.branches[0]
	if branch == null:
		return null
	if active_emotion != null:
		var override_entry := _override_entry(profile)
		if override_entry != null:
			return override_entry
		var entry := branch.entry_for(active_emotion.emotion_name)
		if entry != null:
			return entry
	return branch.resolve_default_entry()

func _override_entry(profile: ModelProfile) -> ModelStateEntry:
	var talking := profile.get_branch(ModelState.TALKING)
	var silence := profile.get_branch(ModelState.SILENCE)
	var talk_entry := talking.find_entry(active_emotion.emotion_name) if talking != null else null
	var silence_entry := silence.find_entry(active_emotion.emotion_name) if silence != null else null
	if is_talking:
		if silence_entry != null and silence_entry.override_silence:
			return silence_entry
	elif talk_entry != null and talk_entry.override_silence:
		return talk_entry
	return null

func get_initial_entry() -> ModelStateEntry:
	var profile := ModelLoader.model_loaded
	if profile == null:
		push_warning(TAG + "No model loaded; cannot get initial entry.")
		return null
	if profile.branches.is_empty():
		push_warning(TAG + "Model profile has no branches; cannot resolve initial state.")
		return null
	var silence := profile.silence_branch()
	if silence != null:
		var entry := silence.resolve_default_entry()
		if entry == null:
			push_warning(TAG + "Silence branch returned no default entry.")
		return entry
	return profile.branches[0].resolve_default_entry()

func force_emotion(emotion_name: String) -> String:
	var profile := ModelLoader.model_loaded
	if profile == null:
		return "no model loaded"
	if emotion_name.is_empty():
		_deactivate_emotion(active_emotion)
		return ""
	var emotion := profile.get_emotion(emotion_name)
	if emotion == null:
		return "unknown emotion: " + emotion_name
	_activate_emotion(emotion)
	return ""

func force_entry_by_path(entry_path: String) -> String:
	var parts := entry_path.split("/", false)
	if parts.is_empty():
		return "invalid state path: " + entry_path

	var profile := ModelLoader.model_loaded
	if profile == null:
		return "no model loaded"

	if parts.size() >= 2:
		var branch := profile.get_branch(parts[0])
		if branch == null:
			return "unknown branch: " + parts[0]
		for entry in branch.all_entries():
			if entry.state_name.to_lower() == parts[1].to_lower():
				return force_emotion(entry.state_name)
		return "unknown entry: " + entry_path

	var emotion := profile.get_emotion(parts[0])
	if emotion != null:
		return force_emotion(emotion.emotion_name)

	for branch in profile.branches:
		for entry in branch.all_entries():
			if entry.state_name.to_lower() == parts[0].to_lower():
				return force_emotion("")
	return "unknown state: " + entry_path
