extends Node

const TAG := "[ModelRender] "

@export_category("Model Render")
@export var model_container: Control

var _machine: ModelStateMachine
var _view: ModelView
var _active_effects: Array[BaseEffect] = []
var _state_request_id := 0

func _ready() -> void:
	if ModelLoader.model_loaded == null:
		push_warning(TAG + "No model loaded; render controller setup skipped.")
		return
	_machine = ModelStateMachine.new()
	_apply_spout_enabled(Settings.settings.spout_enabled)
	_view = ModelView.new()
	add_child(_view)
	_setup_view()
	_prewarm_textures()
	_wire_signals()
	_machine.emotion_changed.connect(_on_emotion_changed)
	_machine.talking_changed.connect(_on_talking_changed)
	add_child(_machine)

func _exit_tree() -> void:
	if _view != null:
		_view.interrupt()
	ModelLoader.textures.clear()
	_active_effects = []
	NodeUtil.disconnect_many(_bus_connections())

func _wire_signals() -> void:
	NodeUtil.connect_many(_bus_connections())
	_machine.entry_changed.connect(_on_state_changed)

func _bus_connections() -> Array:
	return [
		[SignalBus, &"texture_filter_changed", _on_texture_filter_changed],
		[SignalBus, &"antialias_changed", _on_antialias_changed],
		[SignalBus, &"spout_enabled_changed", _on_spout_enabled_changed],
		[SignalBus, &"state_frames_changed", _on_state_frames_changed],
		[SignalBus, &"model_images_reloaded", _on_state_frames_changed],
		[SignalBus, &"model_images_reloaded", _prewarm_textures],
		[SignalBus, &"model_effects_changed", _on_effects_changed],
		[SignalBus, &"outline_settings_changed", _on_outline_settings_changed],
		[SignalBus, &"model_flip_changed", _on_flip_changed],
	]

func _setup_view() -> void:
	var initial_state := _machine.get_initial_entry()
	if initial_state == null:
		push_warning(TAG + "No initial state found; static PNG rendered without texture.")
	_view.setup(model_container, ModelLoader.textures.load_state_texture(initial_state) if initial_state else null)
	_view.set_flip(ModelLoader.model_loaded.flip_x)

func _prewarm_textures() -> void:
	var profile := ModelLoader.model_loaded
	if profile == null:
		return
	var entries: Array[ModelStateEntry] = [_machine.get_initial_entry()]
	var talking := profile.get_branch(ModelState.TALKING)
	if talking != null:
		entries.append(talking.resolve_default_entry())
	if _machine.current_entry != null:
		entries.append(_machine.current_entry)
	var seen: Dictionary[String, bool] = {}
	for entry in entries:
		if entry == null:
			continue
		var path := ModelLoader.textures.state_first_path(entry)
		if path.is_empty() or seen.has(path):
			continue
		seen[path] = true
		ModelLoader.textures.pin_path(path)
		ModelLoader.textures.request_texture(path, Callable())

func _on_state_changed(_previous: ModelStateEntry, current: ModelStateEntry) -> void:
	if current == null:
		push_warning(TAG + "State changed to null; ignoring.")
		return
	_state_request_id += 1
	var request_id := _state_request_id
	ModelLoader.textures.request_state_texture(current, func(next_tex: Texture2D) -> void:
		if request_id != _state_request_id:
			return
		if next_tex == null:
			push_warning(TAG + "Failed to load texture for state: " + current.state_name)
			return
		_view.show_state(next_tex, current, ModelLoader.model_loaded.state_transition_duration)
		_refresh_effects()
	, self)

func _activate_effects(effects: Array[BaseEffect], restart := false) -> void:
	for effect: BaseEffect in _active_effects:
		if restart or not effects.has(effect):
			effect.deactivate()
	for effect: BaseEffect in effects:
		if restart or not _active_effects.has(effect):
			effect.activate(_view.model_render)
	_active_effects = effects.duplicate()

func _refresh_effects(force := false) -> void:
	if _machine == null or _machine.current_entry == null:
		return
	var effects := EffectLayerResolver.resolve(_machine)
	if not force and _same_effects(effects):
		return
	_activate_effects(effects, force)

func _on_effects_changed() -> void:
	_refresh_effects(true)

func _on_emotion_changed(_previous: ModelEmotion, _current: ModelEmotion) -> void:
	_refresh_effects()

func _on_talking_changed(exceeded: bool) -> void:
	_refresh_effects()
	if not exceeded:
		return
	for effect: BaseEffect in _active_effects:
		if effect.retrigger_on_talking():
			effect.activate(_view.model_render)

func _same_effects(effects: Array[BaseEffect]) -> bool:
	if effects.size() != _active_effects.size():
		return false
	for i in effects.size():
		if effects[i] != _active_effects[i]:
			return false
	return true

func _on_state_frames_changed() -> void:
	if _machine == null or _machine.current_entry == null:
		return
	_view.show_state_frames(_machine.current_entry)

func _on_texture_filter_changed(value: int) -> void:
	_view.set_filter(value)

func _on_antialias_changed(value: int) -> void:
	_view.set_antialias(value)

func _on_outline_settings_changed() -> void:
	_view.apply_outline_settings(ModelLoader.model_loaded)

func _on_flip_changed(flip: bool) -> void:
	_view.set_flip(flip)

func _on_spout_enabled_changed(value: bool) -> void:
	_apply_spout_enabled(value)

func _apply_spout_enabled(enabled: bool) -> void:
	model_container = SpoutViewportUtil.apply_enabled(model_container, enabled)
	call_deferred(&"_emit_model_container_changed")

func _emit_model_container_changed() -> void:
	SignalBus.model_container_changed.emit(model_container)
