class_name AtlasStore

const TAG := "[AtlasStore] "
const BuilderScript := preload("uid://bslytymmlyym8")

static var _busy := false
static var _pending: Array = []
static var _folder_cache: Dictionary[String, Dictionary] = {}

static func update_model_atlases(model: ModelProfile, done: Callable = Callable()) -> void:
	_run_model_pass(model, done, false)

static func repack_model_atlases(model: ModelProfile, done: Callable = Callable()) -> void:
	_run_model_pass(model, done, true)

static func has_pending_atlas_jobs(model: ModelProfile) -> bool:
	if model == null:
		return false
	if _busy:
		return true
	return not _collect_stale_jobs(model).is_empty()

static func _run_model_pass(model: ModelProfile, done: Callable, force: bool) -> void:
	if model == null:
		if done.is_valid():
			done.call(0)
		return
	if _busy:
		_pending.append({ "model": model, "done": done, "force": force })
		return
	_busy = true
	_run_for(model, done, force)

static func _run_for(model: ModelProfile, done: Callable, force: bool) -> void:
	var jobs := _collect_stale_jobs(model, force)
	if jobs.is_empty():
		_finish_run(model, done, 0)
		return
	IoService.run_io(func() -> Dictionary:
		var built := 0
		var deleted := 0
		var aborted := 0
		for job: Dictionary in jobs:
			var state: ModelStateEntry = job.state
			var out_dir: String = job.out_dir
			var old_doc := _read_doc(out_dir, BuilderScript.metadata_file_name(state.state_name))
			if not _sources_complete(state, old_doc, out_dir):
				aborted += 1
				push_error(TAG + "rebuild aborted for '%s': missing pixel source for some frame(s)" % state.state_name)
				continue
			var resolver := _make_resolver(old_doc, out_dir)
			var result: Dictionary = BuilderScript.build_state_atlas(state, out_dir, { "load_frame": resolver })
			if result.is_empty() or (result.files as Array).is_empty():
				aborted += 1
				continue
			built += 1
			var keep: Dictionary[String, bool] = {}
			for page_meta: Dictionary in result.pages:
				keep[String(page_meta.get("file", ""))] = true
			_delete_orphan_pages(BuilderScript.metadata_file_name(state.state_name).replace("_atlas.json", "_atlas_p"), out_dir, keep)
			var keep_thumb: Dictionary[String, bool] = {}
			for thumb_page_meta: Dictionary in result.thumb_pages:
				keep_thumb[String(thumb_page_meta.get("file", ""))] = true
			_delete_orphan_pages(BuilderScript.thumb_page_prefix(state.state_name), out_dir.path_join(BuilderScript.THUMB_DIR), keep_thumb)
			deleted += _delete_frame_files(result.frames_meta, out_dir)
		return { "built": built, "deleted": deleted, "aborted": aborted }
	, func(result: Dictionary) -> void:
		for job: Dictionary in jobs:
			_folder_cache.erase(String(job.out_dir))
		print(TAG + "model '%s': %d atlas(es) saved, %d frame file(s) removed, %d aborted" % [
			model.model_name, result.built, result.deleted, result.aborted,
		])
		_finish_run(model, done, result.built)
	)

static func _finish_run(_model: ModelProfile, done: Callable, built: int) -> void:
	if done.is_valid():
		done.call(built)
	if _pending.is_empty():
		_busy = false
		return
	var next: Dictionary = _pending.pop_front()
	_run_for(next.model, next.done, next.force)

static func _collect_stale_jobs(model: ModelProfile, force: bool = false) -> Array:
	var jobs: Array = []
	if model == null:
		return jobs
	for entry: ModelStateEntry in model.all_entries():
		var frames := entry.frames
		if frames.is_empty():
			continue
		var out_dir := String(frames[0]).get_base_dir()
		var snapshot := ModelStateEntry.new(entry.state_name, entry.asset_path)
		snapshot.frames = frames.duplicate()
		snapshot.frame_rate = entry.frame_rate
		snapshot.loop_animation = entry.loop_animation
		if not force and (_is_fresh(snapshot, out_dir) or _adopt_existing_atlas(snapshot, out_dir)):
			continue
		jobs.append({ "state": snapshot, "out_dir": out_dir })
	return jobs

