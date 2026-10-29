class_name TextureCache
extends RefCounted

const CACHE_BUDGET_BYTES := 512 * 1024 * 1024
const SNAP_SAMPLE_SIZE := 32
const FULL_BOUNDS := Rect2(0.0, 0.0, 1.0, 1.0)
const AtlasStoreScript := preload("res://script/utils/atlas_store.gd")
const PAGE_CACHE_LIMIT := 2
const PAGE_CACHE_BUDGET_BYTES := 64 * 1024 * 1024
const IDLE_UNLOAD_SECONDS := 15.0
const PAGE_IDLE_UNLOAD_SECONDS := 15.0

var _cache: Dictionary[String, ImageTexture] = {}
var _order: Array[String] = []
var _pinned: Dictionary[String, bool] = {}
var _leases: Dictionary[String, int] = {}
var _evict_when_ready: Dictionary[String, bool] = {}
var _pending_requests: Dictionary = {}
var _generation: int = 0
var _bounds: Dictionary[Texture2D, Rect2] = {}
var _bytes: int = 0
var _path_bytes: Dictionary[String, int] = {}
var _thumbs: Dictionary[String, Image] = {}
var _thumbs_complete: Dictionary[ModelStateEntry, bool] = {}
var _thumb_refs: Dictionary[String, int] = {}
var _animated_assets: Dictionary[String, bool] = {}
var _last_use: Dictionary[String, int] = {}

static var _page_images: Dictionary[String, Image] = {}
static var _page_mtimes: Dictionary[String, int] = {}
static var _page_order: Array[String] = []
static var _page_last_use: Dictionary[String, int] = {}
static var _page_total := 0
static var _page_lock := Mutex.new()
const THUMB_PAGE_CACHE_LIMIT := 8
static var _thumb_page_images: Dictionary[String, Image] = {}
static var _thumb_page_mtimes: Dictionary[String, int] = {}
static var _thumb_page_order: Array[String] = []

func load_state_texture(state: ModelStateEntry) -> ImageTexture:
	var paths := _state_frame_paths(state)
	if paths.is_empty():
		return load_texture(state.asset_path)
	var tex := load_texture(paths[0])
	if tex == null and paths[0] != state.asset_path and not state.asset_path.is_empty():
		tex = load_texture(state.asset_path)
	return tex

func request_state_texture(state: ModelStateEntry, done: Callable, owner: Object = null) -> void:
	var paths := _state_frame_paths(state)
	var path := state.asset_path
	if not paths.is_empty():
		path = paths[0]
	if path.is_empty():
		if done.is_valid():
			done.call_deferred(null)
		return
	var fallback := state.asset_path if state.asset_path != path and not state.asset_path.is_empty() else ""
	request_texture(path, func(tex: Texture2D) -> void:
		if tex != null or fallback.is_empty():
			if done.is_valid():
				done.call(tex)
			return
		request_texture(fallback, func(fallback_tex: Texture2D) -> void:
			if done.is_valid():
				done.call(fallback_tex)
		, owner)
	, owner)

func load_texture(path: String) -> ImageTexture:
	if _cache.has(path):
		_touch(path)
		return _cache[path]
	var meta: Dictionary = AtlasStoreScript.frame_meta(path)
	if not meta.is_empty():
		var decoded := _decode_atlas_frame(path, meta, Vector2.ZERO)
		var image: Image = decoded[0]
		if image != null:
			var texture := ImageUtil.create_gpu_texture(image)
			_store(path, texture, decoded[1], ImageUtil.estimate_vram_bytes(image))
			return texture
	var decoded_file := ImageUtil.load_texture_with_rect(path)
	var texture_file := decoded_file.texture as ImageTexture
	if texture_file != null:
		_store(path, texture_file, decoded_file.used_rect, decoded_file.vram_bytes)
	return texture_file

func bounds_of(tex: Texture2D) -> Rect2:
	return _bounds.get(tex, FULL_BOUNDS)

