class_name Draggable
extends TextureRect

signal fade_out_done

enum States { NONE, SELECTED, PRESSED, DRAGGING, DISABLED }

const DRAG_THRESHOLD := 0.01
const MIN_SCALE := 0.1
const MAX_SCALE := 5.0
const WHEEL_ZOOM_UP := 1.1
const WHEEL_ZOOM_DOWN := 0.9
const SELECT_Z_OVERRIDE := 100

var fade_duration := 0.25
var _press_pos := Vector2.ZERO
var _drag_offset := Vector2.ZERO
var item: Item
var _fade_tween: Tween
var _outline: SelectionOutline
var _hit_tester := DragHitTester.new()
var _z_before_select := 0
var _z_boosted := false
var state := States.NONE:
	set(value):
		if state == value:
			return
		state = value
		match value:
			States.SELECTED:
				_update_selection_outline(true)
			States.NONE, States.DISABLED:
				_update_selection_outline(false)

func _outline_live() -> SelectionOutline:
	return _outline if is_instance_valid(_outline) else null

func _update_selection_outline(enabled: bool) -> void:
	if _outline_live() != null:
		_outline.cancel_tween()
	if enabled:
		_boost_z()
		_ensure_outline()
		_outline.tween_width(SelectionOutline.OUTLINE_WIDTH)
	elif _outline_live() != null:
		_outline.tween_width(0.0, _finish_outline_fade_out)
	else:
		_restore_z()

func _ensure_outline() -> void:
	if _outline_live() != null:
		return
	_outline = SelectionOutline.create(self, _texture_bounds())

func _texture_bounds() -> Rect2:
	return item.outline_bounds() if item != null else TextureCache.FULL_BOUNDS

func set_texture_bounds(bounds: Rect2) -> void:
	if _outline_live() != null:
		_outline.set_sprite_bounds(bounds)

func sync_outline_texture(_frame: int = -1) -> void:
	if _outline_live() != null:
		_outline.sync_texture(texture)

func _finish_outline_fade_out() -> void:
	if _outline_live() != null:
		_outline.queue_free()
	_outline = null
	_restore_z()

func _boost_z() -> void:
	if item != null and item.z_index >= 0:
		_z_boosted = false
		return
	if _z_boosted:
		return
	_z_boosted = true
	_z_before_select = z_index
	z_index = SELECT_Z_OVERRIDE

func _restore_z() -> void:
	if not _z_boosted:
		return
	_z_boosted = false
	z_index = item.z_index if item != null else _z_before_select

func apply_model_z(value: int) -> void:
	if (state == States.SELECTED or state == States.DRAGGING) and value < 0:
		_z_boosted = true
		z_index = SELECT_Z_OVERRIDE
		return
	if _z_boosted:
		_z_boosted = false
	z_index = value

func _ready() -> void:
	pivot_offset = size * 0.5

func _process(_delta: float) -> void:
	sync_outline_texture()
	if state == States.DISABLED or not visible:
		_unwind_drag()
		return
	if not get_window().has_focus():
		_end_drag()
		return
	var mouse := _viewport_to_ratio(_get_mouse_in_viewport())
	var button := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not DragSession.select_menu_open

	if button and state != States.PRESSED and state != States.DRAGGING:
		state = States.PRESSED
		_press_pos = mouse
		_drag_offset = Vector2.ZERO
	elif button and state == States.PRESSED and mouse.distance_to(_press_pos) > DRAG_THRESHOLD:
		if _can_start_drag_at(_press_pos):
			_drag_offset = _viewport_to_ratio(offset_transform_position + pivot_offset) - mouse
			DragSession.active_draggable = self
			state = States.DRAGGING

	if state == States.DRAGGING:
		offset_transform_position = _ratio_to_viewport(mouse + _drag_offset) - pivot_offset
		if item != null:
			item.position = mouse + _drag_offset
			item.transform_changed.emit()

	if not button:
		_end_drag()

func is_opaque_at_viewport(viewport_pos: Vector2) -> bool:
	return _hit_tester.is_opaque_at(self, viewport_pos)

