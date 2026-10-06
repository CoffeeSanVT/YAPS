class_name FrameTrack
extends RefCounted


var frames: Array[ImageTexture] = []
var index: int = 0
var entry: ModelStateEntry

var _timer: Timer
var _holder: Node
var _on_tick: Callable

func bind(holder: Node, on_tick: Callable) -> void:
	_holder = holder
	_on_tick = on_tick

func is_running() -> bool:
	return is_instance_valid(_timer)

func start(fps: float) -> void:
	if frames.is_empty() or _holder == null:
		return
	_timer = NodeUtil.ensure_timer(_holder, _timer, _on_tick, false)
	_timer.wait_time = 1.0 / maxf(fps, 0.01)
	_timer.start()

func stop() -> void:
	_timer = NodeUtil.free_timer(_timer)

func advance() -> void:
	if frames.is_empty():
		return
	var next := (index + 1) % frames.size()
	if frames[next] == null:
		return
	index = next

func clear() -> void:
	stop()
	frames = []
	index = 0
	entry = null