static func frame_meta(frame_path: String) -> Dictionary:
	var folder := String(frame_path).get_base_dir()
	if folder.is_empty():
		return {}
	var cache := _folder_docs(folder)
	var meta: Dictionary = cache.get("by_path", {}).get(String(frame_path), {})
	if meta.is_empty():
		return {}
	return {
		"page_path": meta.page_path,
		"rect": meta.rect,
		"offset": meta.offset,
		"canvas_size": meta.canvas_size,
		"thumb_page_path": meta.get("thumb_page_path", ""),
		"thumb_rect": meta.get("thumb_rect", Rect2i()),
	}

static func _folder_docs(folder: String) -> Dictionary:
	var folder_mtime := FileAccess.get_modified_time(PathUtil.get_real_path(folder))
	var cached: Dictionary = _folder_cache.get(folder, {})
	if not cached.is_empty() and int(cached.get("mtime", -1)) == folder_mtime and _docs_unchanged(cached):
		return cached
	var docs: Array[Dictionary] = []
	var by_path: Dictionary[String, Dictionary] = {}
	var dir := DirAccess.open(PathUtil.get_real_path(folder))
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry.ends_with("_atlas.json"):
				var doc := _read_doc(folder, entry)
				if not doc.is_empty():
					doc["folder"] = folder
					doc["file_mtime"] = FileAccess.get_modified_time(PathUtil.get_real_path(folder.path_join(entry)))
					doc["file_name"] = entry
					docs.append(doc)
					var pages: Array = doc.get("pages", [])
					var thumb_pages: Array = doc.get("thumb_pages", [])
					for frame_entry: Dictionary in doc.get("frames", []):
						var page_index: int = frame_entry.get("page", -1)
						if page_index < 0 or page_index >= pages.size():
							continue
						var rect_values: Array = frame_entry.get("rect", [])
						var offset_values: Array = frame_entry.get("offset", [])
						var size_values: Array = frame_entry.get("size", [])
						if rect_values.size() != 4 or offset_values.size() != 2 or size_values.size() != 2:
							continue
						var page_size_values: Array = pages[page_index].get("size", [0, 0])
						var thumb_page_path := ""
						var thumb_rect := Rect2i()
						var thumb_page_index: int = int(frame_entry.get("thumb_page", -1))
						var thumb_rect_values: Array = frame_entry.get("thumb_rect", [])
						if thumb_page_index >= 0 and thumb_page_index < thumb_pages.size() and thumb_rect_values.size() == 4:
							thumb_page_path = folder.path_join(BuilderScript.THUMB_DIR).path_join(String(thumb_pages[thumb_page_index].get("file", "")))
							thumb_rect = Rect2i(thumb_rect_values[0], thumb_rect_values[1], thumb_rect_values[2], thumb_rect_values[3])
						by_path[String(frame_entry.get("path", ""))] = {
							"page_path": folder.path_join(String(pages[page_index].get("file", ""))),
							"rect": Rect2i(rect_values[0], rect_values[1], rect_values[2], rect_values[3]),
							"offset": Vector2i(offset_values[0], offset_values[1]),
							"canvas_size": Vector2i(size_values[0], size_values[1]),
							"page_size": Vector2i(page_size_values[0], page_size_values[1]),
							"thumb_page_path": thumb_page_path,
							"thumb_rect": thumb_rect,
						}
			entry = dir.get_next()
		dir.list_dir_end()
	var fresh := { "mtime": folder_mtime, "docs": docs, "by_path": by_path }
	if not docs.is_empty():
		_folder_cache[folder] = fresh
	return fresh

