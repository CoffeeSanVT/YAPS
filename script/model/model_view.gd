class_name ModelView
extends Node

const TAG := "[ModelView] "
const MODEL_SHADER := "uid://brgxnej006wdu"
const HOT_WINDOW := 5
const HOT_LOOKAHEAD := 4

var model_render: TextureRect

var _container: Control
var _applied_tex: Texture2D
var _active_tween: Tween
var _cycle_timer: Timer
var _track := FrameTrack.new()
var _out_track := FrameTrack.new()
var _snap_start_cache: Dictionary[ModelStateEntry, int] = {}
var _anim_frames_left: int = 0
var _transitioning: bool = false
var _next_tex_current: Texture2D

static var _linear_shader: Shader
static var _nearest_shader: Shader

func _init() -> void:
	_track.bind(self, _advance_frame)
	_out_track.bind(self, _advance_out)

func setup(container: Control, initial_tex: Texture2D) -> void:
	var model_node := TextureRect.new()
	var material := ShaderMaterial.new()
	material.shader = _shader_for(Settings.settings.texture_filter)
	model_node.name = &"model"
	model_node.material = material
	if initial_tex:
		model_node.texture = initial_tex
	material.set_shader_parameter(&"_Transition", 0.0)
	material.set_shader_parameter(&"_AntiAlias", Settings.settings.antialias)
	model_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	model_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	model_node.position = Vector2.ZERO
	model_node.size = container.size
	_container = container
	model_render = model_node
	_applied_tex = initial_tex
	if initial_tex:
		_set_current_tex(material, initial_tex)
		_set_next_tex_on(material, initial_tex)
	apply_outline_settings(ModelLoader.model_loaded)
	container.add_child(model_node)
	model_render.pivot_offset = model_render.size * 0.5
	NodeUtil.connect_once(container, &"resized", _sync_model_rect)

func _sync_model_rect() -> void:
	if _container == null or model_render == null:
		return
	model_render.size = _container.size
	model_render.pivot_offset = model_render.size * 0.5

func show_state(tex: Texture2D, state: ModelStateEntry, transition_duration: float) -> void:
	if model_render == null:
		return
	var mat := model_render.material as ShaderMaterial
	_abort_transition()
	var base_tex := _current_base_tex()
	if base_tex == tex:
		_commit_texture(tex)
		show_state_frames(state)
		return
	_snapshot_outgoing_track()
	_transitioning = true
	_start_out_track()
	var current_tex := base_tex
	if not _out_track.frames.is_empty() and _out_track.frames[_out_track.index] != null:
		current_tex = _out_track.frames[_out_track.index]
	_active_tween = _build_crossfade_tween(mat, current_tex, tex, transition_duration, _finish_state_transition)
	_next_tex_current = tex
	show_state_frames(state)

func show_state_frames(state: ModelStateEntry) -> void:
	_stop_frames()
	if state.frames.is_empty():
		show_static(state)
		return
	_start_frame_animation(state)

func show_static(state: ModelStateEntry) -> void:
	var tex := ModelLoader.textures.load_state_texture(state)
	if tex == null:
		push_warning(TAG + "Failed to load static texture for state: " + state.state_name)
		return
	if _transitioning:
		_set_next_tex(tex)
	else:
		_commit_texture(tex)

func interrupt() -> void:
	_abort_transition()
	_stop_frames()

func _abort_transition() -> void:
	_cancel_master_tween()
	_finish_state_transition()

func _current_base_tex() -> Texture2D:
	return _applied_tex if _applied_tex else model_render.texture

func set_filter(value: int) -> void:
	if model_render == null:
		return
	var mat := model_render.material as ShaderMaterial
	mat.shader = _shader_for(value)
	if _active_tween == null or not _active_tween.is_valid():
		_reset_transition(mat, _applied_tex)

func set_antialias(value: int) -> void:
	if model_render == null:
		return
	(model_render.material as ShaderMaterial).set_shader_parameter(&"_AntiAlias", value)

