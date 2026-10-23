extends Control

enum Kind { INFO, SUCCESS, WARNING, ERROR }

const FADE_IN_SEC := 0.2
const FADE_OUT_SEC := 0.35

@export var stack: VBoxContainer
@export var toast_template: PanelContainer
@export var toast_label: Label
@export var max_toasts := 4
@export var default_duration_sec := 5.0
@export var info_color := Color(0.55, 0.73, 0.94)
@export var success_color := Color(0.5, 0.78, 0.5)
@export var warning_color := Color(0.9, 0.78, 0.35)
@export var error_color := Color(0.9, 0.45, 0.45)

var _template_label_index := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if toast_label != null:
		_template_label_index = toast_label.get_index()
	if toast_template != null:
		toast_template.visible = false
	SignalBus.twitch_token_expired.connect(_on_twitch_token_expired)
	SignalBus.twitch_token_refreshed.connect(_on_twitch_token_refreshed)
	if TwitchClient.is_refresh_in_progress():
		show_toast(tr(&"TOAST_TOKEN_EXPIRED"), Kind.WARNING)

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"twitch_token_expired", _on_twitch_token_expired)
	NodeUtil.safe_disconnect(SignalBus, &"twitch_token_refreshed", _on_twitch_token_refreshed)

func show_toast(message: String, kind: Kind = Kind.INFO, duration: float = -1.0) -> void:
	if stack == null or toast_template == null or toast_label == null:
		push_warning("[ToastPanel] missing stack/template references")
		return
	var effective := duration if duration >= 0.0 else default_duration_sec
	_trim_overflow()
	var toast := toast_template.duplicate() as PanelContainer
	var label := toast.get_child(_template_label_index) as Label
	label.text = message
	var style := toast.get_theme_stylebox("panel")
	if style != null:
		var colored := style.duplicate() as StyleBoxFlat
		colored.border_color = _color_for(kind)
		toast.add_theme_stylebox_override("panel", colored)
	toast.visible = true
	toast.modulate.a = 0.0
	stack.add_child(toast)
	var tween := toast.create_tween()
	tween.tween_property(toast, "modulate:a", 1.0, FADE_IN_SEC)
	tween.tween_interval(maxf(effective, 0.1))
	tween.tween_property(toast, "modulate:a", 0.0, FADE_OUT_SEC)
	tween.tween_callback(toast.queue_free)

func _color_for(kind: Kind) -> Color:
	match kind:
		Kind.SUCCESS:
			return success_color
		Kind.WARNING:
			return warning_color
		Kind.ERROR:
			return error_color
	return info_color

func _trim_overflow() -> void:
	while stack.get_child_count() >= max_toasts:
		var oldest := stack.get_child(0)
		oldest.free()

func _on_twitch_token_expired(_context: String) -> void:
	show_toast(tr(&"TOAST_TOKEN_EXPIRED"), Kind.WARNING)

func _on_twitch_token_refreshed(success: bool) -> void:
	if success:
		show_toast(tr(&"TOAST_TOKEN_RENEWED"), Kind.SUCCESS)
	else:
		show_toast(tr(&"TOAST_TOKEN_RENEW_FAILED"), Kind.ERROR)
