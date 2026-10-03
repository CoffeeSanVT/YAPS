class_name Item
extends Resource

@warning_ignore("unused_signal")
signal transform_changed
signal enabled_changed(value: bool)

const TAG := "[Item] "
const MAX_IMAGE_SIZE := Vector2(800.0, 800.0)
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

@export_category("Animation")
@export var animation_loop: bool = true

var instance: Draggable
var animation_data: Variant
var _animation_cache_path: String = ""
var _outline_bounds: Rect2 = TextureCache.FULL_BOUNDS
var _decoder := ItemAnimationDecoder.new()
var _auto_hide_timer: Timer
var _fading_out: bool = false

func _init(name: String = "", path: String = "") -> void:
	state_name = name
	asset_path = path

func _live_instance() -> Draggable:
	return instance if is_instance_valid(instance) else null

func _get_real_path() -> String:
	return PathUtil.get_real_path(asset_path)

func load_image() -> Texture2D:
	var full_path := _get_real_path()
	if animation_data != null and _animation_cache_path == asset_path:
		return animation_data.Frames[0]
	var decoded := ImageUtil.load_texture_with_rect(asset_path)
	var tex: Texture2D = decoded.texture
	if tex == null:
		push_error(TAG + "load_image: failed to decode texture: " + full_path)
		return null
	_apply_outline_bounds(decoded.used_rect, tex)
	if animation_data == null and ImageUtil.is_animated_file(full_path):
		_decoder.request(full_path, _on_frames_decoded, self)
	return tex

func outline_bounds() -> Rect2:
	return _outline_bounds

func is_decoding() -> bool:
	return _decoder.is_busy()

func _apply_outline_bounds(used_rect: Rect2i, texture: Texture2D) -> void:
	if texture == null or used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return
	_outline_bounds = TextureCache.normalized_bounds(texture, used_rect)

func _on_frames_decoded(data: AnimatedImageData) -> void:
	set_animation_data(data)
	if _live_instance() != null:
		_attach_animation_player()
		instance.set_texture_bounds(_outline_bounds)

func set_animation_data(data: Variant) -> void:
	animation_data = data
	_animation_cache_path = asset_path
	if data != null and data.UnionRect.size.x > 0 and data.UnionRect.size.y > 0:
		_apply_outline_bounds(data.UnionRect, data.Frames[0])

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
		if not enabled:
			player.Pause()
		NodeUtil.connect_once(player, &"frame_changed", instance.sync_outline_texture)

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
	if _live_instance() == null:
		return
	var vp := instance.get_viewport()
	var vp_size := Vector2(vp.size) if vp != null else Vector2(1, 1)
	instance.offset_transform_position = DragSession.ratio_to_viewport(position, vp_size) - instance.pivot_offset
	var s := effective_scale()
	instance.offset_transform_scale = Vector2(s, s)
	instance.offset_transform_rotation = rotation

func get_animation_player() -> AnimatedImagePlayer:
	var live := _live_instance()
	if live == null:
		return null
	return live.get_node_or_null("AnimatedImagePlayer") as AnimatedImagePlayer

func set_enabled(value: bool) -> void:
	if value:
		if enabled and not _fading_out:
			return
		_fading_out = false
		enabled = true
		_sync_triggers(true)
		enabled_changed.emit(true)
		_fade_instance(true)
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
	enabled_changed.emit(false)
	schedule_save()

func update_auto_hide_timer() -> void:
	_clear_auto_hide_timer()
	if not enabled:
		return
	if state_trigger == null:
		return
	if state_trigger.auto_hide_after <= 0.0:
		return
	if _live_instance() == null:
		return
	_auto_hide_timer = NodeUtil.ensure_timer(instance, _auto_hide_timer, _on_auto_hide_timeout, true)
	_auto_hide_timer.wait_time = state_trigger.auto_hide_after
	_auto_hide_timer.start()

func _clear_auto_hide_timer() -> void:
	_auto_hide_timer = NodeUtil.free_timer(_auto_hide_timer)

func _on_auto_hide_timeout() -> void:
	if state_trigger != null and state_trigger.enabled:
		state_trigger.set_enabled(false)
	set_enabled(false)

func _fade_instance(show: bool) -> void:
	if _live_instance() == null:
		_finalize_disable()
		return
	if state_trigger != null:
		instance.fade_duration = state_trigger.fade_duration
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

func destroy() -> void:
	deactivate_triggers()
	_clear_auto_hide_timer()
	if _live_instance() != null:
		instance.queue_free()
	instance = null

func _on_trigger_enabled_changed(trigger: BaseTrigger) -> void:
	set_enabled(trigger.enabled)
	schedule_save()

func schedule_save() -> void:
	ModelLoader.save_model()
