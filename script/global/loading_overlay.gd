extends CanvasLayer

const LOADING_DOT_INTERVAL := 0.4
const MIN_DISPLAY_MS := 800
const BG_SWEEP_TIME := 0.5
const TRANSITION_TIME := 0.5
const BG_DARK_ALPHA := 130.0 / 255.0

@onready var _screen: Control = $Screen
@onready var _bg_material: ShaderMaterial = $Screen/AnimatedBG.material as ShaderMaterial
@onready var _bg_dark: ColorRect = $Screen/BGDark
@onready var _status_label: Label = $Screen/CenterContainer/StatusLabel

var _status_text := ""
var _dot_count := 0
var _dots_timer: Timer
var _shown_at_ms: int = -1
var _bg_tween: Tween
var _bg_dark_tween: Tween
var _invert := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dots_timer = NodeUtil.ensure_timer(self, _dots_timer, _advance_dots, false)
	_dots_timer.wait_time = LOADING_DOT_INTERVAL

func show_loading(status: StringName, run_bg_loop := true) -> void:
	_dot_count = 0
	ApplicationState.set_loading(true)
	set_status(status)
	_status_label.show()
	_screen.show()
	_dots_timer.start()
	_shown_at_ms = Time.get_ticks_msec()
	_invert = false
	_tween_bg_dark(BG_DARK_ALPHA, Tween.EASE_OUT)
	await _play_transition(1.0, Tween.EASE_OUT, run_bg_loop)

func set_status(status: StringName) -> void:
	_status_text = status
	_refresh_status_label()

func hide_loading() -> void:
	ApplicationState.set_loading(false)
	if not _screen.visible:
		return
	if _shown_at_ms >= 0:
		var remaining_ms := MIN_DISPLAY_MS - (Time.get_ticks_msec() - _shown_at_ms)
		_shown_at_ms = -1
		if remaining_ms > 0:
			await get_tree().create_timer(remaining_ms / 1000.0).timeout
	_stop_bg_tween()
	_dots_timer.stop()
	_status_label.hide()
	_invert = true
	_tween_bg_dark(0.0, Tween.EASE_IN)
	await _play_transition(0.0, Tween.EASE_IN)
	_screen.hide()

func _tween_bg_dark(target_alpha: float, ease_type: Tween.EaseType) -> void:
	_bg_dark_tween = NodeUtil.stop_tween(_bg_dark_tween)
	_bg_dark_tween = create_tween()
	_bg_dark_tween.tween_property(_bg_dark, "self_modulate:a", target_alpha, TRANSITION_TIME).set_trans(Tween.TRANS_SINE).set_ease(ease_type)

func change_scene_to(status: StringName, scene_path: String) -> void:
	await show_loading(status, false)
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame
	await hide_loading()

func _play_transition(target: float, ease_type: Tween.EaseType, run_bg_loop := false) -> void:
	_stop_bg_tween()
	_bg_tween = create_tween()
	var start := float(_bg_material.get_shader_parameter(&"progress"))
	_bg_tween.tween_method(_set_progress, start, target, TRANSITION_TIME).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	if run_bg_loop:
		_bg_tween.finished.connect(_start_bg_tween, CONNECT_ONE_SHOT)
	await _bg_tween.finished

func _start_bg_tween() -> void:
	_stop_bg_tween()
	_invert = false
	_bg_tween = create_tween()
	_bg_tween.set_loops()
	_bg_tween.tween_callback(_flip_direction)
	_bg_tween.tween_method(_set_progress, 1.0, 0.0, BG_SWEEP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_bg_tween.tween_callback(_flip_direction)
	_bg_tween.tween_method(_set_progress, 0.0, 1.0, BG_SWEEP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_bg_tween.tween_callback(_flip_direction)

func _stop_bg_tween() -> void:
	_bg_tween = NodeUtil.stop_tween(_bg_tween)

func _flip_direction() -> void:
	_invert = not _invert

func _set_progress(value: float) -> void:
	_bg_material.set_shader_parameter(&"progress", value)
	_bg_material.set_shader_parameter(&"invert_direction", _invert)

func _refresh_status_label() -> void:
	_status_label.text = tr(_status_text) + _dots_suffix()

func _dots_suffix() -> String:
	return ".".repeat(1 + (_dot_count % 3))

func _advance_dots() -> void:
	_dot_count = (_dot_count + 1) % 3
	if _screen.visible:
		_refresh_status_label()
