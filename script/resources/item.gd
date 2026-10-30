class_name Item
extends Resource

@warning_ignore("unused_signal")
signal transform_changed
signal enabled_changed(value: bool)
signal animation_ready

const TAG := "[Item] "
const MAX_IMAGE_SIZE := Vector2(800.0, 800.0)
const ANIM_PREFETCH := 4
const Z_MIN := -99
const Z_MAX := 99


@export_category("Identity")
@export var state_name: String = ""
@export_file("*.png", "*.apng", "*.gif", "*.webp", "*.webm") var asset_path: String = ""
@export var state_trigger: BaseTrigger = BaseTrigger.new()
@export var twitch_event: TwitchEvent = null

@export_category("Transform")
@export var position: Vector2
@export var scale: Vector2
@export var rotation: float = 0.0
@export_range(Z_MIN, Z_MAX) var z_index: int = 1:
	set(value):
		var normalized := clampi(value, Z_MIN, Z_MAX)
		if normalized == 0:
			normalized = 1 if z_index <= 0 else -1
		if z_index == normalized:
			return
		z_index = normalized
		apply_z_index()
@export var enabled: bool = false
@export var is_fixed_to_model: bool = true

@export_category("Transform Presets")
@export var transform_presets: Array[ItemTransformPreset] = []

@export_category("Animation")
@export var animation_loop: bool = true

var instance: Draggable
var animation_data: Variant
var _animation_cache_path: String = ""
var _outline_bounds: Rect2 = TextureCache.FULL_BOUNDS
var _decoder := ItemAnimationDecoder.new()
var _frame_leases: Dictionary[int, String] = {}
var _requested_frames: Dictionary[int, bool] = {}
var _failed_frames: Dictionary[int, bool] = {}
var _playback_held: bool = false
var _auto_hide_timer: Timer
var _fading_out: bool = false
var _active_preset: ItemTransformPreset
var _current_expression: String = ""
var _current_position: Vector2 = Vector2.ZERO
var _current_scale: float = 1.0
var _current_rotation: float = 0.0
var _preset_tween: Tween

func _init(name: String = "", path: String = "") -> void:
	state_name = name
	asset_path = path

func _live_instance() -> Draggable:
	return instance if is_instance_valid(instance) else null

func _get_real_path() -> String:
	return PathUtil.get_real_path(asset_path)

func load_image() -> Texture2D:
	var full_path := _get_real_path()
	if _has_animation_cache() and animation_data.Frames[0] != null:
		return animation_data.Frames[0]
	var decoded := ImageUtil.load_texture_with_rect(asset_path, MAX_IMAGE_SIZE)
	var tex: Texture2D = decoded.texture
	if tex == null:
		push_error(TAG + "load_image: failed to decode texture: " + full_path)
		return null
	_apply_outline_bounds(decoded.used_rect, tex)
	if enabled:
		ensure_animation()
	return tex

func load_thumbnail(max_size: Vector2 = Vector2(112.0, 112.0)) -> Texture2D:
	if _has_animation_cache() and animation_data.Frames[0] != null:
		return animation_data.Frames[0]
	var live := _live_instance()
	if live != null and live.texture != null:
		return live.texture
	return ImageUtil.load_thumbnail_texture(asset_path, max_size)

func _has_animation_cache() -> bool:
	return animation_data != null and _animation_cache_path == asset_path

func ensure_animation(source_path: String = "") -> void:
	if _has_animation_cache() or _decoder.is_busy():
		return
	var check_path := PathUtil.get_real_path(source_path) if not source_path.is_empty() else _get_real_path()
	if not ImageUtil.is_animated_file(check_path):
		return
	_decoder.request(asset_path, _on_frames_decoded, self, source_path)

func outline_bounds() -> Rect2:
	return _outline_bounds

func is_decoding() -> bool:
	return _decoder.is_busy()

func cancel_animation() -> void:
	_decoder.cancel()

func _apply_outline_bounds(used_rect: Rect2i, texture: Texture2D) -> void:
	if texture == null or used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return
	_outline_bounds = TextureCache.normalized_bounds(texture, used_rect)