func apply_outline_settings(s: ModelProfile) -> void:
	if s == null or model_render == null:
		return
	var mat := model_render.material as ShaderMaterial
	mat.set_shader_parameter(&"_EnableOutline", s.outline_enabled)
	mat.set_shader_parameter(&"_OutlineColor", s.outline_color)
	mat.set_shader_parameter(&"_OutlineWidth", s.outline_width)
	mat.set_shader_parameter(&"_OutlineSoftness", s.outline_softness)
	mat.set_shader_parameter(&"_OutlineInside", s.outline_inside)
	mat.set_shader_parameter(&"_OutlineAlphaThreshold", s.outline_alpha_threshold)
	mat.set_shader_parameter(&"_OutlineHalftone", s.outline_halftone)
	mat.set_shader_parameter(&"_OutlineHalftoneSize", s.outline_halftone_size)
	mat.set_shader_parameter(&"_OutlineGradient", s.outline_gradient)
	mat.set_shader_parameter(&"_OutlineGradientColor", s.outline_gradient_color)

func _commit_texture(tex: Texture2D) -> void:
	var mat := model_render.material as ShaderMaterial
	_reset_transition(mat, tex)
	_applied_tex = tex
	model_render.texture = tex

func _reset_transition(mat: ShaderMaterial, tex: Texture2D) -> void:
	_set_current_tex(mat, tex)
	_set_next_tex_on(mat, tex)
	mat.set_shader_parameter(&"_Transition", 0.0)

func _build_crossfade_tween(mat: ShaderMaterial, base_tex: Texture2D, next_tex: Texture2D, duration: float, on_complete: Callable) -> Tween:
	_set_current_tex(mat, base_tex)
	_set_next_tex_on(mat, next_tex)
	mat.set_shader_parameter(&"_Transition", 0.0)
	var step := func(value: float) -> void:
		mat.set_shader_parameter(&"_Transition", value)
	var tween := create_tween()
	tween.tween_method(step, 0.0, 1.0, duration)
	tween.tween_callback(on_complete)
	return tween

func _set_current_tex(mat: ShaderMaterial, tex: Texture2D) -> void:
	mat.set_shader_parameter(&"_CurrentTex", tex)
	_set_bounds(mat, &"_CurrentBounds", tex)

func _set_next_tex_on(mat: ShaderMaterial, tex: Texture2D) -> void:
	mat.set_shader_parameter(&"_NextTex", tex)
	_set_bounds(mat, &"_NextBounds", tex)

func _set_bounds(mat: ShaderMaterial, slot: StringName, tex: Texture2D) -> void:
	var bounds := TextureCache.FULL_BOUNDS
	if tex != null:
		bounds = ModelLoader.textures.bounds_of(tex)
	mat.set_shader_parameter(slot, TextureCache.bounds_to_vec4(bounds))

func _set_next_tex(tex: Texture2D) -> void:
	_next_tex_current = tex
	_set_next_tex_on(model_render.material as ShaderMaterial, tex)

func _cancel_master_tween() -> void:
	_active_tween = NodeUtil.stop_tween(_active_tween)

func _finish_state_transition() -> void:
	_transitioning = false
	_out_track.clear()
	var tex := _next_tex_current
	_next_tex_current = null
	if tex != null:
		_commit_texture(tex)

func _snapshot_outgoing_track() -> void:
	if _track.is_running() and _track.entry != null and not _track.frames.is_empty():
		_out_track.frames = _track.frames.duplicate()
		_out_track.index = _track.index
		_out_track.entry = _track.entry

func _start_out_track() -> void:
	if _out_track.frames.is_empty() or _out_track.entry == null:
		return
	_out_track.start(_entry_fps(_out_track.entry))

func _advance_out() -> void:
	if not _transitioning or _out_track.frames.is_empty() or model_render == null:
		_out_track.clear()
		return
	_out_track.advance()
	var out_tex := _out_track.frames[_out_track.index]
	if out_tex == null:
		return
	_set_current_tex(model_render.material as ShaderMaterial, out_tex)

