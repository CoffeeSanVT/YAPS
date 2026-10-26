class_name ImageUtil

const TAG_LOAD := "[ImageLoad] "
const TAG_EXTRACT := "[FrameExtract] "
const TAG_VRAM := "[VRAMCompress] "
const ANIMATED_EXTENSIONS: PackedStringArray = ["gif", "apng", "webm"]
const MIN_FPS := 1.0
const MAX_FPS := 60.0
const WEBP_QUALITY := 0.8


static var _compress_ok_count := 0
static var _compress_fail_count := 0
static var _last_compressed_format := ""
static var _count_lock := Mutex.new()

const VRAM_FORMATS := {
	Image.FORMAT_DXT1: { "bytes": 8, "name": "BC1/DXT1" },
	Image.FORMAT_DXT5: { "bytes": 16, "name": "BC3/DXT5" },
	Image.FORMAT_BPTC_RGBA: { "bytes": 16, "name": "BC7/BPTC" },
	Image.FORMAT_BPTC_RGBFU: { "bytes": 16, "name": "BC6H/BPTC" },
}
const VRAM_CACHE_SUFFIX := ".bc"
const VRAM_CACHE_VERSION := 4
const COMPRESS_DONE := 1
const COMPRESS_FAILED := 2

static func model_compress_enabled() -> bool:
	var model := ModelLoader.model_loaded
	return model != null and model.vram_texture_compression

static func fit_image(image: Image, max_size: Vector2) -> void:
	if image == null or image.is_empty() or max_size.x <= 0.0 or max_size.y <= 0.0:
		return
	var size := Vector2(image.get_width(), image.get_height())
	if size.x <= max_size.x and size.y <= max_size.y:
		return
	var ratio := minf(max_size.x / size.x, max_size.y / size.y)
	image.resize(maxi(1, int(size.x * ratio)), maxi(1, int(size.y * ratio)), Image.INTERPOLATE_BILINEAR)

static func image_fits(image: Image, max_size: Vector2) -> bool:
	if max_size.x <= 0.0 or max_size.y <= 0.0 or image == null or image.is_empty():
		return true
	return image.get_width() <= max_size.x and image.get_height() <= max_size.y

static func thumb_canvas(source: Image, size: int) -> Image:
	if source == null or source.is_empty() or size <= 0:
		return null
	var image := source.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	var source_size := Vector2(image.get_width(), image.get_height())
	var ratio := minf(float(size) / source_size.x, float(size) / source_size.y)
	var w := maxi(1, int(source_size.x * ratio))
	var h := maxi(1, int(source_size.y * ratio))
	image.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var canvas := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	canvas.blit_rect(image, Rect2i(Vector2i.ZERO, Vector2i(w, h)), Vector2i((size - w) >> 1, (size - h) >> 1))
	return canvas

static func compress_for_gpu(image: Image, path := "", used_rect := Rect2i()) -> void:
	if not model_compress_enabled():
		return
	var result := AnimatedImageRuntime.CompressTexture(image)
	_count_lock.lock()
	if result == COMPRESS_FAILED:
		_compress_fail_count += 1
	elif result == COMPRESS_DONE:
		_compress_ok_count += 1
		_last_compressed_format = _vram_format_name(image.get_format())
	_count_lock.unlock()
	if result == COMPRESS_DONE and not path.is_empty():
		_write_vram_cache(path, image, used_rect)

static func load_vram_cache(path: String) -> Dictionary:
	if not model_compress_enabled():
		return {}
	var real_path := PathUtil.get_real_path(path)
	var sidecar := real_path + VRAM_CACHE_SUFFIX
	if not FileAccess.file_exists(sidecar):
		return {}
	var source_time := FileAccess.get_modified_time(real_path)
	var cache_time := FileAccess.get_modified_time(sidecar)
	if source_time > 0 and cache_time > 0 and cache_time < source_time:
		return {}
	var f := FileAccess.open(sidecar, FileAccess.READ)
	if f == null:
		return {}
	var magic := f.get_buffer(4).get_string_from_ascii()
	var version := f.get_32()
	if magic != "YBCP" or version != VRAM_CACHE_VERSION:
		f.close()
		return {}
	var width := f.get_32()
	var height := f.get_32()
	var format := f.get_32()
	var rect := Rect2i(f.get_32(), f.get_32(), f.get_32(), f.get_32())
	var data_size := f.get_32()
	var bytes_per_block: int = _vram_block_bytes(format)
	var expected := _vram_data_size(width, height, bytes_per_block)
	if width <= 0 or height <= 0 or bytes_per_block == 0 or data_size != expected:
		f.close()
		return {}
	var data := f.get_buffer(data_size)
	f.close()
	if data.size() != data_size:
		return {}
	var image := Image.create_from_data(width, height, false, format, data)
	if image == null:
		return {}
	_count_lock.lock()
	_compress_ok_count += 1
	_last_compressed_format = _vram_format_name(format)
	_count_lock.unlock()
	return { "image": image, "used_rect": rect }

