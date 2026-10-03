extends SpinBox

const DB_SAMPLE_LIMIT := 7200

@export_category("Threshold")
@export var button: Button

@export_category("Visualizer")
@export var volume_bar: ProgressBar
@export var db_label: Label

@export_category("Calculation")
@export var average_db_label: Label
@export var calc_timer: Timer

var db_values: Array[float]
var average_db: float
var _calculating: bool = false
var _display: MicVolumeDisplay

func _ready() -> void:
	_display = MicVolumeDisplay.new(volume_bar, db_label)
	SignalBus.mic_input_smoothed.connect(_on_mic_sampled)
	NodeUtil.attach_locale(self, _on_locale_change)
	value = Settings.settings.mic_threshold
	_reset_calc_button()
	average_db_label.text = String(tr(&"AVERAGE_DB")) % [average_db]

func _exit_tree() -> void:
	_display.dispose()
	NodeUtil.safe_disconnect(SignalBus, &"mic_input_smoothed", _on_mic_sampled)

func _on_locale_change() -> void:
	average_db_label.text = String(tr(&"AVERAGE_DB")) % [average_db]
	if not button.disabled:
		_reset_calc_button()

func _on_value_changed(threshold_value: float) -> void:
	SignalBus.mic_threshold_changed.emit(threshold_value)

func _on_mic_sampled(smoothed_db: float) -> void:
	if _calculating and db_values.size() < DB_SAMPLE_LIMIT:
		db_values.append(smoothed_db)

func _on_global_mic_visualizer_toggled(toggled_on: bool) -> void:
	if toggled_on:
		volume_bar.hide()
	else:
		volume_bar.show()

func _on_button_toggled(_toggled_on: bool) -> void:
	_calculating = true
	calc_timer.start()
	_reset_calc_button()
	button.disabled = true

func _on_timer_timeout() -> void:
	_calculating = false
	button.set_pressed_no_signal(false)

	average_db = 0.0
	for db_value in db_values:
		average_db += db_value

	if not db_values.is_empty():
		average_db = average_db / db_values.size()

	average_db_label.text = String(tr(&"CALC_AVERAGE_DB")) % [average_db]

	_reset_calc_button()
	button.disabled = false

	db_values.clear()

func _reset_calc_button() -> void:
	button.text = tr(&"START_CALC_AVERAGE_DB")
