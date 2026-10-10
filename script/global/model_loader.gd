extends Node

signal model_loaded_changed

const TAG := "[ModelLoader] "
const TEXTURE_WORK_TIMEOUT_MS := 30000
const BLINK_FRAME_RATE := 1.0

var model_loaded: ModelProfile = null:
	set(value):
		if model_loaded == value:
			return
		model_loaded = value
		if model_loaded != null:
			print(TAG + "model loaded: '%s' (expressions: %d, emotions: %d, items: %d)" % [
				model_loaded.model_name,
				model_loaded.all_entries().size(),
				model_loaded.emotions.size(),
				model_loaded.items.size(),
			])
		else:
			print(TAG + "model unloaded")
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
		_hold_item_playback(true)
	textures.clear()
	SignalBus.model_images_reloaded.emit()
	if with_overlay:
		await wait_for_texture_work()
		_hold_item_playback(false)
		LoadingOverlay.hide_loading()

func _hold_item_playback(value: bool) -> void:
	if model_loaded == null:
		return
	for item in model_loaded.items:
		item.set_playback_held(value)

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
	var expression_files := PackedStringArray()
	var frame_files := PackedStringArray()
	for file: String in paths_to_images:
		if NameUtil.is_frame_file_name(file.get_file()):
			frame_files.append(file)
		else:
			expression_files.append(file)
	var expressions_save_path := PathUtil.expressions_folder_path(model_name)
	_copy_expression_files(expressions_save_path, expression_files, owner_object, func(success_files: Array) -> void:
		_assemble_static_model(model_name, success_files, frame_files, classifications, done, report, owner_object)
	)

func _copy_expression_files(dest_folder: String, paths_to_images: PackedStringArray, owner_object: Object, on_copied: Callable) -> void:
	IoService.run_io(func() -> Array:
		var success_files: Array[String] = []
		for file: String in paths_to_images:
			if ImageUtil.import_file(file, dest_folder, ImageUtil.imported_file_name(file)) == OK:
				success_files.append(file)
		return success_files
	, on_copied, owner_object)

func _assemble_static_model(model_name: String, files: Array, frame_files: PackedStringArray, classifications: Dictionary, done: Callable, report: Callable, owner_object: Object) -> void:
	var built := _build_static_model(model_name, files, frame_files, classifications)
	var model: ModelProfile = built.model
	var animated_entries: Array = built.animated_entries
	_copy_imported_frames(model, built.frame_targets, built.fallback_files, animated_entries.is_empty(), func() -> void:
		if animated_entries.is_empty():
			report.call(&"LOADING_SAVING")
			_finish_static_model(model, done)
			return
		report.call(&"LOADING_EXTRACTING_FRAMES")
		_extract_static_frames(model, animated_entries, done, report, owner_object)
	, owner_object)

func _extract_static_frames(model: ModelProfile, animated_entries: Array, done: Callable, report: Callable, owner_object: Object) -> void:
	var pending := { "count": animated_entries.size() }
	for item: Dictionary in animated_entries:
		_content.extract_frames_for_entry(model, item.entry, item.source, func() -> void:
			pending.count -= 1
			if pending.count <= 0:
				report.call(&"LOADING_SAVING")
				_finish_static_model(model, done)
		, owner_object)

func _build_static_model(model_name: String, files: Array, frame_files: PackedStringArray, classifications: Dictionary) -> Dictionary:
	var model := ModelProfile.new(model_name)
	var talking := model.talking_branch()
	var silence := model.silence_branch()
	var animated_entries: Array = []
	var frame_targets: Array = []
	var fallback_files: Array = []
	for file: String in files:
		_add_expression_entry(model, talking, silence, file, classifications, animated_entries)
	for file: String in frame_files:
		var state := _resolve_frame_target(model, talking, silence, file, classifications)
		if state == null:
			fallback_files.append(file)
			_add_expression_entry(model, talking, silence, file, classifications, animated_entries)
			continue
		if ImageUtil.is_animated_file(file):
			animated_entries.append({ "entry": state, "source": file })
		else:
			if not ImageUtil.is_animated_file(state.asset_path):
				state.loop_animation = false
			frame_targets.append({ "state": state, "source": file })
	return { "model": model, "animated_entries": animated_entries, "frame_targets": frame_targets, "fallback_files": fallback_files }

