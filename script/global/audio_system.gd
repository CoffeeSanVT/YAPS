extends Node

const TAG := "[AudioSystem] "
const SMOOTHING_ATTACK := 0.5
const SMOOTHING_RELEASE := 0.05
const TALK_HYSTERESIS_DB := 4.0
const TALK_HOLD_MS := 600

var threshold_db: float
var record_bus_index: int
var _was_exceeded: bool
var _below_since_ms: int = -1
var _audio_player: AudioStreamPlayer
var _smoothed_db: float = -60.0

func _ready() -> void:
	record_bus_index = AudioServer.get_bus_index("RecordingBus")
	if record_bus_index == -1:
		push_warning(TAG + "Audio bus 'RecordingBus' not found. Mic input will not work.")
	setup_mic_recording()
	threshold_db = Settings.settings.mic_threshold
	SignalBus.mic_threshold_changed.connect(_on_mic_threshold_changed)
	SignalBus.mic_gain_changed.connect(_on_mic_gain_changed)
	_apply_mic_gain(Settings.settings.mic_gain_db)
	SignalBus.mic_monitoring_changed.connect(_on_mic_monitoring_changed)
	_apply_mic_monitoring(Settings.settings.mic_monitoring)

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"mic_threshold_changed", _on_mic_threshold_changed)
	NodeUtil.safe_disconnect(SignalBus, &"mic_gain_changed", _on_mic_gain_changed)
	NodeUtil.safe_disconnect(SignalBus, &"mic_monitoring_changed", _on_mic_monitoring_changed)
	if _audio_player != null:
		_audio_player.stop()
		_audio_player.stream = null
		_audio_player = null

func _on_mic_threshold_changed(value: float) -> void:
	threshold_db = value

func _on_mic_gain_changed(gain_db: float) -> void:
	_apply_mic_gain(gain_db)

func _apply_mic_gain(gain_db: float) -> void:
	if record_bus_index == -1:
		return
	var effect_index := _get_amplify_effect_index()
	if effect_index == -1:
		push_warning(TAG + "AudioEffectAmplify not found on 'RecordingBus'. Mic gain will not work.")
		return
	var effect := AudioServer.get_bus_effect(record_bus_index, effect_index) as AudioEffectAmplify
	effect.volume_db = gain_db

func _get_amplify_effect_index() -> int:
	for i in AudioServer.get_bus_effect_count(record_bus_index):
		if AudioServer.get_bus_effect(record_bus_index, i) is AudioEffectAmplify:
			return i
	return -1

func _process(_delta: float) -> void:
	if record_bus_index == -1:
		return
	var current_db := clampf(AudioServer.get_bus_peak_volume_left_db(record_bus_index, 0), -60, 0)
	SignalBus.mic_input_detected.emit(current_db)
	_smoothed_db = _smooth_db(current_db, _smoothed_db)
	SignalBus.mic_input_smoothed.emit(_smoothed_db)
	_update_exceeded(current_db)

func _update_exceeded(current_db: float) -> void:
	if _smoothed_db > threshold_db:
		_below_since_ms = -1
		_set_exceeded(true, current_db)
		return
	if _smoothed_db < threshold_db - TALK_HYSTERESIS_DB:
		if _below_since_ms < 0:
			_below_since_ms = Time.get_ticks_msec()
		if _was_exceeded and Time.get_ticks_msec() - _below_since_ms >= TALK_HOLD_MS:
			_below_since_ms = -1
			_set_exceeded(false, current_db)
		return
	_below_since_ms = -1

func _set_exceeded(value: bool, _current_db: float) -> void:
	if value == _was_exceeded:
		return
	_was_exceeded = value
	SignalBus.mic_input_exceed_threshold.emit(value)

static func _smooth_db(current: float, previous: float) -> float:
	var alpha := SMOOTHING_ATTACK if current >= previous else SMOOTHING_RELEASE
	return lerpf(previous, current, alpha)

func setup_mic_recording() -> void:
	if record_bus_index == -1:
		push_warning(TAG + "Skipping microphone setup: 'RecordingBus' missing.")
		return
	_audio_player = AudioStreamPlayer.new()
	_audio_player.autoplay = true
	_audio_player.bus = &"RecordingBus"
	_audio_player.stream = AudioStreamMicrophone.new()
	add_child(_audio_player)

func _on_mic_monitoring_changed(enabled: bool) -> void:
	_apply_mic_monitoring(enabled)

func _apply_mic_monitoring(enabled: bool) -> void:
	var trapped_bus_index := AudioServer.get_bus_index(&"TrappedOutput")
	if trapped_bus_index == -1:
		push_warning(TAG + "Audio bus 'TrappedOutput' not found. Mic monitoring will not work.")
		return
	AudioServer.set_bus_mute(trapped_bus_index, not enabled)