func request_texture(path: String, done: Callable, owner: Object = null, max_size: Vector2 = Vector2.ZERO) -> void:
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
	var meta: Dictionary = AtlasStoreScript.frame_meta(path)
	var task: Callable
	if meta.is_empty():
		task = func() -> Array:
			var cached := ImageUtil.load_vram_cache(path)
			if not cached.is_empty():
				var cached_image: Image = cached.image
				if ImageUtil.image_fits(cached_image, max_size):
					return [cached_image, cached.used_rect]
			var image := ImageUtil.load_image(path)
			if image == null:
				return [null, Rect2i()]
			ImageUtil.fit_image(image, max_size)
			var used_rect := image.get_used_rect()
			ImageUtil.compress_for_gpu(image, path, used_rect)
			return [image, used_rect]
	else:
		task = func() -> Array:
			return _decode_atlas_frame(path, meta, max_size)
	IoService.run_io(task,
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
		_store(path, texture, used_rect, ImageUtil.estimate_vram_bytes(image))
	for cb: Callable in callbacks:
		if cb.is_valid():
			cb.call(texture)
	if _evict_when_ready.has(path):
		_evict_when_ready.erase(path)
		if not _leases.has(path) and not _pinned.has(path):
			_evict_texture(path)

func _state_frame_paths(state: ModelStateEntry) -> Array[String]:
	if state.frames.is_empty():
		return state.get_frame_paths()
	if _asset_is_animated(state.asset_path):
		return state.frames
	return state.get_frame_paths()

func _asset_is_animated(asset_path: String) -> bool:
	if asset_path.is_empty():
		return false
	if not _animated_assets.has(asset_path):
		_animated_assets[asset_path] = ImageUtil.is_animated_file(asset_path)
	return _animated_assets[asset_path]

func state_frame_paths(state: ModelStateEntry) -> Array[String]:
	return _state_frame_paths(state)

func state_first_path(state: ModelStateEntry) -> String:
	var paths := _state_frame_paths(state)
	return paths[0] if not paths.is_empty() else state.asset_path

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

func request_thumb(path: String, done: Callable = Callable()) -> void:
	if path.is_empty():
		return
	if _thumbs.has(path):
		if done.is_valid():
			done.call_deferred(_thumbs[path])
		return
	var generation := _generation
	var deliver := func(img: Image) -> void:
		if generation != _generation:
			return
		if img != null and img.get_width() == SNAP_SAMPLE_SIZE and img.get_height() == SNAP_SAMPLE_SIZE and _thumb_refs.has(path):
			_thumbs[path] = img
		if done.is_valid():
			done.call_deferred(img)
	var meta: Dictionary = AtlasStoreScript.frame_meta(path)
	if not meta.is_empty():
		var thumb_page_path := String(meta.get("thumb_page_path", ""))
		if not thumb_page_path.is_empty():
			var thumb_rect: Rect2i = meta.get("thumb_rect", Rect2i())
			IoService.run_io(func() -> Image:
				var page := _thumb_page_image(thumb_page_path)
				if page == null:
					return null
				if thumb_rect.position.x < 0 or thumb_rect.position.y < 0 or thumb_rect.end.x > page.get_width() or thumb_rect.end.y > page.get_height():
					return null
				return page.get_region(thumb_rect)
			, deliver)
			return
		IoService.run_io(func() -> Image:
			var page := _page_image(meta.page_path)
			if page == null:
				return null
			var region: Rect2i = meta.rect
			if region.end.x > page.get_width() or region.end.y > page.get_height() or region.position.x < 0 or region.position.y < 0:
				return null
			return ImageUtil.thumb_canvas(page.get_region(region), SNAP_SAMPLE_SIZE)
		, deliver)
		return
	IoService.run_io(func() -> Image:
		var image := ImageUtil.load_image(path)
		if image == null:
			return null
		return ImageUtil.thumb_canvas(image, SNAP_SAMPLE_SIZE)
	, deliver)

func has_all_thumbs(state: ModelStateEntry) -> bool:
	if _thumbs_complete.get(state, false):
		return true
	var paths := _state_frame_paths(state)
	for path in paths:
		if not path.is_empty() and not _thumbs.has(path):
			return false
	_thumbs_complete[state] = true
	return true

func acquire_thumbs(paths: Array[String]) -> void:
	for path in paths:
		if path.is_empty():
			continue
		_thumb_refs[path] = int(_thumb_refs.get(path, 0)) + 1

func release_thumbs(paths: Array[String]) -> void:
	var evicted := false
	for path in paths:
		if path.is_empty():
			continue
		var refs := int(_thumb_refs.get(path, 0)) - 1
		if refs > 0:
			_thumb_refs[path] = refs
			continue
		_thumb_refs.erase(path)
		if _thumbs.erase(path):
			evicted = true
	if evicted:
		_thumbs_complete.clear()
	if _thumb_refs.is_empty():
		_page_lock.lock()
		_thumb_page_images.clear()
		_thumb_page_mtimes.clear()
		_thumb_page_order.clear()
		_page_lock.unlock()

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
	return ImageUtil.thumb_canvas(image, SNAP_SAMPLE_SIZE)

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

func drop_texture(path: String) -> void:
	release_texture(path)

func acquire_texture(path: String) -> void:
	if path.is_empty():
		return
	_leases[path] = int(_leases.get(path, 0)) + 1
	_evict_when_ready.erase(path)

func release_texture(path: String, evict_immediately: bool = true) -> void:
	if _leases.has(path):
		var leases := int(_leases[path]) - 1
		if leases > 0:
			_leases[path] = leases
			return
		_leases.erase(path)
	if not evict_immediately:
		if _cache.has(path):
			_touch(path)
		return
	if _pinned.has(path):
		return
	if _cache.has(path):
		_evict_texture(path)
	elif _pending_requests.has(path):
		_evict_when_ready[path] = true
	else:
		_last_use.erase(path)

func evict_unleased(path: String) -> void:
	if _leases.has(path) or _pinned.has(path):
		return
	if _cache.has(path):
		_evict_texture(path)
	elif _pending_requests.has(path):
		_evict_when_ready[path] = true
	else:
		_last_use.erase(path)

func _evict_texture(path: String) -> void:
	_last_use.erase(path)
	var texture: ImageTexture = _cache.get(path)
	if texture == null:
		return
	_bytes -= _path_bytes.get(path, _texture_bytes(texture))
	_path_bytes.erase(path)
	_cache.erase(path)
	_order.erase(path)
	_bounds.erase(texture)

func pin_path(path: String) -> void:
	if path.is_empty():
		return
	_pinned[path] = true

func clear() -> void:
	_generation += 1
	_pending_requests.clear()
	_cache.clear()
	_order.clear()
	_pinned.clear()
	_leases.clear()
	_evict_when_ready.clear()
	_bounds.clear()
	_thumbs.clear()
	_thumbs_complete.clear()
	_thumb_refs.clear()
	_animated_assets.clear()
	_path_bytes.clear()
	_last_use.clear()
	_bytes = 0
	_page_lock.lock()
	_page_images.clear()
	_page_mtimes.clear()
	_page_order.clear()
	_page_last_use.clear()
	_page_total = 0
	_thumb_page_images.clear()
	_thumb_page_mtimes.clear()
	_thumb_page_order.clear()
	_page_lock.unlock()

func pending_count() -> int:
	return _pending_requests.size()

static func _decode_atlas_frame(path: String, meta: Dictionary, max_size: Vector2) -> Array:
	var cached := ImageUtil.load_vram_cache(path)
	if not cached.is_empty() and ImageUtil.image_fits(cached.image, max_size):
		return [cached.image, cached.used_rect]
	var page := _page_image(meta.page_path)
	if page == null:
		return [null, Rect2i()]
	var region: Rect2i = meta.rect
	if region.position.x < 0 or region.position.y < 0 or region.end.x > page.get_width() or region.end.y > page.get_height():
		return [null, Rect2i()]
	var canvas_size: Vector2i = meta.canvas_size
	var canvas := Image.create_empty(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	canvas.blit_rect(page, region, meta.offset)
	var used_rect := Rect2i(meta.offset, region.size)
	ImageUtil.compress_for_gpu(canvas, path, used_rect)
	return [canvas, used_rect]

static func _page_image(page_path: String) -> Image:
	_page_lock.lock()
	var image := _page_image_locked(page_path)
	_page_lock.unlock()
	return image

static func _thumb_page_image(page_path: String) -> Image:
	_page_lock.lock()
	var mtime := FileAccess.get_modified_time(PathUtil.get_real_path(page_path))
	var cached: Image = _thumb_page_images.get(page_path)
	if cached != null and int(_thumb_page_mtimes.get(page_path, -1)) == mtime:
		_thumb_page_order.erase(page_path)
		_thumb_page_order.append(page_path)
		_page_lock.unlock()
		return cached
	_page_lock.unlock()
	var image := Image.load_from_file(PathUtil.get_real_path(page_path))
	if image == null:
		return null
	if image.is_compressed() and image.decompress() != OK:
		return null
	_page_lock.lock()
	_thumb_page_images[page_path] = image
	_thumb_page_mtimes[page_path] = mtime
	_thumb_page_order.erase(page_path)
	_thumb_page_order.append(page_path)
	while _thumb_page_order.size() > THUMB_PAGE_CACHE_LIMIT:
		var evict: String = _thumb_page_order[0]
		_thumb_page_order.remove_at(0)
		_thumb_page_images.erase(evict)
		_thumb_page_mtimes.erase(evict)
	_page_lock.unlock()
	return image

static func _page_image_locked(page_path: String) -> Image:
	var real_path := PathUtil.get_real_path(page_path)
	var mtime := FileAccess.get_modified_time(real_path)
	var cached: Image = _page_images.get(page_path)
	if cached != null and int(_page_mtimes.get(page_path, -1)) == mtime:
		_page_order.erase(page_path)
		_page_order.append(page_path)
		_page_last_use[page_path] = Time.get_ticks_msec()
		return cached
	var image := Image.load_from_file(real_path)
	if image == null:
		return null
	if image.is_compressed() and image.decompress() != OK:
		return null
	_discard_page_locked(page_path)
	_page_images[page_path] = image
	_page_mtimes[page_path] = mtime
	_page_total += image.get_width() * image.get_height() * 4
	_page_order.append(page_path)
	_page_last_use[page_path] = Time.get_ticks_msec()
	while _page_order.size() > 1 and (_page_order.size() > PAGE_CACHE_LIMIT or _page_total > PAGE_CACHE_BUDGET_BYTES):
		_discard_page_locked(_page_order[0])
	return image

static func _discard_page_locked(page_path: String) -> void:
	var image: Image = _page_images.get(page_path)
	if image != null:
		_page_total -= image.get_width() * image.get_height() * 4
	_page_order.erase(page_path)
	_page_images.erase(page_path)
	_page_mtimes.erase(page_path)
	_page_last_use.erase(page_path)

static func unload_idle_pages(idle_seconds: float = PAGE_IDLE_UNLOAD_SECONDS) -> int:
	var now := Time.get_ticks_msec()
	var idle_ms := int(idle_seconds * 1000.0)
	var stale: Array[String] = []
	_page_lock.lock()
	for path: String in _page_order:
		if now - int(_page_last_use.get(path, 0)) >= idle_ms:
			stale.append(path)
	for path: String in stale:
		_discard_page_locked(path)
	_page_lock.unlock()
	return stale.size()

func _touch(path: String) -> void:
	_order.erase(path)
	_order.append(path)
	_last_use[path] = Time.get_ticks_msec()

func unload_idle(idle_seconds: float = IDLE_UNLOAD_SECONDS) -> int:
	var now := Time.get_ticks_msec()
	var idle_ms := int(idle_seconds * 1000.0)
	var removed := 0
	for path: String in _order.duplicate():
		if _pinned.has(path) or _leases.has(path):
			continue
		if not _cache.has(path):
			continue
		if now - int(_last_use.get(path, 0)) < idle_ms:
			continue
		release_texture(path)
		removed += 1
	return removed

func _store(path: String, texture: ImageTexture, used_rect: Rect2i, vram_bytes := -1) -> void:
	_last_use[path] = Time.get_ticks_msec()
	var entry_bytes := vram_bytes if vram_bytes >= 0 else _texture_bytes(texture)
	if _cache.has(path):
		_bytes -= _path_bytes.get(path, _texture_bytes(_cache[path]))
		_bounds.erase(_cache[path])
		_cache[path] = texture
		_touch(path)
		_bounds[texture] = normalized_bounds(texture, used_rect)
		_path_bytes[path] = entry_bytes
		_bytes += entry_bytes
		return
	_cache[path] = texture
	_order.append(path)
	_bounds[texture] = normalized_bounds(texture, used_rect)
	_path_bytes[path] = entry_bytes
	_bytes += entry_bytes
	while _bytes > CACHE_BUDGET_BYTES and _order.size() > 1:
		var oldest: String = _find_evictable()
		if oldest.is_empty():
			return
		_order.erase(oldest)
		var oldest_tex: ImageTexture = _cache[oldest]
		_bytes -= _path_bytes.get(oldest, _texture_bytes(oldest_tex))
		_bounds.erase(oldest_tex)
		_cache.erase(oldest)
		_path_bytes.erase(oldest)
		_last_use.erase(oldest)

func _find_evictable() -> String:
	for path in _order:
		if not _pinned.has(path) and not _leases.has(path):
			return path
	return ""

static func normalized_bounds(texture: Texture2D, used_rect: Rect2i) -> Rect2:
	var size := texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0 or used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return FULL_BOUNDS
	var pos := Vector2(used_rect.position) / size
	var end := Vector2(used_rect.end) / size
	return Rect2(pos, end - pos)

static func bounds_to_vec4(bounds: Rect2) -> Vector4:
	return Vector4(bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y)