func _start_frame_animation(state: ModelStateEntry) -> void:
	if model_render == null:
		push_warning(TAG + "Cannot start frame animation: model_render is null.")
		return
	if state.frames.is_empty():
		return
	_track.entry = state
	_track.index = 0
	show_static(state)
	_track.frames = ModelLoader.textures.state_frame_array(state)
	_track.index = _snap_start_index(state, ModelLoader.textures.has_all_thumbs(state))
	ModelLoader.textures.request_frame_window(state, _track.index, HOT_WINDOW, _track.frames, self, func(ready: int) -> void:
		_on_frames_buffered(state, ready)
	)

func _on_frames_buffered(state: ModelStateEntry, _ready: int) -> void:
	if _track.entry != state or _track.frames.is_empty():
		return
	_show_track_frame()
	if _is_looping():
		_start_burst_timer()
	else:
		_start_cycle_timer()

func _show_track_frame() -> void:
	var tex := _track.frames[_track.index]
	if tex == null:
		return
	if _transitioning:
		_set_next_tex(tex)
	else:
		_commit_texture(tex)

func _stream_lookahead() -> void:
	var state := _track.entry
	if state == null or _track.frames.is_empty():
		return
	var size := _track.frames.size()
	ModelLoader.textures.request_state_frame(state, (_track.index + HOT_LOOKAHEAD) % size, _track.frames, self)
	if size > (HOT_LOOKAHEAD + 1) * 2:
		_track.frames[(_track.index - HOT_LOOKAHEAD - 1 + size) % size] = null
	if not _snap_start_cache.has(state) and ModelLoader.textures.has_all_thumbs(state):
		_snap_start_cache[state] = ModelLoader.textures.snap_start_index(state, _applied_tex)

func _snap_start_index(state: ModelStateEntry, complete: bool) -> int:
	if _snap_start_cache.has(state):
		return _snap_start_cache[state]
	var best := ModelLoader.textures.snap_start_index(state, _applied_tex)
	if complete:
		_snap_start_cache[state] = best
	return best

func _start_cycle_timer() -> void:
	_cycle_timer = NodeUtil.ensure_timer(self, _cycle_timer, _on_cycle_done, true)
	_cycle_timer.wait_time = maxf(_entry_chance(_track.entry), 0.1)
	_cycle_timer.start()

func _start_burst_timer() -> void:
	if _track.entry == null:
		return
	if not _track.entry.loop_animation:
		_anim_frames_left = _track.frames.size()
	_track.start(_entry_fps(_track.entry))

func _entry_fps(entry: ModelStateEntry) -> float:
	var global_rate := ModelLoader.model_loaded.global_frame_rate if ModelLoader.model_loaded != null else 0.0
	return entry.effective_frame_rate(global_rate)

func _entry_chance(entry: ModelStateEntry) -> float:
	var global_chance := ModelLoader.model_loaded.global_animation_chance if ModelLoader.model_loaded != null else 0.0
	return entry.effective_animation_chance(global_chance)

func _on_cycle_done() -> void:
	_start_burst_timer()

func _stop_frames() -> void:
	_track.clear()
	_cycle_timer = NodeUtil.free_timer(_cycle_timer)
	_anim_frames_left = 0

func _advance_frame() -> void:
	if model_render == null or _track.frames.is_empty():
		_track.stop()
		return
	_track.advance()
	_stream_lookahead()
	var next_tex := _track.frames[_track.index]
	if next_tex == null:
		return
	if _transitioning:
		_set_next_tex(next_tex)
	else:
		_commit_texture(next_tex)
	if not _is_looping():
		_anim_frames_left -= 1
		if _anim_frames_left <= 0:
			_track.stop()
			if _track.entry != null:
				show_static(_track.entry)
				_start_cycle_timer()

func _is_looping() -> bool:
	return _track.entry != null and _track.entry.loop_animation

static func _shader_for(value: int) -> Shader:
	if value == CanvasItem.TEXTURE_FILTER_NEAREST:
		if _nearest_shader == null:
			var base: Shader = load(MODEL_SHADER)
			var shader := Shader.new()
			shader.code = base.code.replace("filter_linear", "filter_nearest")
			_nearest_shader = shader
		return _nearest_shader
	if _linear_shader == null:
		_linear_shader = load(MODEL_SHADER)
	return _linear_shader
