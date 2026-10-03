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

const FORMAT_NAMES := { Image.FORMAT_DXT1: "BC1/DXT1", Image.FORMAT_DXT5: "BC3/DXT5", Image.FORMAT_BPTC_RGBA: "BC7/BPTC", Image.FORMAT_BPTC_RGBFU: "BC6H/BPTC" }
const VRAM_CACHE_SUFFIX := ".bc"
const VRAM_CACHE_VERSION := 2
const COMPRESS_SKIPPED := 0
const COMPRESS_DONE := 1
const COMPRESS_FAILED := 2
const VRAM_CACHE_FORMATS := { Image.FORMAT_DXT1: 8, Image.FORMAT_DXT5: 16, Image.FORMAT_BPTC_RGBA: 16, Image.FORMAT_BPTC_RGBFU: 16 }

static func model_compress_enabled() -> bool:
	var model := ModelLoader.model_loaded
	return model != null and model.vram_texture_compression

static func compress_for_gpu(image: Image, path := "", used_rect := Rect2i()) -> void:
	if not model_compress_enabled():
		return
	match AnimatedImageRuntime.CompressTexture(image):
		COMPRESS_SKIPPED:
			return
		COMPRESS_FAILED:
			_count_lock.lock()
			_compress_fail_count += 1
			_count_lock.unlock()
			return
	_count_lock.lock()
	_compress_ok_count += 1
	_last_compressed_format = str(FORMAT_NAMES.get(image.get_format(), image.get_format()))
	_count_lock.unlock()
	if not path.is_empty():
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
	var bytes_per_block: int = VRAM_CACHE_FORMATS.get(format, 0)
	@warning_ignore("integer_division")
	var blocks := ((width + 3) / 4) * ((height + 3) / 4)
	var expected := blocks * bytes_per_block
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
	_last_compressed_format = str(FORMAT_NAMES.get(format, format))
	_count_lock.unlock()
	return { "image": image, "used_rect": rect }

static func _write_vram_cache(path: String, image: Image, used_rect: Rect2i) -> void:
	var format := image.get_format()
	if not VRAM_CACHE_FORMATS.has(format):
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



static func load_image(path: String) -> Image:
	var full_path := PathUtil.get_real_path(path)
	if not FileAccess.file_exists(full_path):
		push_error(TAG_LOAD + "file not found: " + full_path)
		return null
	return Image.load_from_file(full_path)

static func load_texture_with_rect(path: String) -> TextureLoadResult:
	var full_path := PathUtil.get_real_path(path)
	if not FileAccess.file_exists(full_path):
		push_error(TAG_LOAD + "file not found: " + full_path)
		return TextureLoadResult.new()
	var cached := load_vram_cache(path)
	if not cached.is_empty():
		return TextureLoadResult.new(ImageTexture.create_from_image(cached.image), cached.used_rect)
	if is_animated_file(full_path):
		var decoded: Dictionary = AnimatedImageRuntime.LoadFirstFrameData(full_path, model_compress_enabled())
		if decoded != null and decoded[&"texture"] != null:
			return TextureLoadResult.new(decoded[&"texture"], decoded[&"used_rect"])
	var image := load_image(path)
	if image == null:
		return TextureLoadResult.new()
	var used_rect := image.get_used_rect()
	compress_for_gpu(image, path, used_rect)
	return TextureLoadResult.new(ImageTexture.create_from_image(image), used_rect)



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
	var data: ExtractedFrameFilesData = AnimatedImageRuntime.ExtractFrameFiles(PathUtil.get_real_path(source_path), dest_folder, file_base)
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

