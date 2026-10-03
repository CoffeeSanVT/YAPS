class_name ItemAnimationDecoder
extends RefCounted

const TAG := "[ItemAnimationDecoder] "
const FRAMES_PER_STEP := 4

var _scheduled := false
var _on_decoded: Callable
var _images: Array = []
var _durations: Array[float] = []
var _frames: Array[Texture2D] = []
var _union := Rect2i()

func is_busy() -> bool:
	return _scheduled

func request(full_path: String, on_decoded: Callable, owner: Object) -> void:
	if _scheduled:
		return
	_scheduled = true
	_on_decoded = on_decoded
	IoService.run_io(func() -> Variant:
		var extracted := AnimatedImageRuntime.ExtractFrameImages(full_path)
		if extracted != null and extracted.Images != null:
			for image: Image in extracted.Images:
				ImageUtil.compress_for_gpu(image)
		return extracted
	, func(extracted: ExtractedFramesData) -> void:
		_on_extracted(extracted)
	, owner)

func _on_extracted(extracted: ExtractedFramesData) -> void:
	if extracted == null or extracted.Images == null or extracted.Images.is_empty():
		_scheduled = false
		push_warning(TAG + "no frames extracted")
		return
	_images = Array(extracted.Images)
	_durations.assign(extracted.Durations)
	_union = extracted.UnionRect
	_frames.clear()
	_build_step.call_deferred()

func _build_step() -> void:
	var count := mini(FRAMES_PER_STEP, _images.size())
	for i in count:
		var image: Image = _images.pop_front()
		_frames.append(ImageUtil.create_gpu_texture(image))
	if _images.is_empty():
		_finish()
		return
	_build_step.call_deferred()

func _finish() -> void:
	_scheduled = false
	var frames: Array[Texture2D] = []
	frames.assign(_frames)
	var durations: Array[float] = []
	durations.assign(_durations)
	_images.clear()
	_frames.clear()
	var data := AnimatedImageData.new()
	data.Frames = frames
	data.Durations = durations
	data.UnionRect = _union
	if _on_decoded.is_valid():
		_on_decoded.call(data)
	_on_decoded = Callable()