static func _docs_unchanged(cached: Dictionary) -> bool:
	for doc: Dictionary in cached.get("docs", []):
		var doc_path := String(cached.get("folder", "")).path_join(String(doc.get("file_name", "")))
		if FileAccess.get_modified_time(PathUtil.get_real_path(doc_path)) != int(doc.get("file_mtime", -1)):
			return false
	return true

static func _read_doc(out_dir: String, file_name: String) -> Dictionary:
	var doc_path := out_dir.path_join(file_name)
	if not FileAccess.file_exists(doc_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(doc_path))
	if parsed == null or not (parsed is Dictionary):
		return {}
	return parsed

static func _is_fresh(state: ModelStateEntry, out_dir: String) -> bool:
	var parsed := _read_doc(out_dir, BuilderScript.metadata_file_name(state.state_name))
	if parsed.is_empty():
		return false
	if int(parsed.get("version", 0)) != BuilderScript.DOC_VERSION:
		return false
	if not _thumb_size_matches(parsed):
		return false
	if not _thumb_refs_valid(parsed, out_dir):
		return false
	var frames_meta: Array = parsed.get("frames", [])
	if frames_meta.size() != state.frames.size():
		return false
	var json_mtime := FileAccess.get_modified_time(PathUtil.get_real_path(out_dir.path_join(BuilderScript.metadata_file_name(state.state_name))))
	for i: int in state.frames.size():
		var frame_path := String(state.frames[i])
		if String(frames_meta[i].get("path", "")) != frame_path:
			return false
		if FileAccess.get_modified_time(PathUtil.get_real_path(frame_path)) > json_mtime:
			return false
	for page_meta: Dictionary in parsed.get("pages", []):
		if not FileAccess.file_exists(out_dir.path_join(String(page_meta.get("file", "")))):
			return false
	return true

static func _adopt_existing_atlas(state: ModelStateEntry, out_dir: String) -> bool:
	var wanted := BuilderScript.metadata_file_name(state.state_name)
	if FileAccess.file_exists(out_dir.path_join(wanted)):
		return false
	var dir := DirAccess.open(PathUtil.get_real_path(out_dir))
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	var adopted := false
	while entry != "":
		if entry.ends_with("_atlas.json") and entry != wanted:
			var doc := _read_doc(out_dir, entry)
			if _doc_matches_frames(doc, state.frames, out_dir) and _doc_pages_exist(doc, out_dir):
				adopted = _rename_atlas_files(state, out_dir, doc, entry)
			break
		entry = dir.get_next()
	dir.list_dir_end()
	return adopted

static func _doc_matches_frames(doc: Dictionary, frames: Array[String], out_dir: String) -> bool:
	if int(doc.get("version", 0)) != BuilderScript.DOC_VERSION:
		return false
	if not _thumb_size_matches(doc):
		return false
	if not _thumb_refs_valid(doc, out_dir):
		return false
	var frames_meta: Array = doc.get("frames", [])
	if frames_meta.size() != frames.size():
		return false
	for i: int in frames.size():
		if String(frames_meta[i].get("path", "")) != String(frames[i]):
			return false
	return true

static func _thumb_size_matches(doc: Dictionary) -> bool:
	var thumb_size: Array = doc.get("thumb_size", [])
	return thumb_size.size() == 2 and int(thumb_size[0]) == BuilderScript.THUMB_SIZE and int(thumb_size[1]) == BuilderScript.THUMB_SIZE

static func _thumb_refs_valid(doc: Dictionary, out_dir: String) -> bool:
	var thumb_pages: Array = doc.get("thumb_pages", [])
	var thumb_dir := out_dir.path_join(BuilderScript.THUMB_DIR)
	for page_meta: Dictionary in thumb_pages:
		var file_name := String(page_meta.get("file", ""))
		if file_name.is_empty() or not FileAccess.file_exists(thumb_dir.path_join(file_name)):
			return false
	for frame_entry: Dictionary in doc.get("frames", []):
		if int(frame_entry.get("page", -1)) < 0:
			continue
		var thumb_page_index: int = int(frame_entry.get("thumb_page", -1))
		if thumb_page_index < 0 or thumb_page_index >= thumb_pages.size():
			return false
		var rect_values: Array = frame_entry.get("thumb_rect", [])
		if rect_values.size() != 4 or int(rect_values[2]) <= 0 or int(rect_values[3]) <= 0:
			return false
	return true