func _on_frames_decoded(data: AnimatedImageData) -> void:
	set_animation_data(data)
	if _live_instance() != null:
		_attach_animation_player()
		instance.set_texture_bounds(_outline_bounds)
	animation_ready.emit()

func set_animation_data(data: Variant) -> void:
	_release_all_frames()
	animation_data = data
	_animation_cache_path = asset_path
	if data != null and data.UnionRect.size.x > 0 and data.UnionRect.size.y > 0:
		var first: Texture2D = data.Frames[0] if data.Frames.size() > 0 else null
		if first != null:
			_apply_outline_bounds(data.UnionRect, first)

static func fit_size(image_size: Vector2) -> Vector2:
	var fitted := image_size
	var ratio := MAX_IMAGE_SIZE / fitted
	return fitted * min(ratio.x, ratio.y)

func instantiate_in_scene(parent: Node) -> Draggable:
	if parent == null:
		push_error(TAG + "Item.instantiate_in_scene: parent is null")
		return null
	var texture := load_image()
	if texture == null:
		push_error(TAG + "Item.instantiate_in_scene: failed to load image from '%s'" % asset_path)
		return null
	var texture_rect := DragSession.create_for_item(texture, self)
	texture_rect.visible = enabled
	instance = texture_rect
	parent.add_child(texture_rect)
	apply_transform_to_instance()
	apply_z_index()
	_attach_animation_player()
	return texture_rect

func _attach_animation_player() -> void:
	if _live_instance() == null or animation_data == null:
		return
	if get_animation_player() != null:
		return
	var player := AnimatedImageRuntime.AttachPlayer(animation_data, instance)
	if player != null:
		player.Loop = animation_loop
		if not enabled or _playback_held:
			player.Pause()
		NodeUtil.connect_once(player, &"FrameChanged", instance.sync_outline_texture)
		NodeUtil.connect_once(player, &"FrameChanged", _on_player_frame_changed)
		NodeUtil.connect_once(player, &"FrameNeeded", _on_player_frame_needed)
		if enabled and not _playback_held:
			_prefetch_frames(player, player.CurrentFrame)

func set_playback_held(value: bool) -> void:
	if _playback_held == value:
		return
	_playback_held = value
	if _playback_held:
		pause_animation()
		return
	if enabled:
		play_animation()

func play_animation() -> void:
	var player := get_animation_player()
	if player == null:
		return
	if _playback_held or not enabled:
		player.Pause()
		return
	player.Stop()
	player.Play()

func pause_animation() -> void:
	var player := get_animation_player()
	if player != null:
		player.Pause()

func _on_player_frame_changed(_frame: int) -> void:
	var player := get_animation_player()
	if player != null:
		_prefetch_frames(player, player.CurrentFrame)

func _on_player_frame_needed(frame: int) -> void:
	var player := get_animation_player()
	if player != null:
		_prefetch_frames(player, frame)

func _prefetch_frames(player: AnimatedImagePlayer, index: int) -> void:
	if not enabled or _playback_held:
		return
	var count: int = player.FrameCount
	if count <= 0:
		return
	var window: Array[int] = []
	for offset in ANIM_PREFETCH:
		var target := ((index + offset) % count) if player.Loop else mini(index + offset, count - 1)
		window.append(target)
		_request_frame(target)
	_release_frames(window)

func _release_frames(window: Array[int]) -> void:
	var data: AnimatedImageData = animation_data
	for index: int in _frame_leases.keys():
		if window.has(index):
			continue
		var path := _frame_leases[index]
		_frame_leases.erase(index)
		_requested_frames.erase(index)
		_failed_frames.erase(index)
		if data != null and data.Frames != null and index < data.Frames.size():
			data.SetFrameTexture(index, null)
		ModelLoader.textures.release_texture(path, false)

func _release_all_frames() -> void:
	for path: String in _frame_leases.values():
		ModelLoader.textures.release_texture(path)
	_frame_leases.clear()
	_requested_frames.clear()
	_failed_frames.clear()
	var data: AnimatedImageData = animation_data
	if data == null:
		return
	if data.FramePaths != null:
		for path: String in data.FramePaths:
			ModelLoader.textures.evict_unleased(path)
	if data.Frames == null:
		return
	for index in data.Frames.size():
		data.SetFrameTexture(index, null)

