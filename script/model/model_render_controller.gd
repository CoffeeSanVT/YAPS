extends Node

const TAG := "[ModelRender] "
const STATIC_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]

@export_category("Model Render")
@export var model_container: Control

var _machine: ModelStateMachine
var _view: ModelView
var _active_effects: Array[BaseEffect] = []

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
	]

func _setup_view() -> void:
	var initial_state := _machine.get_initial_entry()
	if initial_state == null:
		push_warning(TAG + "No initial state found; static PNG rendered without texture.")
	_view.setup(model_container, ModelLoader.textures.load_state_texture(initial_state) if initial_state else null)

func _prewarm_textures() -> void:
	var profile := ModelLoader.model_loaded
	if profile == null:
		return
	var seen: Dictionary[String, bool] = {}
	for branch in profile.branches:
		for entry in branch.all_entries():
			if not entry.asset_path.is_empty() and not seen.has(entry.asset_path):
				seen[entry.asset_path] = true
				if _is_static_image(entry.asset_path):
					ModelLoader.textures.request_texture(entry.asset_path, Callable())
			if entry.frames.is_empty():
				continue
			ModelLoader.textures.request_texture(entry.frames[0], Callable())
			for frame_path in entry.frames:
				if frame_path.is_empty() or seen.has(frame_path):
					continue
				seen[frame_path] = true
				ModelLoader.textures.request_thumb(frame_path)

static func _is_static_image(path: String) -> bool:
	return path.get_extension().to_lower() in STATIC_EXTENSIONS

func _on_state_changed(previous: ModelStateEntry, current: ModelStateEntry) -> void:
	if current == null:
		push_warning(TAG + "State changed to null; ignoring.")
		return
	var next_tex := ModelLoader.textures.load_state_texture(current)
	if next_tex == null:
		push_warning(TAG + "Failed to load texture for state: " + current.state_name)
		return
	if previous != null:
		_deactivate_all_effects()
	_view.show_state(next_tex, current, ModelLoader.model_loaded.state_transition_duration)
	_refresh_effects()

func _deactivate_all_effects() -> void:
	for effect: BaseEffect in _active_effects:
		effect.deactivate()
	_active_effects = []

func _activate_effects(effects: Array[BaseEffect]) -> void:
	_deactivate_all_effects()
	_active_effects = effects.duplicate()
	for effect: BaseEffect in _active_effects:
		effect.activate(_view.model_render)

func _refresh_effects(force := false) -> void:
	if _machine == null or _machine.current_entry == null:
		return
	var effects := EffectLayerResolver.resolve(_machine)
	if not force and _same_effects(effects):
		return
	_activate_effects(effects)

func _on_effects_changed() -> void:
	_refresh_effects(true)

func _on_emotion_changed(_previous: ModelEmotion, _current: ModelEmotion) -> void:
	_refresh_effects()

func _on_talking_changed(_exceeded: bool) -> void:
	_refresh_effects()

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

func _on_spout_enabled_changed(value: bool) -> void:
	_apply_spout_enabled(value)

func _apply_spout_enabled(enabled: bool) -> void:
	model_container = SpoutViewportUtil.apply_enabled(model_container, enabled)
	call_deferred(&"_emit_model_container_changed")

func _emit_model_container_changed() -> void:
	SignalBus.model_container_changed.emit(model_container)
