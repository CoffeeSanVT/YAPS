class_name MicVolumeDisplay
extends RefCounted

const UPDATE_INTERVAL_MS := 66

var volume_bar: ProgressBar
var db_label: Label
var _last_update_ms: int = 0

func _init(bar: ProgressBar, label: Label) -> void:
	volume_bar = bar
	db_label = label
	SignalBus.mic_input_smoothed.connect(_on_mic_input_smoothed)

func dispose() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"mic_input_smoothed", _on_mic_input_smoothed)

func _on_mic_input_smoothed(smoothed_db: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_update_ms < UPDATE_INTERVAL_MS:
		return
	_last_update_ms = now
	volume_bar.value = smoothed_db
	db_label.text = "%.1f dB" % [smoothed_db]