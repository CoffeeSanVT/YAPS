class_name UpdateModelTransform
extends Control

const CONTROLLER_GROUP := &"model_transform_controller"

static func find_controller(tree: SceneTree) -> UpdateModelTransform:
	return tree.get_first_node_in_group(CONTROLLER_GROUP) as UpdateModelTransform

var _current_position: Vector2 = Vector2.ZERO
var _current_scale: float = 1.0
var _current_rotation: float = 0.0
var _active_tween: Tween
var _hold_preset: TransformPreset
var _hold_trigger: KeyHolding
var _hold_position: Vector2 = Vector2.ZERO
var _hold_scale: float = 1.0
var _hold_rotation: float = 0.0

func _ready() -> void:
	add_to_group(CONTROLLER_GROUP)
	_apply_default_preset()
	pivot_offset = size * 0.5

func _exit_tree() -> void:
	_release_hold_trigger()

func apply_position(value: Vector2) -> void:
	_tween_position(value)

func apply_scale(value: float) -> void:
	_tween_scale(value)

func apply_rotation(value: float) -> void:
	_tween_rotation(value)

func apply_preset(preset: TransformPreset) -> void:
	_apply_preset(preset)

func _apply_default_preset() -> void:
	var model := ModelLoader.model_loaded
	if model == null:
		return
	for preset in model.transform_presets:
		if preset.is_default:
			_apply_preset(preset, true)
			return

func _apply_offsets() -> void:
	offset_transform_position_ratio = _current_position

func _tween_position(value: Vector2) -> void:
	_current_position = value
	_apply_offsets()
	_emit_values()

func _tween_scale(value: float) -> void:
	_current_scale = value
	offset_transform_scale = Vector2(value, value)
	_emit_values()

func _tween_rotation(value: float) -> void:
	_current_rotation = value
	offset_transform_rotation = value
	_emit_values()

func _emit_values() -> void:
	SignalBus.model_transform_values.emit(_current_position, _current_scale, _current_rotation)

func _apply_preset(preset: TransformPreset, instant: bool = false) -> void:
	if preset == null:
		return
	_active_tween = NodeUtil.stop_tween(_active_tween)
	_track_hold_preset(preset)
	if instant or not preset.interpolate:
		_set_preset_values(preset.position, preset.scale_value, preset.rotation)
		return
	_tween_transform(preset.position, preset.scale_value, preset.rotation, preset)

func _track_hold_preset(preset: TransformPreset) -> void:
	var hold_trigger := preset.trigger as KeyHolding
	if hold_trigger == null:
		return
	_hold_preset = preset
	_hold_trigger = hold_trigger
	_hold_position = _current_position
	_hold_scale = _current_scale
	_hold_rotation = _current_rotation
	NodeUtil.connect_once(hold_trigger, &"enabled_changed", _on_hold_trigger_changed)

func _on_hold_trigger_changed(trigger: BaseTrigger) -> void:
	if trigger.enabled or trigger != _hold_trigger:
		return
	var preset := _hold_preset
	_release_hold_trigger()
	_active_tween = NodeUtil.stop_tween(_active_tween)
	_tween_transform(_hold_position, _hold_scale, _hold_rotation, preset)

func _release_hold_trigger() -> void:
	if _hold_trigger == null:
		return
	NodeUtil.safe_disconnect(_hold_trigger, &"enabled_changed", _on_hold_trigger_changed)
	_hold_trigger = null
	_hold_preset = null

func _tween_transform(pos: Vector2, sc: float, rot: float, preset: TransformPreset) -> void:
	if not preset.interpolate:
		_set_preset_values(pos, sc, rot)
		return

	var start_pos := _current_position
	var start_scale_val := _current_scale
	var start_rot := _current_rotation

	_active_tween = create_tween().set_parallel(true)
	_active_tween.set_ease(preset.ease_type as Tween.EaseType)
	_active_tween.set_trans(preset.trans_type as Tween.TransitionType)
	_active_tween.tween_method(_tween_position, start_pos, pos, preset.duration)
	_active_tween.tween_method(_tween_scale, start_scale_val, sc, preset.duration)
	_active_tween.tween_method(_tween_rotation, start_rot, rot, preset.duration)
	_active_tween.chain().tween_callback(func() -> void:
		_current_position = pos
		_current_scale = sc
		_current_rotation = rot
		_emit_values()
	)

func _set_preset_values(pos: Vector2, sc: float, rot: float) -> void:
	_tween_position(pos)
	_tween_scale(sc)
	_tween_rotation(rot)
