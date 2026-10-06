class_name ItemAnimationDecoder
extends RefCounted

const TAG := "[ItemAnimationDecoder] "
const FRAMES_DIR_SUFFIX := "_frames"
const META_FILE := "meta.json"

var _scheduled := false
var _on_decoded: Callable

func is_busy() -> bool:
	return _scheduled

func request(asset_path: String, on_decoded: Callable, owner: Object, source_path: String = "") -> void:
	if _scheduled:
		return
	_scheduled = true
	_on_decoded = on_decoded
	IoService.run_io(func() -> Dictionary:
		return _extract_sync(asset_path, source_path)
	, func(result: Dictionary) -> void:
		_scheduled = false
		if result.is_empty():
			push_warning(TAG + "no frames extracted for: " + asset_path)
			return
		if _on_decoded.is_valid():
			_on_decoded.call(_build_data(result))
		_on_decoded = Callable()
	, owner)

static func frames_res_folder(asset_path: String) -> String:
	return asset_path.get_base_dir().path_join(asset_path.get_file() + FRAMES_DIR_SUFFIX)

func _extract_sync(asset_path: String, source_override: String) -> Dictionary:
	var folder_res := frames_res_folder(asset_path)
	var folder_fs := PathUtil.get_real_path(folder_res)
	var source_path := PathUtil.get_real_path(source_override) if not source_override.is_empty() else PathUtil.get_real_path(asset_path)
	if not FileAccess.file_exists(source_path):
		push_warning(TAG + "asset not found: " + source_path)
		return {}
	var cached := _load_meta(folder_res, folder_fs, source_path)
	if not cached.is_empty():
		return cached
	if DirAccess.dir_exists_absolute(folder_fs):
		PathUtil.delete_dir_recursive(folder_fs)
	var dir_err := PathUtil.ensure_dir(folder_fs)
	if dir_err != OK:
		push_error(TAG + "failed to create folder '%s': %s" % [folder_fs, error_string(dir_err)])
		return {}
	var data: ExtractedFrameFilesData = AnimatedImageRuntime.ExtractFrameFiles(source_path, folder_fs, asset_path.get_file().get_basename())
	if data == null or data.FileNames.is_empty():
		push_warning(TAG + "no frames extracted from: " + asset_path)
		return {}
	var files: Array[String] = []
	files.assign(data.FileNames)
	var durations: Array[float] = []
	durations.assign(data.Durations)
	var union := _union_of_frames(folder_fs, files)
	var source_file := FileAccess.open(source_path, FileAccess.READ)
	var source_size := source_file.get_length() if source_file != null else -1
	if source_file != null:
		source_file.close()
	var meta := {
		"files": files,
		"durations": durations,
		"union": [union.position.x, union.position.y, union.size.x, union.size.y],
		"source_size": source_size,
	}
	_save_meta(folder_fs.path_join(META_FILE), meta)
	print(TAG + "extracted %d frame(s) from '%s'" % [files.size(), asset_path])
	return { "folder": folder_res, "files": files, "durations": durations, "union": union }

func _load_meta(folder_res: String, folder_fs: String, source_path: String) -> Dictionary:
	var meta_path := folder_fs.path_join(META_FILE)
	if not FileAccess.file_exists(meta_path):
		return {}
	var file := FileAccess.open(meta_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var files: Array = parsed.get("files", [])
	var durations: Array = parsed.get("durations", [])
	var union_values: Array = parsed.get("union", [])
	var source_size: int = int(parsed.get("source_size", -1))
	var source_file := FileAccess.open(source_path, FileAccess.READ)
	var current_size := source_file.get_length() if source_file != null else -2
	if source_file != null:
		source_file.close()
	if files.is_empty() or durations.size() != files.size() or union_values.size() != 4 or current_size != source_size:
		return {}
	for file_name: String in files:
		if not FileAccess.file_exists(folder_fs.path_join(file_name)):
			return {}
	var typed_files: Array[String] = []
	typed_files.assign(files)
	var typed_durations: Array[float] = []
	typed_durations.assign(durations)
	var union := Rect2i(int(union_values[0]), int(union_values[1]), int(union_values[2]), int(union_values[3]))
	return { "folder": folder_res, "files": typed_files, "durations": typed_durations, "union": union }

func _union_of_frames(folder_fs: String, files: Array[String]) -> Rect2i:
	var union := Rect2i()
	for file_name in files:
		var image := Image.load_from_file(folder_fs.path_join(file_name))
		if image == null:
			continue
		var rect := image.get_used_rect()
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		union = rect if union.size.x <= 0 and union.size.y <= 0 else union.merge(rect)
	return union

func _save_meta(meta_path: String, meta: Dictionary) -> void:
	var file := FileAccess.open(meta_path, FileAccess.WRITE)
	if file == null:
		push_warning(TAG + "failed to write meta file: " + meta_path)
		return
	file.store_string(JSON.stringify(meta))
	file.close()

func _build_data(result: Dictionary) -> AnimatedImageData:
	var files: Array[String] = []
	files.assign(result.files)
	var paths: Array[String] = []
	for file_name in files:
		paths.append(String(result.folder).path_join(file_name))
	var frames: Array[Texture2D] = []
	frames.resize(files.size())
	var durations: Array[float] = []
	durations.assign(result.durations)
	var data := AnimatedImageData.new()
	data.Frames = frames
	data.FramePaths = paths
	data.Durations = durations
	data.UnionRect = result.union
	return data