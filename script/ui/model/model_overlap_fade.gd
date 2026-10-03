extends Panel

@export_range(0.1, 1.0, 0.05) var faded_alpha := 0.5
@export var fade_duration := 0.25
@export var fade_position_max_x := -0.23

var _model_position: Vector2 = Vector2.ZERO
var _has_position := false
var _fade_tween: Tween

func _ready() -> void:
	SignalBus.model_transform_values.connect(_on_model_transform_values)
	modulate.a = 1.0

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"model_transform_values", _on_model_transform_values)

func _process(_delta: float) -> void:
	if not visible or not _has_position:
		return
	_update_fade(_position_in_fade_range())

func _on_model_transform_values(pos: Vector2, _scale_value: float, _rotation: float) -> void:
	_has_position = true
	_model_position = pos
	if visible:
		_update_fade(_position_in_fade_range())

func _position_in_fade_range() -> bool:
	return _model_position.x <= fade_position_max_x

func _update_fade(overlaps: bool) -> void:
	var target := faded_alpha if overlaps else 1.0
	if is_equal_approx(modulate.a, target):
		return
	_fade_tween = NodeUtil.stop_tween(_fade_tween)
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_SINE)
	_fade_tween.set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_property(self, "modulate:a", target, fade_duration)
