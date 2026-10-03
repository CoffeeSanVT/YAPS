class_name TextureCache
extends RefCounted

const MAX_ENTRIES := 512
const FULL_BOUNDS := Rect2(0.0, 0.0, 1.0, 1.0)

var _cache: Dictionary[String, ImageTexture] = {}
var _order: Array[String] = []
var _pending_requests: Dictionary = {}
var _generation: int = 0
var _bounds: Dictionary[Texture2D, Rect2] = {}

func load_state_texture(state: ModelStateEntry) -> ImageTexture:
	return load_texture(state.asset_path)

func load_texture(path: String) -> ImageTexture:
	if _cache.has(path):
		_touch(path)
		return _cache[path]
	var decoded := ImageUtil.load_texture_with_rect(path)
	var texture := decoded.texture as ImageTexture
	if texture != null:
		_store(path, texture, decoded.used_rect)
	return texture

func bounds_of(tex: Texture2D) -> Rect2:
	return _bounds.get(tex, FULL_BOUNDS)

func request_texture(path: String, done: Callable, owner: Object = null) -> void:
	if owner != null:
		var ref: WeakRef = weakref(owner)
		var delivered := done
		done = func(tex: ImageTexture) -> void:
			if ref.get_ref() == null:
				return
			delivered.call(tex)
	var generation := _generation
	if _cache.has(path):
		_touch(path)
		if done.is_valid():
			done.call_deferred(_cache[path])
		return
	if _pending_requests.has(path):
		if done.is_valid():
			_pending_requests[path].append(done)
		return
	_pending_requests[path] = [done] if done.is_valid() else []
	IoService.run_io(func() -> Array:
		var cached := ImageUtil.load_vram_cache(path)
		if not cached.is_empty():
			return [cached.image, cached.used_rect]
		var image := ImageUtil.load_image(path)
		if image == null:
			return [null, Rect2i()]
		var used_rect := image.get_used_rect()
		ImageUtil.compress_for_gpu(image, path, used_rect)
		return [image, used_rect],
	func(result: Array) -> void:
		_finish_request(path, result[0], result[1], generation)
	)

func _finish_request(path: String, image: Image, used_rect: Rect2i, generation: int) -> void:
	if generation != _generation:
		return
	var callbacks: Array = _pending_requests.get(path, [])
	_pending_requests.erase(path)
	var texture: ImageTexture = _cache.get(path)
	if texture == null and image != null:
		texture = ImageUtil.create_gpu_texture(image)
		_store(path, texture, used_rect)
	for cb: Callable in callbacks:
		if cb.is_valid():
			cb.call(texture)

func load_state_frames(state: ModelStateEntry) -> Array[ImageTexture]:
	var frames: Array[ImageTexture] = []
	for frame_path in state.get_frame_paths():
		var tex := load_texture(frame_path)
		if tex != null:
			frames.append(tex)
	return frames

func clear() -> void:
	_generation += 1
	_pending_requests.clear()
	_cache.clear()
	_order.clear()
	_bounds.clear()

func pending_count() -> int:
	return _pending_requests.size()

func _touch(path: String) -> void:
	_order.erase(path)
	_order.append(path)

func _store(path: String, texture: ImageTexture, used_rect: Rect2i) -> void:
	if _cache.has(path):
		_bounds.erase(_cache[path])
		_cache[path] = texture
		_touch(path)
		_bounds[texture] = normalized_bounds(texture, used_rect)
		return
	while _order.size() >= MAX_ENTRIES:
		var oldest: String = _order.pop_front()
		_bounds.erase(_cache[oldest])
		_cache.erase(oldest)
	_cache[path] = texture
	_order.append(path)
	_bounds[texture] = normalized_bounds(texture, used_rect)

static func normalized_bounds(texture: Texture2D, used_rect: Rect2i) -> Rect2:
	var size := texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0 or used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return FULL_BOUNDS
	var pos := Vector2(used_rect.position) / size
	var end := Vector2(used_rect.end) / size
	return Rect2(pos, end - pos)

static func bounds_to_vec4(bounds: Rect2) -> Vector4:
	return Vector4(bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y)
