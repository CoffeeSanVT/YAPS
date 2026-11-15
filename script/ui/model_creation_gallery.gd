extends ItemList

const THUMBNAIL_SIZE := Vector2(100, 100)
const PREVIEW_HOVER_SECONDS := 3.0

var _paths: PackedStringArray
var _preview_blocked: Callable
var _next_thumbnail := 0
var _hovered_image := -1
var _hover_elapsed := 0.0
var _preview_requested := false
var _preview_request: AnimatedImageRuntime
var _preview_original: Texture2D
var _preview_frames: Array[Texture2D] = []
var _preview_durations := PackedFloat32Array()
var _preview_frame := 0
var _preview_elapsed := 0.0

func populate(paths: PackedStringArray, preview_blocked: Callable) -> void:
	_paths = paths
	_preview_blocked = preview_blocked
	for path in _paths:
		var index := add_item(path.get_file().get_basename())
		set_item_auto_translate_mode(index, Node.AUTO_TRANSLATE_MODE_DISABLED)
		set_item_tooltip_enabled(index, false)

func _exit_tree() -> void:
	if _preview_request != null:
		_preview_request.CancelPreview()
		_preview_request = null
	_preview_original = null
	_preview_frames.clear()
	_preview_durations.clear()
	_preview_blocked = Callable()
	_paths = PackedStringArray()
	clear()

func _load_next_thumbnail() -> void:
	var index := _next_thumbnail
	_next_thumbnail += 1
	var thumbnail := ImageUtil.load_thumbnail_texture(_paths[index], THUMBNAIL_SIZE)
	if index == _hovered_image and not _preview_frames.is_empty():
		_preview_original = thumbnail
	else:
		set_item_icon(index, thumbnail)

func _process(delta: float) -> void:
	if _next_thumbnail < _paths.size():
		_load_next_thumbnail()
	var hovered := _hovered_gallery_item()
	if hovered != _hovered_image:
		if not _preview_frames.is_empty():
			set_item_icon(_hovered_image, _preview_original)
			_preview_frames.clear()
			_preview_original = null
		_hovered_image = hovered
		_hover_elapsed = 0.0
		_preview_requested = false
	if hovered < 0:
		return
	if not _preview_frames.is_empty():
		_advance_preview(delta)
	elif not _preview_requested:
		_hover_elapsed += delta
		if _hover_elapsed >= PREVIEW_HOVER_SECONDS and _preview_request == null:
			_request_preview(hovered)

func _hovered_gallery_item() -> int:
	if not is_visible_in_tree() or (_preview_blocked.is_valid() and _preview_blocked.call()) or get_viewport().gui_get_hovered_control() != self:
		return -1
	return get_item_at_position(get_local_mouse_position(), true)

func _request_preview(index: int) -> void:
	_preview_requested = true
	var path := _paths[index]
	if path.get_extension().to_lower() not in ["gif", "apng", "png", "webp"] or not ImageUtil.is_animated_file(path):
		return
	var source := PathUtil.get_real_path(path)
	var request := AnimatedImageRuntime.new()
	_preview_request = request
	IoService.run_io(func() -> Variant:
		return request.LoadPreviewFrames(source, int(THUMBNAIL_SIZE.x), int(THUMBNAIL_SIZE.y))
	, func(data: Variant) -> void:
		if _preview_request != request:
			return
		_preview_request = null
		if index != _hovered_image or index != _hovered_gallery_item() or not _preview_requested or data == null or data.frames.size() < 2:
			return
		_preview_original = get_item_icon(index)
		for image: Image in data.frames:
			_preview_frames.append(ImageTexture.create_from_image(image))
		_preview_durations = data.durations
		_preview_frame = 0
		_preview_elapsed = 0.0
		set_item_icon(index, _preview_frames[0])
	, self)

func _advance_preview(delta: float) -> void:
	_preview_elapsed += delta
	var previous_frame := _preview_frame
	while _preview_elapsed >= _preview_durations[_preview_frame]:
		_preview_elapsed -= _preview_durations[_preview_frame]
		_preview_frame = (_preview_frame + 1) % _preview_frames.size()
	if _preview_frame != previous_frame:
		set_item_icon(_hovered_image, _preview_frames[_preview_frame])
