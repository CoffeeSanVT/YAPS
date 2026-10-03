class_name ModalOverlay
extends RefCounted

const LAYER := 100
const DIM_COLOR := Color(0, 0, 0, 0.45)

var _layer: CanvasLayer
var _dim: ColorRect

func show_modal(host: Node, modal: Control, size: Vector2i) -> void:
	_ensure_layer(host)
	_clear_dim()
	_dim = ColorRect.new()
	_dim.color = DIM_COLOR
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_dim)

	_layer.add_child(modal)
	modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	modal.custom_minimum_size = Vector2(size)
	var viewport_size := modal.get_viewport().get_visible_rect().size
	modal.position = (viewport_size - Vector2(size)) / 2
	modal.show()
	modal.tree_exited.connect(_clear_dim)

func dispose() -> void:
	if is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_dim = null

func _ensure_layer(host: Node) -> void:
	if not is_instance_valid(_layer):
		_layer = CanvasLayer.new()
		_layer.layer = LAYER
		host.get_tree().root.add_child(_layer)

func _clear_dim() -> void:
	if is_instance_valid(_dim) and _dim.is_inside_tree():
		_dim.queue_free()
	_dim = null
