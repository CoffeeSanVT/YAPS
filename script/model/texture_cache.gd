class_name TextureCache
extends RefCounted

const CACHE_BUDGET_BYTES := 256 * 1024 * 1024
const SNAP_SAMPLE_SIZE := 24
const FULL_BOUNDS := Rect2(0.0, 0.0, 1.0, 1.0)

var _cache: Dictionary[String, ImageTexture] = {}
var _order: Array[String] = []
var _pending_requests: Dictionary = {}
var _generation: int = 0
var _bounds: Dictionary[Texture2D, Rect2] = {}
var _bytes: int = 0
var _thumbs: Dictionary[String, Image] = {}

func load_state_texture(state: ModelStateEntry) -> ImageTexture:
	var paths := _state_frame_paths(state)
	if paths.is_empty():
		return load_texture(state.asset_path)
	var tex := load_texture(paths[0])
	if tex == null and paths[0] != state.asset_path and not state.asset_path.is_empty():
		tex = load_texture(state.asset_path)
	return tex

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
		ImageUtil.ensure_mipmaps(image)
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

func _state_frame_paths(state: ModelStateEntry) -> Array[String]:
	return state.frames if not state.frames.is_empty() else state.get_frame_paths()

func state_frame_array(state: ModelStateEntry) -> Array[ImageTexture]:
	var frames: Array[ImageTexture] = []
	frames.resize(_state_frame_paths(state).size())
	return frames

func request_frame_window(state: ModelStateEntry, start_index: int, count: int, frames: Array[ImageTexture], owner: Object = null, on_ready: Callable = Callable()) -> void:
	var paths := _state_frame_paths(state)
	if paths.is_empty():
		if on_ready.is_valid():
			on_ready.call_deferred(0)
		return
	var target := 0
	var filled := [0]
	var fired := [false]
	var notify := func() -> void:
		if fired[0] or not on_ready.is_valid():
			return
		if filled[0] >= target:
			fired[0] = true
			on_ready.call_deferred(filled[0])
	for k in count:
		var i := (start_index + k) % paths.size()
		var path := paths[i]
		if path.is_empty():
			continue
		target += 1
		var cached: ImageTexture = _cache.get(path)
		if cached != null:
			_touch(path)
			frames[i] = cached
			filled[0] += 1
			continue
		var slot := i
		request_texture(path, func(tex: ImageTexture) -> void:
			frames[slot] = tex
			filled[0] += 1
			notify.call()
		, owner)
	notify.call()

func request_state_frame(state: ModelStateEntry, index: int, frames: Array[ImageTexture], owner: Object = null) -> void:
	var paths := _state_frame_paths(state)
	if index < 0 or index >= paths.size() or index >= frames.size():
		return
	var path := paths[index]
	if path.is_empty():
		return
	var cached: ImageTexture = _cache.get(path)
	if cached != null:
		_touch(path)
		frames[index] = cached
		return
	var slot := index
	request_texture(path, func(tex: ImageTexture) -> void:
		frames[slot] = tex
	, owner)

func request_thumb(path: String) -> void:
	if path.is_empty() or _thumbs.has(path):
		return
	IoService.run_io(func() -> Image:
		var image := ImageUtil.load_image(path)
		if image == null:
			return null
		image.convert(Image.FORMAT_RGBA8)
		image.resize(SNAP_SAMPLE_SIZE, SNAP_SAMPLE_SIZE, Image.INTERPOLATE_BILINEAR)
		return image
	, func(img: Image) -> void:
		if img != null and img.get_width() == SNAP_SAMPLE_SIZE and img.get_height() == SNAP_SAMPLE_SIZE:
			_thumbs[path] = img
	)

func has_all_thumbs(state: ModelStateEntry) -> bool:
	for path in _state_frame_paths(state):
		if not path.is_empty() and not _thumbs.has(path):
			return false
	return true

func snap_start_index(state: ModelStateEntry, reference_tex: Texture2D) -> int:
	var paths := _state_frame_paths(state)
	var reference_thumb := _texture_to_thumb(reference_tex)
	var best := 0
	var best_diff := -1.0
	for i in paths.size():
		var path := paths[i]
		if path.is_empty():
			continue
		var thumb: Image = _thumbs.get(path)
		if thumb == null:
			continue
		var diff := _thumb_diff(reference_thumb, thumb)
		if diff > best_diff:
			best_diff = diff
			best = i
	return best

func _texture_to_thumb(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var image := tex.get_image()
	if image == null or image.is_empty():
		return null
	if image.is_compressed() and image.decompress() != OK:
		return null
	if image.has_mipmaps():
		image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(SNAP_SAMPLE_SIZE, SNAP_SAMPLE_SIZE, Image.INTERPOLATE_BILINEAR)
	if image.get_width() != SNAP_SAMPLE_SIZE or image.get_height() != SNAP_SAMPLE_SIZE:
		return null
	return image

static func _thumb_diff(a: Image, b: Image) -> float:
	if a == null or b == null:
		return 0.0
	var da := a.get_data()
	var db := b.get_data()
	var expected := SNAP_SAMPLE_SIZE * SNAP_SAMPLE_SIZE * 4
	if da.size() != expected or db.size() != expected:
		return 0.0
	var total := 0.0
	for i in range(0, expected, 4):
		total += absf(da[i] - db[i]) + absf(da[i + 1] - db[i + 1]) + absf(da[i + 2] - db[i + 2]) + absf(da[i + 3] - db[i + 3])
	return total / float(da.size())

static func _texture_bytes(tex: Texture2D) -> int:
	var size := tex.get_size()
	return int(float(size.x) * float(size.y) * 4.0 * 4.0 / 3.0)

func release_texture(path: String) -> void:
	var texture: ImageTexture = _cache.get(path)
	if texture == null:
		return
	_bytes -= _texture_bytes(texture)
	_cache.erase(path)
	_order.erase(path)
	_bounds.erase(texture)

func clear() -> void:
	_generation += 1
	_pending_requests.clear()
	_cache.clear()
	_order.clear()
	_bounds.clear()
	_thumbs.clear()
	_bytes = 0

func pending_count() -> int:
	return _pending_requests.size()

func _touch(path: String) -> void:
	_order.erase(path)
	_order.append(path)

func _store(path: String, texture: ImageTexture, used_rect: Rect2i) -> void:
	if _cache.has(path):
		_bytes -= _texture_bytes(_cache[path])
		_bounds.erase(_cache[path])
		_cache[path] = texture
		_touch(path)
		_bounds[texture] = normalized_bounds(texture, used_rect)
		_bytes += _texture_bytes(texture)
		return
	_cache[path] = texture
	_order.append(path)
	_bounds[texture] = normalized_bounds(texture, used_rect)
	_bytes += _texture_bytes(texture)
	while _bytes > CACHE_BUDGET_BYTES and _order.size() > 1:
		var oldest: String = _order.pop_front()
		var oldest_tex: ImageTexture = _cache[oldest]
		_bytes -= _texture_bytes(oldest_tex)
		_bounds.erase(oldest_tex)
		_cache.erase(oldest)

static func normalized_bounds(texture: Texture2D, used_rect: Rect2i) -> Rect2:
	var size := texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0 or used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return FULL_BOUNDS
	var pos := Vector2(used_rect.position) / size
	var end := Vector2(used_rect.end) / size
	return Rect2(pos, end - pos)

static func bounds_to_vec4(bounds: Rect2) -> Vector4:
	return Vector4(bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y)