static func _doc_pages_exist(doc: Dictionary, out_dir: String) -> bool:
	for page_meta: Dictionary in doc.get("pages", []):
		if not FileAccess.file_exists(out_dir.path_join(String(page_meta.get("file", "")))):
			return false
	return true

static func _rename_atlas_files(state: ModelStateEntry, out_dir: String, doc: Dictionary, old_json_name: String) -> bool:
	var new_json_name := BuilderScript.metadata_file_name(state.state_name)
	var renamed_pages: Array = []
	var keep: Dictionary[String, bool] = {}
	for page_index: int in (doc.get("pages", []) as Array).size():
		var page_meta: Dictionary = doc.pages[page_index]
		var old_file := String(page_meta.get("file", ""))
		var new_file := BuilderScript.page_file_name(state.state_name, page_index)
		if old_file != new_file:
			if DirAccess.rename_absolute(PathUtil.get_real_path(out_dir.path_join(old_file)), PathUtil.get_real_path(out_dir.path_join(new_file))) != OK:
				push_error(TAG + "failed to rename page '%s' during adoption" % old_file)
				return false
			page_meta["file"] = new_file
		keep[new_file] = true
		renamed_pages.append({ "file": new_file, "size": page_meta.get("size", [0, 0]) })
	var thumb_dir := out_dir.path_join(BuilderScript.THUMB_DIR)
	var renamed_thumb_pages: Array = []
	var keep_thumb: Dictionary[String, bool] = {}
	for thumb_page_index: int in (doc.get("thumb_pages", []) as Array).size():
		var thumb_page_meta: Dictionary = doc.thumb_pages[thumb_page_index]
		var old_thumb_file := String(thumb_page_meta.get("file", ""))
		var new_thumb_file := BuilderScript.thumb_page_file_name(state.state_name, thumb_page_index)
		if old_thumb_file != new_thumb_file:
			if DirAccess.rename_absolute(PathUtil.get_real_path(thumb_dir.path_join(old_thumb_file)), PathUtil.get_real_path(thumb_dir.path_join(new_thumb_file))) != OK:
				push_error(TAG + "failed to rename thumb page '%s' during adoption" % old_thumb_file)
				return false
			thumb_page_meta["file"] = new_thumb_file
		keep_thumb[new_thumb_file] = true
		renamed_thumb_pages.append({ "file": new_thumb_file, "size": thumb_page_meta.get("size", [0, 0]) })
	doc["state"] = state.state_name
	doc["pages"] = renamed_pages
	doc["thumb_pages"] = renamed_thumb_pages
	var file := FileAccess.open(PathUtil.get_real_path(out_dir.path_join(new_json_name)), FileAccess.WRITE)
	if file == null:
		push_error(TAG + "failed to write adopted metadata '%s'" % new_json_name)
		return false
	file.store_string(JSON.stringify(doc, "\t"))
	file.close()
	_delete_orphan_pages(old_json_name.replace("_atlas.json", "_atlas_p"), out_dir, keep)
	_delete_orphan_pages(new_json_name.replace("_atlas.json", "_atlas_p"), out_dir, keep)
	_delete_orphan_pages(old_json_name.replace("_atlas.json", "_thumb_p"), thumb_dir, keep_thumb)
	_delete_orphan_pages(new_json_name.replace("_atlas.json", "_thumb_p"), thumb_dir, keep_thumb)
	if old_json_name != new_json_name:
		DirAccess.remove_absolute(PathUtil.get_real_path(out_dir.path_join(old_json_name)))
	_folder_cache.erase(out_dir)
	print(TAG + "adopted atlas '%s' for state '%s'" % [new_json_name, state.state_name])
	return true