func reset_animation_textures() -> void:
	_frame_leases.clear()
	_requested_frames.clear()
	_failed_frames.clear()
	var data: AnimatedImageData = animation_data
	if data == null or data.Frames == null:
		return
	for index in data.Frames.size():
		data.SetFrameTexture(index, null)

func _request_frame(index: int) -> void:
	var data: AnimatedImageData = animation_data
	if data == null or data.Frames == null or data.FramePaths == null:
		return
	if index < 0 or index >= data.FramePaths.size() or index >= data.Frames.size() or _frame_leases.has(index):
		return
	var path: String = data.FramePaths[index]
	if path.is_empty():
		return
	_frame_leases[index] = path
	ModelLoader.textures.acquire_texture(path)
	if data.Frames[index] != null:
		return
	_requested_frames[index] = true
	ModelLoader.textures.request_texture(path, func(tex: ImageTexture) -> void:
		_requested_frames.erase(index)
		if animation_data != data or _frame_leases.get(index, "") != path:
			return
		if tex == null:
			_failed_frames[index] = true
			return
		data.SetFrameTexture(index, tex)
		if index == 0:
			_apply_outline_bounds(data.UnionRect, tex)
			if _live_instance() != null:
				instance.set_texture_bounds(_outline_bounds)
				var player := get_animation_player()
				if player == null or player.CurrentFrame == 0:
					instance.texture = tex
	, self, MAX_IMAGE_SIZE)

func reparent_for_fixed(free_parent: Node, fixed_parent: Node) -> void:
	if _live_instance() == null:
		return
	var target := fixed_parent if is_fixed_to_model else free_parent
	if target == null or instance.get_parent() == target:
		return
	instance.get_parent().remove_child(instance)
	target.add_child(instance)

func apply_z_index() -> void:
	if _live_instance() == null:
		return
	instance.apply_model_z(z_index)

func effective_scale() -> float:
	return scale.x if scale != Vector2.ZERO else 1.0

func apply_transform_to_instance() -> void:
	_preset_tween = NodeUtil.stop_tween(_preset_tween)
	_set_current_transform(position, effective_scale(), rotation)

func refresh_transform_to_instance() -> void:
	_sync_current_transform_from_instance()
	_apply_current_transform()

func stop_transform_tween() -> void:
	_preset_tween = NodeUtil.stop_tween(_preset_tween)
	_sync_current_transform_from_instance()

func has_preset_named(preset_name: String, excluding: ItemTransformPreset = null) -> bool:
	for preset in transform_presets:
		if preset != excluding and preset.preset_name.to_lower() == preset_name.to_lower():
			return true
	return false

func has_preset_for_expression(expression_name: String, excluding: ItemTransformPreset = null) -> bool:
	if expression_name.is_empty():
		return false
	for preset in transform_presets:
		if preset != excluding and preset.expression_name.to_lower() == expression_name.to_lower():
			return true
	return false

func preset_for_expression(expression_name: String) -> ItemTransformPreset:
	if expression_name.is_empty():
		return null
	for preset in transform_presets:
		if preset.expression_name.to_lower() == expression_name.to_lower():
			return preset
	return null

func apply_expression(expression_name: String, instant: bool = false) -> void:
	_current_expression = expression_name
	_apply_preset(preset_for_expression(expression_name), instant)

func refresh_expression_preset(instant: bool = false) -> void:
	apply_expression(_current_expression, instant)

func current_expression_name() -> String:
	return _current_expression

func displayed_position() -> Vector2:
	if _live_instance() == null:
		return position
	_sync_current_transform_from_instance()
	return _current_position

func displayed_scale() -> float:
	if _live_instance() == null:
		return effective_scale()
	_sync_current_transform_from_instance()
	return _current_scale

func displayed_rotation() -> float:
	if _live_instance() == null:
		return rotation
	_sync_current_transform_from_instance()
	return _current_rotation

func apply_preset(preset: ItemTransformPreset, instant: bool = false) -> void:
	_apply_preset(preset, instant)

