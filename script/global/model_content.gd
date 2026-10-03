class_name ModelContent

const TAG := "[ModelContent] "

var _loader: Node

func _init(loader: Node) -> void:
	_loader = loader

func _require_model(caller: String) -> ModelProfile:
	if _loader.model_loaded == null:
		push_error(TAG + caller + ": no model loaded")
	return _loader.model_loaded

func _save_file_to_model_folder(internal_path: String, file_path: String, dest_file_name: String = "", on_done: Callable = Callable()) -> void:
	if _require_model("_save_file_to_model_folder") == null:
		return
	var model_folder_path := PathUtil.get_model_folder_path(_loader.model_loaded.model_name).path_join(internal_path)
	var file_name := dest_file_name if not dest_file_name.is_empty() else ImageUtil.imported_file_name(file_path)
	var destination := model_folder_path.path_join(file_name)
	var src := file_path
	IoService.run_io(func() -> Error:
		if FileAccess.file_exists(destination):
			var remove_err := DirAccess.remove_absolute(destination)
			if remove_err != OK:
				return remove_err
		return ImageUtil.import_file(src, model_folder_path, file_name)
	, func(err: Error) -> void:
		if err != OK:
			push_error(TAG + "save_file_to_model_folder: failed IO for '%s' -> '%s': %s" % [src, destination, error_string(err)])
		if on_done.is_valid():
			on_done.call(err)
	)

func add_dropped_item_to_model(file_path: String, pos: Vector2, sc: Vector2) -> Item:
	var model := _require_model("add_dropped_item_to_model")
	if model == null:
		return null
	var file_name := file_path.get_file()
	var item_name := file_name.get_basename()
	if model.has_item_named(item_name):
		item_name = NameUtil.unique_name(item_name, model.has_item_named)
	var asset_path := PathUtil.item_asset_path(model.model_name, ImageUtil.imported_file_name(file_path))
	var item := Item.new(item_name, asset_path)
	item.position = pos
	item.scale = sc
	item.enabled = true
	_save_file_to_model_folder(PathUtil.ITEMS_SUBFOLDER, file_path, "", func(err: Error) -> void:
		if err != OK or _loader.model_loaded != model:
			return
		model.items.append(item)
		_loader.save_model()
		SignalBus.items_changed.emit()
	)
	return item

func add_state_to_model(file_path: String, branch_name: String = ModelState.SILENCE) -> ModelStateEntry:
	var model := _require_model("add_state_to_model")
	if model == null:
		return null
	var branch := model.ensure_branch(branch_name)
	var file_name := file_path.get_file()
	var emotion_name := NameUtil.emotion_name_for_file(file_name)
	var entry_name := branch.unique_entry_name(emotion_name)
	var asset_path := PathUtil.expression_asset_path(model.model_name, ImageUtil.imported_file_name(file_path))
	var state := ModelStateEntry.new(entry_name, asset_path)
	var is_neutral := NameUtil.is_neutral_file_name(file_name)
	_persist_state_image(model, state, file_path, func() -> void:
		if is_neutral:
			if branch.default_entry != null:
				branch.add_emotion_entry(branch.default_entry)
			branch.default_entry = state
		elif branch.default_entry == null:
			branch.default_entry = state
		else:
			branch.add_emotion_entry(state)
		if not is_neutral:
			model.ensure_emotion(entry_name)
	, func() -> void:
		SignalBus.model_triggers_changed.emit()
	)
	return state

func add_emotion_with_images(emotion_name: String, talking_path: String = "", silence_path: String = "") -> ModelEmotion:
	var model := _require_model("add_emotion_with_images")
	if model == null:
		return null
	var clean_name := emotion_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Emotion"
	clean_name = NameUtil.unique_name(clean_name, model.has_emotion_named)
	var emotion := model.ensure_emotion(clean_name)
	emotion.trigger = StartTalking.new()
	if not talking_path.is_empty():
		_add_emotion_image(clean_name, talking_path, ModelState.TALKING)
	if not silence_path.is_empty():
		_add_emotion_image(clean_name, silence_path, ModelState.SILENCE)
	_loader.save_model()
	SignalBus.states_changed.emit()
	SignalBus.model_triggers_changed.emit()
	return emotion

func _add_emotion_image(emotion_name: String, file_path: String, branch_name: String) -> void:
	var model: ModelProfile = _loader.model_loaded
	var asset_path := PathUtil.expression_asset_path(model.model_name, ImageUtil.imported_file_name(file_path))
	var entry := ModelStateEntry.new(emotion_name, asset_path)
	_persist_state_image(model, entry, file_path, func() -> void:
		model.ensure_branch(branch_name).add_emotion_entry(entry)
	)

