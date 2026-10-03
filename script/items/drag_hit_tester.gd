class_name DragHitTester
extends RefCounted

const ALPHA_THRESHOLD := 0.05

var _image: Image
var _image_source: Texture2D

func is_opaque_at(target: TextureRect, viewport_pos: Vector2) -> bool:
	_refresh_image(target.texture)
	if _image == null:
		return true
	var s := target.offset_transform_scale
	if s == Vector2.ZERO:
		return false
	var pivot := target.size * 0.5
	var delta := viewport_pos - target.offset_transform_position - pivot
	var angle := target.offset_transform_rotation
	if angle != 0.0:
		var c := cos(-angle)
		var sn := sin(-angle)
		delta = Vector2(delta.x * c - delta.y * sn, delta.x * sn + delta.y * c)
	var local := pivot + delta / s
	if local.x < 0.0 or local.y < 0.0 or local.x > target.size.x or local.y > target.size.y:
		return false
	var px := clampi(int(local.x / target.size.x * _image.get_width()), 0, _image.get_width() - 1)
	var py := clampi(int(local.y / target.size.y * _image.get_height()), 0, _image.get_height() - 1)
	return _image.get_pixel(px, py).a > ALPHA_THRESHOLD

func _refresh_image(tex: Texture2D) -> void:
	var image_tex := tex as ImageTexture
	if image_tex == null:
		_image = null
		_image_source = null
		return
	if image_tex == _image_source and _image != null:
		return
	_image_source = image_tex
	_image = image_tex.get_image()
