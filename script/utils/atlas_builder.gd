class_name AtlasBuilder
extends RefCounted

const TAG := "[AtlasBuilder] "
const AtlasPackerScript := preload("res://script/utils/atlas_packer.gd")
const DEFAULT_ALPHA_THRESHOLD := 0.0

static func build_state_atlas(state: ModelStateEntry, out_dir: String, options: Dictionary = {}) -> Dictionary:
	var alpha_threshold: float = options.get("alpha_threshold", DEFAULT_ALPHA_THRESHOLD)
	var padding: int = options.get("padding", AtlasPackerScript.DEFAULT_PADDING)
	var min_page: int = options.get("min_page", AtlasPackerScript.MIN_PAGE_SIZE)
	var max_page: int = options.get("max_page", AtlasPackerScript.MAX_PAGE_SIZE)
	var save: bool = options.get("save", true)
	var load_frame: Callable = options.get("load_frame", Callable())
	var merge_singles: bool = options.get("merge_singles", true)
	var paths: Array[String] = state.frames
	if paths.is_empty():
		paths = [state.asset_path]
	var sprites: Array[Image] = []
	var sizes: Array[Vector2i] = []
	var frames_meta: Array = []
	var source_pixels := 0
	var trimmed_pixels := 0
	var empty_count := 0
	for i: int in paths.size():
		var path := paths[i]
		var image: Image = null
		if load_frame.is_valid():
			image = load_frame.call(path)
		else:
			image = ImageUtil.load_image(path)
		var trimmed: Dictionary = {}
		var source_size := Vector2i.ZERO
		if image != null and not image.is_empty():
			source_size = Vector2i(image.get_width(), image.get_height())
			trimmed = AtlasPackerScript.trim_sprite(image, alpha_threshold)
		var meta := {
			"path": path,
			"page": -1,
			"rect": Rect2i(),
			"offset": Vector2i.ZERO,
			"size": source_size,
			"trimmed": false,
			"empty": trimmed.is_empty(),
		}
		source_pixels += source_size.x * source_size.y
		if trimmed.is_empty():
			empty_count += 1
			sprites.append(null)
			sizes.append(Vector2i.ZERO)
		else:
			var sprite: Image = trimmed.image
			sprites.append(sprite)
			sizes.append(trimmed.size)
			trimmed_pixels += trimmed.size.x * trimmed.size.y
			meta.offset = trimmed.offset
			meta.trimmed = true
			meta.trimmed_size = trimmed.size
		frames_meta.append(meta)
	var pack_result: Dictionary = AtlasPackerScript.pack(sizes, padding, min_page, max_page, merge_singles)
	var pages_meta: Array = []
	var atlas_pixels := 0
	var files: Array[String] = []
	var pack_pages: Array = pack_result.pages
	for page_index: int in pack_pages.size():
		var page: Dictionary = pack_pages[page_index]
		var page_size: Vector2i = page.size
		atlas_pixels += page_size.x * page_size.y
		var atlas := Image.create_empty(page_size.x, page_size.y, false, Image.FORMAT_RGBA8)
		for placement: Dictionary in page.placements:
			var sprite: Image = sprites[placement.index]
			var rect: Rect2i = placement.rect
			atlas.blit_rect(sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), rect.position)
			var meta: Dictionary = frames_meta[placement.index]
			meta.page = page_index
			meta.rect = rect
		if save:
			var file_path := out_dir.path_join(page_file_name(state.state_name, page_index))
			var err := atlas.save_png(file_path)
			if err != OK:
				push_error(TAG + "failed to save '%s': %s" % [file_path, error_string(err)])
			else:
				files.append(file_path)
				pages_meta.append({ "file": file_path.get_file(), "size": [page_size.x, page_size.y] })
		else:
			pages_meta.append({ "file": "", "size": [page_size.x, page_size.y] })
	if save:
		files.append(_save_metadata(state, out_dir, frames_meta, pages_meta, alpha_threshold, padding))
	return {
		"state": state.state_name,
		"frame_count": paths.size(),
		"packed_count": _packed_count(frames_meta),
		"empty_count": empty_count,
		"pages": pages_meta,
		"page_count": pack_pages.size(),
		"source_pixels": source_pixels,
		"trimmed_pixels": trimmed_pixels,
		"atlas_pixels": atlas_pixels,
		"fill_ratio": pack_result.fill_ratio,
		"trim_ratio": 1.0 - float(trimmed_pixels) / float(source_pixels) if source_pixels > 0 else 0.0,
		"alpha_threshold": alpha_threshold,
		"padding": padding,
		"files": files,
		"frames_meta": frames_meta,
	}

static func _packed_count(frames_meta: Array) -> int:
	var count := 0
	for meta: Dictionary in frames_meta:
		if meta.page >= 0:
			count += 1
	return count

static func _save_metadata(state: ModelStateEntry, out_dir: String, frames_meta: Array, pages_meta: Array, alpha_threshold: float, padding: int) -> String:
	var frames_json: Array = []
	for meta: Dictionary in frames_meta:
		var rect: Rect2i = meta.rect
		frames_json.append({
			"path": meta.path,
			"page": meta.page,
			"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			"offset": [meta.offset.x, meta.offset.y],
			"size": [meta.size.x, meta.size.y],
			"trimmed_size": [meta.trimmed_size.x, meta.trimmed_size.y] if meta.trimmed else [0, 0],
			"trimmed": meta.trimmed,
			"empty": meta.empty,
		})
	var document := {
		"state": state.state_name,
		"frame_rate": state.frame_rate,
		"loop_animation": state.loop_animation,
		"alpha_threshold": alpha_threshold,
		"padding": padding,
		"power_of_two": true,
		"pages": pages_meta,
		"frames": frames_json,
	}
	var json_path := out_dir.path_join(metadata_file_name(state.state_name))
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		push_error(TAG + "failed to save metadata '%s': %s" % [json_path, error_string(FileAccess.get_open_error())])
		return json_path
	file.store_string(JSON.stringify(document, "\t"))
	file.close()
	return json_path

static func metadata_file_name(state_name: String) -> String:
	return "%s_atlas.json" % _sanitize(state_name)

static func page_file_name(state_name: String, page_index: int) -> String:
	return "%s_atlas_p%d.png" % [_sanitize(state_name), page_index]

static func _sanitize(name: String) -> String:
	var invalid := "/\\:*?\"<>|%. "
	var sanitized := ""
	for character: String in name:
		sanitized += "_" if invalid.contains(character) else character
	return sanitized if not sanitized.is_empty() else "atlas"