func _resolve_frame_target(model: ModelProfile, talking: ModelState, silence: ModelState, file: String, classifications: Dictionary) -> ModelStateEntry:
	var candidate := NameUtil.strip_frame_suffix(file.get_file().get_basename())
	var branch := talking if resolve_branch_for_file(file, classifications) == ModelState.TALKING else silence
	var names: Array[String] = [candidate]
	var stripped := NameUtil.strip_emotion_suffix(candidate)
	if stripped != candidate:
		names.append(stripped)
	for candidate_name: String in names:
		if candidate_name.is_empty():
			continue
		var entry := branch.find_entry(candidate_name)
		if entry != null:
			return entry
	for candidate_name: String in names:
		if candidate_name.is_empty():
			continue
		for other_entry in model.all_entries():
			if other_entry.state_name.to_lower() == candidate_name.to_lower():
				return other_entry
	return branch.resolve_default_entry()

func _add_expression_entry(model: ModelProfile, talking: ModelState, silence: ModelState, file: String, classifications: Dictionary, animated_entries: Array) -> void:
	var file_name := file.get_file()
	var branch := talking if resolve_branch_for_file(file, classifications) == ModelState.TALKING else silence
	var asset_path: String = PathUtil.expression_asset_path(model.model_name, ImageUtil.imported_file_name(file))
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

func _copy_imported_frames(model: ModelProfile, frame_targets: Array, fallback_files: Array, allow_default_frame_rate: bool, on_done: Callable, owner_object: Object) -> void:
	if frame_targets.is_empty() and fallback_files.is_empty():
		on_done.call()
		return
	var plan: Array = []
	var planned_names := {}
	for target: Dictionary in frame_targets:
		var state: ModelStateEntry = target.state
		var state_id: int = state.get_instance_id()
		if not planned_names.has(state_id):
			planned_names[state_id] = []
		var planned: Array = planned_names[state_id]
		var frame_name := _unique_frame_name(state, ImageUtil.imported_file_name(target.source), planned)
		planned.append(frame_name)
		plan.append({
			"source": target.source,
			"dest_folder": PathUtil.frames_folder_path(model.model_name, state.state_name),
			"file_name": frame_name,
			"state": state,
		})
	var expressions_folder := PathUtil.expressions_folder_path(model.model_name)
	IoService.run_io(func() -> bool:
		for item: Dictionary in plan:
			if ImageUtil.import_file(item.source, item.dest_folder, item.file_name) != OK:
				return false
		for file: String in fallback_files:
			if ImageUtil.import_file(file, expressions_folder, ImageUtil.imported_file_name(file)) != OK:
				return false
		return true
	, func(success: bool) -> void:
		if success:
			for item: Dictionary in plan:
				var state: ModelStateEntry = item.state
				state.frames.append(PathUtil.frame_asset_path(model.model_name, state.state_name, item.file_name))
			if allow_default_frame_rate and not plan.is_empty() and model.global_frame_rate <= 0.0:
				model.global_frame_rate = BLINK_FRAME_RATE
			save_model_profile(model)
		else:
			push_error(TAG + "failed to copy animation frame files")
		on_done.call()
	, owner_object)

func _unique_frame_name(state: ModelStateEntry, frame_name: String, planned_names: Array = []) -> String:
	if not _has_frame_named(state, frame_name) and not planned_names.has(frame_name):
		return frame_name
	var base := frame_name.get_basename()
	var ext := frame_name.get_extension()
	return NameUtil.unique_name(base, func(candidate: String) -> bool:
		return _has_frame_named(state, "%s.%s" % [candidate, ext]) or planned_names.has("%s.%s" % [candidate, ext])
	) + "." + ext

func _has_frame_named(state: ModelStateEntry, file_name: String) -> bool:
	for frame_path in state.frames:
		if frame_path.get_file().to_lower() == file_name.to_lower():
			return true
	return false

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

func remove_state_from_model(state: ModelStateEntry) -> void:
	_content.remove_state_from_model(state)

func add_emotion_with_images(emotion_name: String, talking_path: String = "", silence_path: String = "") -> ModelEmotion:
	return _content.add_emotion_with_images(emotion_name, talking_path, silence_path)

func add_frame_to_state(state: ModelStateEntry, file_path: String, done: Callable = Callable()) -> void:
	_content.add_frame_to_state(state, file_path, done)

func remove_frame_from_state(state: ModelStateEntry, asset_path: String) -> void:
	_content.remove_frame_from_state(state, asset_path)

func set_emotion_effect(emotion: ModelEmotion, effect: BaseEffect, category: int) -> void:
	_content.set_emotion_effect(emotion, effect, category)