func _apply_preset(preset: ItemTransformPreset, instant: bool) -> void:
	var transition := preset if preset != null else _active_preset
	_active_preset = preset
	var target_position := preset.position if preset != null else position
	var target_scale := preset.scale_value if preset != null else effective_scale()
	var target_rotation := preset.rotation if preset != null else rotation

	_preset_tween = NodeUtil.stop_tween(_preset_tween)
	_sync_current_transform_from_instance()
	var live := _live_instance()
	if instant or transition == null or not transition.interpolate or live == null:
		_set_current_transform(target_position, target_scale, target_rotation)
		return

	var start_position := _current_position
	var start_scale := _current_scale
	var start_rotation := _current_rotation
	_preset_tween = live.create_tween().set_parallel(true)
	_preset_tween.set_ease(transition.ease_type as Tween.EaseType)
	_preset_tween.set_trans(transition.trans_type as Tween.TransitionType)
	_preset_tween.tween_method(_set_current_position, start_position, target_position, transition.duration)
	_preset_tween.tween_method(_set_current_scale, start_scale, target_scale, transition.duration)
	_preset_tween.tween_method(_set_current_rotation, start_rotation, target_rotation, transition.duration)
	_preset_tween.chain().tween_callback(func() -> void:
		_preset_tween = null
		_set_current_transform(target_position, target_scale, target_rotation)
	)

func _set_current_position(value: Vector2) -> void:
	_current_position = value
	_apply_current_transform()

func _set_current_scale(value: float) -> void:
	_current_scale = value
	_apply_current_transform()

func _set_current_rotation(value: float) -> void:
	_current_rotation = value
	_apply_current_transform()

func _set_current_transform(pos: Vector2, sc: float, rot: float) -> void:
	_current_position = pos
	_current_scale = sc
	_current_rotation = rot
	_apply_current_transform()

func _sync_current_transform_from_instance() -> void:
	var live := _live_instance()
	if live == null:
		return
	var vp := live.get_viewport()
	var vp_size := Vector2(vp.size) if vp != null else Vector2.ONE
	_current_position = DragSession.viewport_to_ratio(live.offset_transform_position + live.pivot_offset, vp_size)
	_current_scale = live.offset_transform_scale.x
	_current_rotation = live.offset_transform_rotation

func _apply_current_transform() -> void:
	var live := _live_instance()
	if live == null:
		return
	var vp := live.get_viewport()
	var vp_size := Vector2(vp.size) if vp != null else Vector2.ONE
	live.offset_transform_position = DragSession.ratio_to_viewport(_current_position, vp_size) - live.pivot_offset
	live.offset_transform_scale = Vector2(_current_scale, _current_scale)
	live.offset_transform_rotation = _current_rotation

func get_animation_player() -> AnimatedImagePlayer:
	var live := _live_instance()
	if live == null:
		return null
	return live.get_node_or_null("AnimatedImagePlayer") as AnimatedImagePlayer

func set_enabled(value: bool) -> void:
	if value:
		if enabled and not _fading_out:
			_restart_auto_hide_timer()
			return
		_fading_out = false
		enabled = true
		_sync_triggers(true)
		enabled_changed.emit(true)
		_fade_instance(true)
		ensure_animation()
		play_animation()
		update_auto_hide_timer()
		schedule_save()
	else:
		if not enabled or _fading_out:
			return
		_fading_out = true
		_sync_triggers(false)
		_fade_instance(false)
		_clear_auto_hide_timer()

func _finalize_disable() -> void:
	_fading_out = false
	if not enabled:
		return
	enabled = false
	pause_animation()
	_release_all_frames()
	_clear_instance_texture()
	enabled_changed.emit(false)
	schedule_save()

func _clear_instance_texture() -> void:
	var live := _live_instance()
	if live == null:
		return
	live.texture = null

func _restore_instance_texture() -> void:
	if _live_instance() == null or instance.texture != null:
		return
	if _has_animation_cache():
		return
	instance.texture = load_image()