static func _vram_block_bytes(format: int) -> int:
	return VRAM_FORMATS.get(format, {}).get("bytes", 0)

static func _vram_format_name(format: int) -> String:
	return str(VRAM_FORMATS.get(format, {}).get("name", format))

static func _vram_data_size(width: int, height: int, bytes_per_block: int) -> int:
	@warning_ignore("integer_division")
	return ((width + 3) / 4) * ((height + 3) / 4) * bytes_per_block

static func _write_vram_cache(path: String, image: Image, used_rect: Rect2i) -> void:
	var format := image.get_format()
	if not VRAM_FORMATS.has(format):
		return
	var f := FileAccess.open(PathUtil.get_real_path(path) + VRAM_CACHE_SUFFIX, FileAccess.WRITE)
	if f == null:
		return
	var data := image.get_data()
	f.store_buffer("YBCP".to_ascii_buffer())
	f.store_32(VRAM_CACHE_VERSION)
	f.store_32(image.get_width())
	f.store_32(image.get_height())
	f.store_32(format)
	f.store_32(used_rect.position.x)
	f.store_32(used_rect.position.y)
	f.store_32(used_rect.size.x)
	f.store_32(used_rect.size.y)
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()

static func log_compression_summary() -> void:
	_count_lock.lock()
	var ok := _compress_ok_count
	var failed := _compress_fail_count
	var fmt := _last_compressed_format
	_compress_ok_count = 0
	_compress_fail_count = 0
	_last_compressed_format = ""
	_count_lock.unlock()
	if ok == 0 and failed == 0:
		return
	print(TAG_VRAM + "summary: %d compressed, %d kept RGBA8 (last format: %s)" % [ok, failed, fmt])

static func create_gpu_texture(image: Image) -> ImageTexture:
	compress_for_gpu(image)
	return ImageTexture.create_from_image(image)

static func estimate_vram_bytes(image: Image) -> int:
	if image == null or image.is_empty():
		return -1
	var block_bytes: int = _vram_block_bytes(image.get_format())
	if block_bytes > 0:
		return _vram_data_size(image.get_width(), image.get_height(), block_bytes)
	return image.get_width() * image.get_height() * 4

static func estimate_vram_bytes_heuristic(size: Vector2i, compressed: bool) -> int:
	if compressed:
		return _vram_data_size(size.x, size.y, 16)
	return size.x * size.y * 4



static func load_image(path: String) -> Image:
	var full_path := PathUtil.get_real_path(path)
	if not FileAccess.file_exists(full_path):
		push_error(TAG_LOAD + "file not found: " + full_path)
		return null
	return Image.load_from_file(full_path)

static func load_gpu_image(path: String) -> Image:
	var cached := load_vram_cache(path)
	if not cached.is_empty():
		return cached.image
	var image := load_image(path)
	if image != null:
		compress_for_gpu(image, path, image.get_used_rect())
	return image

static func load_texture_with_rect(path: String) -> TextureLoadResult:
	var full_path := PathUtil.get_real_path(path)
	if not FileAccess.file_exists(full_path):
		push_error(TAG_LOAD + "file not found: " + full_path)
		return TextureLoadResult.new()
	var cached := load_vram_cache(path)
	if not cached.is_empty():
		return TextureLoadResult.new(ImageTexture.create_from_image(cached.image), cached.used_rect, estimate_vram_bytes(cached.image))
	if is_animated_file(full_path):
		var decoded: Dictionary = AnimatedImageRuntime.LoadFirstFrameData(full_path, model_compress_enabled(), 0)
		if decoded != null and decoded[&"texture"] != null:
			var decoded_tex: Texture2D = decoded[&"texture"]
			var decoded_size := Vector2i(decoded_tex.get_width(), decoded_tex.get_height())
			return TextureLoadResult.new(decoded_tex, decoded[&"used_rect"], estimate_vram_bytes_heuristic(decoded_size, model_compress_enabled()))
	var image := load_image(path)
	if image == null:
		return TextureLoadResult.new()
	var used_rect := image.get_used_rect()
	compress_for_gpu(image, path, used_rect)
	return TextureLoadResult.new(ImageTexture.create_from_image(image), used_rect, estimate_vram_bytes(image))



