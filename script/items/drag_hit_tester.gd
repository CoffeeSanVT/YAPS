class_name DragHitTester
extends RefCounted

const ALPHA_THRESHOLD := 0.05
const HIT_MASK_MAX_SIZE := 64

var _mask := PackedByteArray()
var _mask_size := Vector2i.ZERO
var _image_source: WeakRef

func is_opaque_at(target: TextureRect, viewport_pos: Vector2) -> bool:
	_refresh_mask(target.texture)
	if _mask.is_empty():
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
	var px := clampi(int(local.x / target.size.x * _mask_size.x), 0, _mask_size.x - 1)
	var py := clampi(int(local.y / target.size.y * _mask_size.y), 0, _mask_size.y - 1)
	return _mask[py * _mask_size.x + px] > int(ALPHA_THRESHOLD * 255.0)

func _refresh_mask(tex: Texture2D) -> void:
	var image_tex := tex as ImageTexture
	if image_tex == null:
		_clear()
		return
	if _image_source != null and _image_source.get_ref() == image_tex and not _mask.is_empty():
		return
	var image := image_tex.get_image()
	if image == null or image.is_empty():
		_clear()
		return
	if image.is_compressed() and image.decompress() != OK:
		_clear()
		return
	var ratio := minf(1.0, minf(float(HIT_MASK_MAX_SIZE) / image.get_width(), float(HIT_MASK_MAX_SIZE) / image.get_height()))
	var width := maxi(1, int(image.get_width() * ratio))
	var height := maxi(1, int(image.get_height() * ratio))
	image.resize(width, height, Image.INTERPOLATE_BILINEAR)
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	_mask_size = Vector2i(width, height)
	_mask.resize(width * height)
	for y in height:
		for x in width:
			_mask[y * width + x] = int(image.get_pixel(x, y).a * 255.0)
	_image_source = weakref(image_tex)

func _clear() -> void:
	_mask.clear()
	_mask_size = Vector2i.ZERO
	_image_source = null
