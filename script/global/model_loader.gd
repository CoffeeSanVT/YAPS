extends Node

signal model_loaded_changed

const TAG := "[ModelLoader] "
const TEXTURE_WORK_TIMEOUT_MS := 30000

var model_loaded: ModelProfile = null:
	set(value):
		if model_loaded == value:
			return
		model_loaded = value
		model_loaded_changed.emit()

var textures := TextureCache.new()

var _saver := IoService.DeferredSaver.new()
var _content := ModelContent.new(self)

func _ready() -> void:
	PathUtil.ensure_model_folder()
	add_child(ModelWsApi.new(self))

func _exit_tree() -> void:
	IoService.wait_for_io()

func reload_textures() -> void:
	var with_overlay := model_loaded != null
	if with_overlay:
		var status: StringName = &"LOADING_COMPRESSING" if model_loaded.vram_texture_compression else &"LOADING_LOADING"
		await LoadingOverlay.show_loading(status)
	textures.clear()
	SignalBus.model_images_reloaded.emit()
	if with_overlay:
		await wait_for_texture_work()
		LoadingOverlay.hide_loading()

func wait_for_texture_work() -> void:
	var deadline_ms := Time.get_ticks_msec() + TEXTURE_WORK_TIMEOUT_MS
	while textures.pending_count() > 0 or _items_decoding():
		if Time.get_ticks_msec() >= deadline_ms:
			push_warning(TAG + "texture work wait timed out; continuing")
			break
		await get_tree().process_frame
	ImageUtil.log_compression_summary()

func _items_decoding() -> bool:
	if model_loaded == null:
		return false
	for item in model_loaded.items:
		if item.is_decoding():
			return true
	return false

func save_model() -> void:
	if model_loaded == null:
		push_error(TAG + "save_model: no model loaded")
		return
	save_model_profile(model_loaded)

func save_and_sync_triggers() -> void:
	save_model()
	SignalBus.model_triggers_changed.emit()

func save_model_profile(model: ModelProfile) -> void:
	var save_path: String = model.resource_path
	if save_path.is_empty():
		save_path = PathUtil.get_model_folder_path(model.model_name).path_join(ModelProfileStore.MODEL_FILE_NAME)
	model.resource_path = save_path
	_saver.save_resource(model, save_path)

func create_and_save_static_model(model_name: String, paths_to_images: PackedStringArray, done: Callable = Callable(), classifications: Dictionary = {}, on_progress: Callable = Callable(), owner_object: Object = null) -> void:
	if model_name.strip_edges().is_empty():
		push_error(TAG + "create_and_save_static_model: model name is empty")
		return
	var report := func(status: StringName) -> void:
		if on_progress.is_valid():
			on_progress.call(status)
	report.call(&"LOADING_COPYING_FILES")
	var expressions_save_path := PathUtil.expressions_folder_path(model_name)
	_copy_expression_files(expressions_save_path, paths_to_images, owner_object, func(success_files: Array) -> void:
		_assemble_static_model(model_name, success_files, classifications, done, report, owner_object)
	)

func _copy_expression_files(dest_folder: String, paths_to_images: PackedStringArray, owner_object: Object, on_copied: Callable) -> void:
	IoService.run_io(func() -> Array:
		var success_files: Array[String] = []
		for file: String in paths_to_images:
			if ImageUtil.import_file(file, dest_folder, ImageUtil.imported_file_name(file)) == OK:
				success_files.append(file)
		return success_files
	, on_copied, owner_object)

func _assemble_static_model(model_name: String, files: Array, classifications: Dictionary, done: Callable, report: Callable, owner_object: Object) -> void:
	var built := _build_static_model(model_name, files, classifications)
	var model: ModelProfile = built.model
	var animated_entries: Array = built.animated_entries
	if animated_entries.is_empty():
		report.call(&"LOADING_SAVING")
		_finish_static_model(model, done)
		return
	report.call(&"LOADING_EXTRACTING_FRAMES")
	_extract_static_frames(model, animated_entries, done, report, owner_object)

func _extract_static_frames(model: ModelProfile, animated_entries: Array, done: Callable, report: Callable, owner_object: Object) -> void:
	var pending := { "count": animated_entries.size() }
	for item: Dictionary in animated_entries:
		_content.extract_frames_for_entry(model, item.entry, item.source, func() -> void:
			pending.count -= 1
			if pending.count <= 0:
				report.call(&"LOADING_SAVING")
				_finish_static_model(model, done)
		, owner_object)

func _build_static_model(model_name: String, files: Array, classifications: Dictionary) -> Dictionary:
	var model := ModelProfile.new(model_name)
	var talking := model.talking_branch()
	var silence := model.silence_branch()
	var animated_entries: Array = []
	for file: String in files:
		var file_name := file.get_file()
		var branch := talking if resolve_branch_for_file(file, classifications) == ModelState.TALKING else silence
		var asset_path: String = PathUtil.expression_asset_path(model_name, ImageUtil.imported_file_name(file))
		var entry: ModelStateEntry
		if NameUtil.is_neutral_file_name(file_name):
			entry = ModelStateEntry.new(file_name.get_basename(), asset_path)
			branch.default_entry = entry
		else:
			var emotion_name: String = NameUtil.emotion_name_for_file(file_name)
			var entry_name := branch.unique_entry_name(emotion_name)
			entry = ModelStateEntry.new(entry_name, asset_path)
			branch.add_emotion_entry(entry)
			model.ensure_emotion(emotion_name)
		if ImageUtil.is_animated_file(file):
			animated_entries.append({ "entry": entry, "source": file })
	return { "model": model, "animated_entries": animated_entries }

func _finish_static_model(model: ModelProfile, done: Callable) -> void:
	model.resource_path = PathUtil.get_model_folder_path(model.model_name).path_join(ModelProfileStore.MODEL_FILE_NAME)
	save_model_profile(model)
	if done.is_valid():
		done.call(model)

func resolve_branch_for_file(file_path: String, classifications: Dictionary = {}) -> String:
	var classified: String = classifications.get(file_path, "")
	if not classified.is_empty():
		return classified
	if file_path.get_file().to_lower().contains("talking"):
		return ModelState.TALKING
	return ModelState.SILENCE

func list_found_models(done: Callable) -> void:
	ModelProfileStore.list_found_models(done)

func add_dropped_item_to_model(file_path: String, pos: Vector2, sc: Vector2) -> Item:
	return _content.add_dropped_item_to_model(file_path, pos, sc)

func add_state_to_model(file_path: String, branch_name: String = ModelState.SILENCE) -> ModelStateEntry:
	return _content.add_state_to_model(file_path, branch_name)

func add_emotion_with_images(emotion_name: String, talking_path: String = "", silence_path: String = "") -> ModelEmotion:
	return _content.add_emotion_with_images(emotion_name, talking_path, silence_path)

func add_frame_to_state(state: ModelStateEntry, file_path: String, done: Callable = Callable()) -> void:
	_content.add_frame_to_state(state, file_path, done)

func remove_frame_from_state(state: ModelStateEntry, asset_path: String) -> void:
	_content.remove_frame_from_state(state, asset_path)

func set_emotion_effect(emotion: ModelEmotion, effect: BaseEffect, category: int) -> void:
	_content.set_emotion_effect(emotion, effect, category)
