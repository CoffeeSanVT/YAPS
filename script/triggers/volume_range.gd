class_name VolumeRange
extends BaseTrigger

@export_category("Volume Range")
@export var min_db: float = -20.0
@export var max_db: float = -10.0
@export var revert_delay: float = 0.5
@export var activation_delay: float = 0.1

var _exit_at_msec: int = 0
var _entry_at_msec: int = 0

func _init() -> void:
	trigger_name = &"volume_range"
	ui_prefab = preload("uid://bfbdhjbhwlrmh")

func activate() -> void:
	_entry_at_msec = 0
	_exit_at_msec = 0
	NodeUtil.connect_once(SignalBus, &"mic_input_detected", _on_mic)

func deactivate() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"mic_input_detected", _on_mic)

func _on_mic(db: float) -> void:
	if db >= min_db and db <= max_db:
		_handle_in_range()
	else:
		_handle_out_of_range()

func _handle_in_range() -> void:
	_exit_at_msec = 0
	if enabled:
		return
	if _entry_at_msec == 0:
		_entry_at_msec = Time.get_ticks_msec()
	elif Time.get_ticks_msec() >= _entry_at_msec + int(activation_delay * 1000.0):
		_entry_at_msec = 0
		set_enabled(true)

func _handle_out_of_range() -> void:
	_entry_at_msec = 0
	if not enabled:
		return
	if _exit_at_msec == 0:
		_exit_at_msec = Time.get_ticks_msec() + int(revert_delay * 1000.0)
	elif Time.get_ticks_msec() >= _exit_at_msec:
		_exit_at_msec = 0
		set_enabled(false)