func _persist_state_image(model: ModelProfile, entry: ModelStateEntry, file_path: String, on_saved: Callable, on_persisted: Callable = Callable()) -> void:
	var is_animated := ImageUtil.is_animated_file(file_path)
	_save_file_to_model_folder(PathUtil.EXPRESSIONS_SUBFOLDER, file_path, "", func(err: Error) -> void:
		if err != OK or _loader.model_loaded != model:
			return
		on_saved.call()
		if is_animated:
			extract_frames_for_entry(model, entry, file_path)
		_loader.save_model()
		SignalBus.states_changed.emit()
		if on_persisted.is_valid():
			on_persisted.call()
	)

func add_frame_to_state(state: ModelStateEntry, file_path: String, done: Callable = Callable()) -> void:
	if _require_model("add_frame_to_state") == null or state == null:
		push_error(TAG + "add_frame_to_state: invalid model or state")
		return
	if ImageUtil.is_animated_file(file_path):
		_add_animated_frames_to_state(state, file_path, done)
		return
	var model: ModelProfile = _loader.model_loaded
	var frame_name := ImageUtil.imported_file_name(file_path)
	if _has_frame_named(state, frame_name):
		var base := frame_name.get_basename()
		var ext := frame_name.get_extension()
		frame_name = NameUtil.unique_name(base, func(c: String) -> bool: return _has_frame_named(state, "%s.%s" % [c, ext])) + "." + ext
	var frames_folder := PathUtil.frames_internal_folder_path(state.state_name)
	var asset_path := PathUtil.frame_asset_path(model.model_name, state.state_name, frame_name)
	_save_file_to_model_folder(frames_folder, file_path, frame_name, func(err: Error) -> void:
		if err == OK and _loader.model_loaded == model:
			state.frames.append(asset_path)
			_loader.save_model()
		if done.is_valid():
			done.call()
	)

func _add_animated_frames_to_state(state: ModelStateEntry, file_path: String, done: Callable = Callable()) -> void:
	if _require_model("_add_animated_frames_to_state") == null or state == null:
		push_error(TAG + "add_animated_frames_to_state: invalid model or state")
		return
	var model: ModelProfile = _loader.model_loaded
	var file_base := _unique_frame_base(state, file_path.get_file().get_basename())
	_extract_frames(model, state, file_path, file_base, func(frame_paths: Array[String], frame_rate: float) -> void:
		if not frame_paths.is_empty() and _loader.model_loaded == model:
			state.frames.append_array(frame_paths)
			state.frame_rate = frame_rate
			_loader.save_model()
		if done.is_valid():
			done.call()
	)

func extract_frames_for_entry(model: ModelProfile, entry: ModelStateEntry, source_path: String, on_finished: Callable = Callable(), owner: Object = null) -> void:
	_extract_frames(model, entry, source_path, entry.state_name, func(frame_paths: Array[String], frame_rate: float) -> void:
		if not frame_paths.is_empty():
			entry.frames.append_array(frame_paths)
			entry.frame_rate = frame_rate
			if model.global_frame_rate <= 0.0:
				model.global_frame_rate = frame_rate
			if model.global_animation_chance <= 0.0:
				model.global_animation_chance = entry.animation_chance
			_loader.save_model_profile(model)
			SignalBus.state_frames_changed.emit()
		if on_finished.is_valid():
			on_finished.call()
	, owner)

func _extract_frames(model: ModelProfile, entry: ModelStateEntry, source_path: String, file_base: String, on_done: Callable, owner: Object = null) -> void:
	ImageUtil.extract_frames(
		source_path,
		PathUtil.frames_folder_path(model.model_name, entry.state_name),
		PathUtil.frames_res_path(model.model_name, entry.state_name),
		file_base,
		on_done,
		owner
	)

func _unique_frame_base(state: ModelStateEntry, base: String) -> String:
	return NameUtil.unique_name(base, func(candidate: String) -> bool: return _has_frame_named(state, "%s_001.webp" % candidate))

func remove_frame_from_state(state: ModelStateEntry, asset_path: String) -> void:
	if state == null:
		return
	state.frames.erase(asset_path)
	_loader.save_model()

func set_emotion_effect(emotion: ModelEmotion, effect: BaseEffect, category: int) -> void:
	if emotion == null:
		return
	var is_movement := category == EffectLayerResolver.Category.MOVEMENT
	var old := emotion.movement_effect if is_movement else emotion.filter_effect
	if old != null and old != effect:
		old.deactivate()
	if is_movement:
		emotion.movement_effect = effect
	else:
		emotion.filter_effect = effect
	if _loader.model_loaded != null:
		_loader.save_model()
		SignalBus.model_effects_changed.emit()

func _has_frame_named(state: ModelStateEntry, file_name: String) -> bool:
	for frame_path in state.frames:
		if frame_path.get_file().to_lower() == file_name.to_lower():
			return true
	return false