func _is_opaque_at(parent_pos_ratio: Vector2) -> bool:
	return is_opaque_at_viewport(_ratio_to_viewport(parent_pos_ratio))

func is_dragging() -> bool:
	return state == States.DRAGGING

func set_selected(value: bool) -> bool:
	if state == States.DISABLED or state == States.DRAGGING or state == States.PRESSED:
		return false
	state = States.SELECTED if value else States.NONE
	return true

func _is_still_selected() -> bool:
	return is_instance_valid(DragSession.selected_draggable) and DragSession.selected_draggable == self

func _end_drag() -> void:
	if state == States.DRAGGING and item != null:
		item.schedule_save()
	_unwind_drag()

func _unwind_drag() -> void:
	if state == States.DRAGGING or state == States.PRESSED:
		state = States.SELECTED if _is_still_selected() else States.NONE
	if DragSession.active_draggable == self:
		DragSession.active_draggable = null

func _viewport_to_ratio(viewport_pos: Vector2) -> Vector2:
	return DragSession.viewport_to_ratio(viewport_pos, Vector2(get_viewport().size))

func _ratio_to_viewport(ratio: Vector2) -> Vector2:
	return DragSession.ratio_to_viewport(ratio, Vector2(get_viewport().size))

func _get_mouse_in_viewport() -> Vector2:
	return DragSession.mouse_in_viewport(get_viewport().get_parent() as SubViewportContainer, get_viewport())

func scale_wheel(up: bool) -> void:
	var current := offset_transform_scale.x
	var new_scale := current * (WHEEL_ZOOM_UP if up else WHEEL_ZOOM_DOWN)
	new_scale = clampf(new_scale, MIN_SCALE, MAX_SCALE)
	offset_transform_scale = Vector2(new_scale, new_scale)
	if item != null:
		item.scale = Vector2(new_scale, new_scale)
		item.transform_changed.emit()
		item.schedule_save()

func get_scaled_rect() -> Rect2:
	var s := offset_transform_scale
	var pos := offset_transform_position
	return Rect2(pos + (Vector2.ONE - s) * pivot_offset, size * s)

func _is_top_control_at(pos_ratio: Vector2) -> bool:
	var nodes := get_tree().get_nodes_in_group(DragSession.MODEL_ITEMS_GROUP)
	return DragSession.topmost_among(nodes, _ratio_to_viewport(pos_ratio)) == self

func _can_start_drag_at(pos_ratio: Vector2) -> bool:
	if _other_drag_active():
		return false
	if not _is_opaque_at(pos_ratio):
		return false
	var selected := valid_selected_draggable()
	if selected == self:
		return true
	if selected != null and selected.is_opaque_at_viewport(_ratio_to_viewport(pos_ratio)):
		return false
	return _is_top_control_at(pos_ratio)

static func _other_drag_active(except: Draggable = null) -> bool:
	if not is_instance_valid(DragSession.active_draggable):
		return false
	return DragSession.active_draggable != except and DragSession.active_draggable.is_dragging()

static func valid_selected_draggable() -> Draggable:
	if not is_instance_valid(DragSession.selected_draggable):
		return null
	if not DragSession.selected_draggable.visible or DragSession.selected_draggable.state == States.DISABLED:
		return null
	return DragSession.selected_draggable

func set_visible_with_fade(should_show: bool) -> void:
	_fade_tween = NodeUtil.stop_tween(_fade_tween)
	_fade_tween = create_tween()
	if should_show:
		state = States.SELECTED if _is_still_selected() else States.NONE
		modulate.a = 0.0
		visible = true
		_fade_tween.tween_property(self, "modulate:a", 1.0, fade_duration)
	else:
		_fade_tween.tween_property(self, "modulate:a", 0.0, fade_duration)
		_fade_tween.tween_callback(_on_fade_out_done)

func _on_fade_out_done() -> void:
	visible = false
	state = States.DISABLED
	_fade_tween = null
	if item != null:
		var player := item.get_animation_player()
		if player != null:
			player.Pause()
	fade_out_done.emit()