static func is_animated_file(file_path: String) -> bool:
	var extension := file_path.get_extension().to_lower()
	if extension == "png":
		return _is_apng(file_path)
	if extension == "webp":
		return _is_animated_webp(file_path)
	return ANIMATED_EXTENSIONS.has(extension)

static func _is_apng(file_path: String) -> bool:
	if not FileAccess.file_exists(file_path):
		return false
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return false
	file.big_endian = true
	file.seek(8)
	var file_length := file.get_length()
	while file.get_position() + 8 <= file_length:
		var chunk_length := file.get_32()
		var chunk_type := file.get_buffer(4).get_string_from_ascii()
		if chunk_type == "acTL":
			return true
		if chunk_type == "IDAT" or chunk_length > file_length:
			return false
		file.seek(file.get_position() + chunk_length + 4)
	return false

static func _is_animated_webp(file_path: String) -> bool:
	if not FileAccess.file_exists(file_path):
		return false
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return false
	file.seek(12)
	if file.get_buffer(4).get_string_from_ascii() != "VP8X":
		return false
	file.seek(20)
	return (file.get_8() & 0x02) != 0



static func extract_frames(source_path: String, dest_folder: String, dest_res_folder: String, file_base: String, on_done: Callable, owner: Object = null) -> void:
	IoService.run_io(func() -> Dictionary:
		return _extract_sync(source_path, dest_folder, file_base)
	, func(result: Dictionary) -> void:
		var frame_paths: Array[String] = []
		if not result.is_empty():
			for file_name: String in result.file_names:
				frame_paths.append(dest_res_folder.path_join(file_name))
		if on_done.is_valid():
			on_done.call(frame_paths, result.get("frame_rate", 0.0))
	, owner)

static func _extract_sync(source_path: String, dest_folder: String, file_base: String) -> Dictionary:
	var dir_err := PathUtil.ensure_dir(dest_folder)
	if dir_err != OK:
		push_error(TAG_EXTRACT + "failed to create folder '%s': %s" % [dest_folder, error_string(dir_err)])
		return {}
	var data: ExtractedFrameFilesData = AnimatedImageRuntime.ExtractFrameFiles(PathUtil.get_real_path(source_path), dest_folder, file_base, 0)
	if data == null or data.Durations.is_empty():
		push_warning(TAG_EXTRACT + "no frames extracted from: " + source_path)
		return {}
	var total_duration := 0.0
	for duration: float in data.Durations:
		total_duration += duration
	var avg_duration: float = total_duration / data.Durations.size()
	var frame_rate := clampf(1.0 / maxf(avg_duration, 0.001), MIN_FPS, MAX_FPS)
	print(TAG_EXTRACT + "extracted %d frame(s) from '%s' at %.1f fps" % [data.FileNames.size(), source_path, frame_rate])
	return { "file_names": data.FileNames, "frame_rate": frame_rate }



static func imported_file_name(file_path: String) -> String:
	var file_name := file_path.get_file()
	if file_name.get_extension().to_lower() == "png" and not is_animated_file(file_path):
		return "%s.webp" % file_name.get_basename()
	return file_name

static func import_file(src_path: String, dest_folder: String, dest_name: String) -> Error:
	var err := PathUtil.ensure_dir(dest_folder)
	if err != OK:
		return err
	var destination := dest_folder.path_join(dest_name)
	if dest_name.get_extension().to_lower() == "webp" and src_path.get_extension().to_lower() == "png":
		var image := Image.load_from_file(PathUtil.get_real_path(src_path))
		if image == null:
			return ERR_FILE_CANT_OPEN
		return image.save_webp(destination, true, WEBP_QUALITY)
	return DirAccess.copy_absolute(PathUtil.get_real_path(src_path), destination)

