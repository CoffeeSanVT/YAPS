extends PanelContainer

const BYTES_PER_GIB := 1073741824.0
const BYTES_PER_MIB := 1048576.0
const FRAME_TIME_EMA_WEIGHT := 0.15

@export_category("Overlay")
@export var fps_label: Label
@export var frame_time_label: Label
@export var cpu_label: Label
@export var gpu_label: Label
@export var ram_label: Label
@export var vram_label: Label
@export var system_stats: Node

var _frame_time_ms: float = 0.0
var _update_timer: Timer = null

func _ready() -> void:
	SignalBus.performance_overlay_changed.connect(_on_visibility_changed)
	visible = Settings.settings.show_performance_overlay
	_update_timer = Timer.new()
	_update_timer.wait_time = 0.2
	_update_timer.timeout.connect(_refresh_stats)
	add_child(_update_timer)
	_refresh_stats()
	_set_active(visible)

func _process(delta: float) -> void:
	if not visible:
		return
	_frame_time_ms = lerpf(_frame_time_ms, delta * 1000.0, FRAME_TIME_EMA_WEIGHT)

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"performance_overlay_changed", _on_visibility_changed)
	system_stats.Stop()

func _on_visibility_changed(value: bool) -> void:
	visible = value
	_set_active(value)

func _set_active(active: bool) -> void:
	if active:
		_update_timer.start()
		system_stats.Start()
	else:
		_update_timer.stop()
		system_stats.Stop()

func _refresh_stats() -> void:
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	fps_label.text = "FPS: %d" % roundi(fps)
	frame_time_label.text = "Frame Time: %.1f ms" % _frame_time_ms
	cpu_label.text = "CPU: %s" % _format_percent(system_stats.GetCpuUsage())
	gpu_label.text = "GPU: %s" % _format_percent(system_stats.GetGpuUsage())
	ram_label.text = "RAM: %s" % _format_size(system_stats.GetRamUsedBytes())
	vram_label.text = "VRAM: %s" % _format_size(system_stats.GetVramUsedBytes())

func _format_percent(value: float) -> String:
	if value < 0.0:
		return "N/A"
	return "%d%%" % roundi(value)

func _format_size(bytes: float) -> String:
	if bytes < 0.0:
		return "N/A"
	if bytes < BYTES_PER_GIB:
		return "%d MB" % roundi(bytes / BYTES_PER_MIB)
	return "%.1f GB" % (bytes / BYTES_PER_GIB)
