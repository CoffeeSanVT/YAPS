class_name ItemAnimControls
extends FoldableContainer

signal loop_toggled(pressed: bool)

@export_category("UI References")
@export var play_btn: TextureButton
@export var slider: HSlider
@export var frame_label: Label
@export var loop_check: CheckButton
@export_category("Playback Icons")
@export var play_icon: Texture2D
@export var play_icon_hover: Texture2D
@export var play_icon_pressed: Texture2D
@export var play_icon_disabled: Texture2D
@export var play_icon_focused: Texture2D
@export var pause_icon: Texture2D
@export var pause_icon_hover: Texture2D
@export var pause_icon_pressed: Texture2D
@export var pause_icon_disabled: Texture2D
@export var pause_icon_focused: Texture2D

var _player: AnimatedImagePlayer

func _exit_tree() -> void:
	_disconnect_player()

func setup(player: AnimatedImagePlayer, loop: bool) -> void:
	_disconnect_player()
	_player = player
	visible = _player != null
	if _player == null:
		return
	slider.max_value = max(_player.FrameCount - 1, 0)
	slider.set_value_no_signal(_player.CurrentFrame)
	loop_check.set_pressed_no_signal(loop)
	_update_frame_label()
	_update_play_btn()
	_player.FrameChanged.connect(_on_frame_changed)

func get_player() -> AnimatedImagePlayer:
	return _player

func set_enabled(enabled: bool) -> void:
	play_btn.disabled = not enabled
	slider.editable = enabled
	_update_play_btn()

func _on_play_pressed() -> void:
	if _player == null:
		return
	if _player.IsPlaying:
		_player.Pause()
	else:
		_player.Play()
	_update_play_btn()

func _update_play_btn() -> void:
	if _player == null or play_btn == null:
		return
	if _player.IsPlaying:
		_set_icons(pause_icon, pause_icon_pressed, pause_icon_hover, pause_icon_disabled, pause_icon_focused, &"PAUSE")
	else:
		_set_icons(play_icon, play_icon_pressed, play_icon_hover, play_icon_disabled, play_icon_focused, &"PLAY")

func _set_icons(normal: Texture2D, pressed: Texture2D, hover: Texture2D, disabled: Texture2D, focused: Texture2D, tooltip: StringName) -> void:
	play_btn.texture_normal = normal
	play_btn.texture_pressed = pressed
	play_btn.texture_hover = hover
	play_btn.texture_disabled = disabled
	play_btn.texture_focused = focused
	play_btn.tooltip_text = tooltip
	play_btn.tooltip_auto_translate_mode = Control.AUTO_TRANSLATE_MODE_ALWAYS

func _on_slider_changed(value: float) -> void:
	if _player == null:
		return
	_player.Seek(int(value))

func _on_loop_toggled(pressed: bool) -> void:
	if _player == null:
		return
	_player.Loop = pressed
	loop_toggled.emit(pressed)

func _on_frame_changed(frame: int) -> void:
	if slider != null and not slider.has_focus():
		slider.set_value_no_signal(frame)
	_update_frame_label()

func _update_frame_label() -> void:
	if frame_label == null or _player == null:
		return
	frame_label.text = "%d / %d" % [_player.CurrentFrame + 1, _player.FrameCount]

func _disconnect_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = null
		return
	NodeUtil.safe_disconnect(_player, &"FrameChanged", _on_frame_changed)
	_player = null