static func _delete_orphan_pages(page_prefix: String, out_dir: String, keep: Dictionary[String, bool]) -> void:
	var dir := DirAccess.open(PathUtil.get_real_path(out_dir))
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with(page_prefix) and entry.ends_with(".png") and not keep.has(entry):
			DirAccess.remove_absolute(PathUtil.get_real_path(out_dir.path_join(entry)))
			DirAccess.remove_absolute(PathUtil.get_real_path(out_dir.path_join(entry + ".import")))
		entry = dir.get_next()
	dir.list_dir_end()

static func _sources_complete(state: ModelStateEntry, old_doc: Dictionary, out_dir: String) -> bool:
	var pages: Array = old_doc.get("pages", [])
	var old_meta: Dictionary[String, Dictionary] = {}
	for frame_entry: Dictionary in old_doc.get("frames", []):
		var page_index: int = frame_entry.get("page", -1)
		old_meta[String(frame_entry.get("path", ""))] = {
			"trimmed": frame_entry.get("trimmed", false),
			"page_ok": page_index >= 0 and page_index < pages.size()
				and FileAccess.file_exists(out_dir.path_join(String(pages[page_index].get("file", "")))),
		}
	for frame_path: String in state.frames:
		if FileAccess.file_exists(PathUtil.get_real_path(frame_path)):
			continue
		var old: Dictionary = old_meta.get(frame_path, {})
		if old.is_empty():
			return false
		if bool(old.get("trimmed", false)) and not bool(old.get("page_ok", false)):
			return false
	return true

static func _make_resolver(old_doc: Dictionary, out_dir: String) -> Callable:
	var page_images: Dictionary[String, Image] = {}
	return func(path: String) -> Image:
		var image := ImageUtil.load_image(path)
		if image != null:
			return image
		var pages: Array = old_doc.get("pages", [])
		for frame_entry: Dictionary in old_doc.get("frames", []):
			if String(frame_entry.get("path", "")) != path:
				continue
			if not bool(frame_entry.get("trimmed", false)):
				return null
			var page_index: int = frame_entry.get("page", -1)
			if page_index < 0 or page_index >= pages.size():
				return null
			var page_path := out_dir.path_join(String(pages[page_index].get("file", "")))
			var page: Image = page_images.get(page_path)
			if page == null:
				page = Image.load_from_file(PathUtil.get_real_path(page_path))
				if page == null:
					return null
				page_images[page_path] = page
			var rect_values: Array = frame_entry.get("rect", [])
			if rect_values.size() != 4:
				return null
			var region := Rect2i(rect_values[0], rect_values[1], rect_values[2], rect_values[3])
			if region.position.x < 0 or region.position.y < 0 or region.end.x > page.get_width() or region.end.y > page.get_height():
				return null
			var canvas_values: Array = frame_entry.get("size", [])
			var offset_values: Array = frame_entry.get("offset", [])
			if canvas_values.size() != 2 or offset_values.size() != 2:
				return page.get_region(region)
			var canvas := Image.create_empty(canvas_values[0], canvas_values[1], false, Image.FORMAT_RGBA8)
			canvas.blit_rect(page, region, Vector2i(offset_values[0], offset_values[1]))
			return canvas
		return null

static func _delete_frame_files(frames_meta: Array, out_dir: String) -> int:
	var deleted := 0
	for meta: Dictionary in frames_meta:
		var path := String(meta.get("path", ""))
		if path.is_empty() or String(path).get_base_dir() != out_dir:
			continue
		var real_path := PathUtil.get_real_path(path)
		if not FileAccess.file_exists(real_path):
			continue
		if DirAccess.remove_absolute(real_path) != OK:
			push_warning(TAG + "could not remove frame file '%s'" % path)
			continue
		DirAccess.remove_absolute(real_path + ImageUtil.VRAM_CACHE_SUFFIX)
		DirAccess.remove_absolute(real_path + ".import")
		deleted += 1
	return deleted
