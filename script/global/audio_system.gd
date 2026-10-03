extends Node

const TAG := "[AudioSystem] "
const SMOOTHING_ATTACK := 0.5
const SMOOTHING_RELEASE := 0.12

var threshold_db: float
var record_bus_index: int
var _was_exceeded: bool
var _audio_player: AudioStreamPlayer
var _smoothed_db: float = -60.0

func _ready() -> void:
	record_bus_index = AudioServer.get_bus_index("RecordingBus")
	if record_bus_index == -1:
		push_warning(TAG + "Audio bus 'RecordingBus' not found. Mic input will not work.")
	setup_mic_recording()
	threshold_db = Settings.settings.mic_threshold
	SignalBus.mic_threshold_changed.connect(_on_mic_threshold_changed)

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"mic_threshold_changed", _on_mic_threshold_changed)
	if _audio_player != null:
		_audio_player.stop()
		_audio_player.stream = null
		_audio_player = null

func _on_mic_threshold_changed(value: float) -> void:
	threshold_db = value

func _process(_delta: float) -> void:
	if record_bus_index == -1:
		return
	var current_db := clampf(AudioServer.get_bus_peak_volume_left_db(record_bus_index, 0), -60, 0)
	SignalBus.mic_input_detected.emit(current_db)
	_smoothed_db = _smooth_db(current_db, _smoothed_db)
	SignalBus.mic_input_smoothed.emit(_smoothed_db)
	var exceeded: bool = _smoothed_db > threshold_db
	if exceeded != _was_exceeded:
		_was_exceeded = exceeded
		SignalBus.mic_input_exceed_threshold.emit(exceeded)

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
