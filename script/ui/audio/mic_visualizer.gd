extends PanelContainer

@export_category("Visualizer")
@export var volume_bar: ProgressBar
@export var db_label: Label

var _display: MicVolumeDisplay

func _ready() -> void:
	_display = MicVolumeDisplay.new(volume_bar, db_label)
	SignalBus.mic_visualizer_changed.connect(_on_visibility_changed)
	visible = Settings.settings.show_mic_visualizer

func _exit_tree() -> void:
	_display.dispose()
	NodeUtil.safe_disconnect(SignalBus, &"mic_visualizer_changed", _on_visibility_changed)

func _on_visibility_changed(value: bool) -> void:
	visible = value