func update_auto_hide_timer() -> void:
	_clear_auto_hide_timer()
	if not enabled:
		return
	var trigger := _settings_trigger()
	if trigger == null:
		return
	if trigger.auto_hide_after <= 0.0:
		return
	if _live_instance() == null:
		return
	_auto_hide_timer = NodeUtil.ensure_timer(instance, _auto_hide_timer, _on_auto_hide_timeout, true)
	_auto_hide_timer.wait_time = trigger.auto_hide_after
	_auto_hide_timer.start()

func _settings_trigger() -> BaseTrigger:
	if state_trigger != null and state_trigger.trigger_name != &"":
		return state_trigger
	return twitch_event

func _restart_auto_hide_timer() -> void:
	if _auto_hide_timer != null:
		_auto_hide_timer.start()

func _clear_auto_hide_timer() -> void:
	_auto_hide_timer = NodeUtil.free_timer(_auto_hide_timer)

func _on_auto_hide_timeout() -> void:
	if state_trigger != null and state_trigger.enabled:
		state_trigger.set_enabled(false)
	if twitch_event != null and twitch_event.enabled:
		twitch_event.set_enabled(false)
	set_enabled(false)

func _fade_instance(show: bool) -> void:
	if _live_instance() == null:
		_finalize_disable()
		return
	var trigger := _settings_trigger()
	if trigger != null:
		instance.fade_duration = trigger.fade_duration
	if show:
		_restore_instance_texture()
	instance.set_visible_with_fade(show)
	if not show:
		NodeUtil.connect_once(instance, &"fade_out_done", _on_fade_out_done)

func _on_fade_out_done() -> void:
	_finalize_disable()

func _sync_triggers(value: bool) -> void:
	if state_trigger != null:
		state_trigger.enabled = value
	if twitch_event != null:
		twitch_event.enabled = value

func set_trigger(new_trigger: BaseTrigger) -> void:
	if state_trigger == new_trigger:
		return
	state_trigger = _replace_trigger(state_trigger, new_trigger)
	activate_trigger()

func set_twitch_event(new_event: TwitchEvent) -> void:
	if twitch_event == new_event:
		return
	twitch_event = _replace_trigger(twitch_event, new_event)
	_activate_trigger(twitch_event, &"event_type")

func activate_trigger() -> void:
	_activate_trigger(state_trigger, &"trigger_name")

func activate_twitch_event() -> void:
	_activate_trigger(twitch_event, &"event_type")

func _replace_trigger(current: BaseTrigger, new_trigger: BaseTrigger) -> BaseTrigger:
	NodeUtil.safe_disconnect(current, &"enabled_changed", _on_trigger_enabled_changed)
	if current != null:
		current.deactivate()
	return new_trigger

func _activate_trigger(trigger: BaseTrigger, readiness: StringName) -> void:
	if trigger == null or trigger.get(readiness) == &"":
		return
	trigger.enabled = enabled
	trigger.bind_changed(_on_trigger_enabled_changed)

func deactivate_triggers() -> void:
	for trigger: BaseTrigger in [state_trigger, twitch_event]:
		if trigger == null:
			continue
		NodeUtil.safe_disconnect(trigger, &"enabled_changed", _on_trigger_enabled_changed)
		trigger.deactivate()
		trigger.enabled = false

func release_runtime() -> void:
	_preset_tween = NodeUtil.stop_tween(_preset_tween)
	cancel_animation()
	_release_all_frames()
	animation_data = null
	_animation_cache_path = ""
	_outline_bounds = TextureCache.FULL_BOUNDS
	if _live_instance() != null:
		instance.queue_free()
	instance = null

func destroy() -> void:
	release_runtime()
	deactivate_triggers()
	_clear_auto_hide_timer()

func _on_trigger_enabled_changed(trigger: BaseTrigger) -> void:
	if _should_defer_twitch_hide(trigger):
		return
	set_enabled(trigger.enabled)
	schedule_save()

func _should_defer_twitch_hide(trigger: BaseTrigger) -> bool:
	var twitch := trigger as TwitchEvent
	if twitch == null or twitch != twitch_event or twitch.enabled:
		return false
	var settings := _settings_trigger()
	return settings != null and settings.auto_hide_after > 0.0 and enabled and not _fading_out

func schedule_save() -> void:
	ModelLoader.save_model()
