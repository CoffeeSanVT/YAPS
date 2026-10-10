class_name ModelProfileStore

const MODEL_FILE_NAME := "model.tres"

static func list_found_models(done: Callable) -> void:
	var model_folder_path := PathUtil.get_models_folder_path()
	IoService.run_io(func() -> Array:
		var models: Array[ModelProfile] = []
		var dir := DirAccess.open(model_folder_path)
		if dir == null:
			return models
		dir.list_dir_begin()
		while true:
			var folder := dir.get_next()
			if folder == "":
				break
			if folder.begins_with("."):
				continue
			if dir.current_is_dir():
				var model := _load_in_folder(model_folder_path.path_join(folder))
				if model != null:
					models.append(model)
		dir.list_dir_end()
		return models
	, done)

static func _load_in_folder(model_folder_path: String) -> ModelProfile:
	var model_path := model_folder_path.path_join(MODEL_FILE_NAME)
	if not FileAccess.file_exists(model_path):
		return null
	var model := ResourceLoader.load(model_path) as ModelProfile
	if model == null:
		return null
	_normalize_emotion_naming(model)
	return model

static func _normalize_emotion_naming(model: ModelProfile) -> void:
	_strip_entry_name_suffixes(model)
	_promote_default_entries(model)
	_merge_duplicate_emotions(model)
	_apply_blink_loop_defaults(model)

static func _apply_blink_loop_defaults(model: ModelProfile) -> void:
	for entry in model.all_entries():
		if entry.frames.is_empty() or entry.asset_path.is_empty():
			continue
		if ImageUtil.is_animated_file(entry.asset_path):
			continue
		var all_blink := true
		for frame_path in entry.frames:
			if not NameUtil.is_frame_file_name(frame_path.get_file()):
				all_blink = false
				break
		if all_blink:
			entry.loop_animation = false

static func _strip_entry_name_suffixes(model: ModelProfile) -> void:
	for branch in model.branches:
		for entry in branch.emotion_entries:
			var stripped := NameUtil.strip_emotion_suffix(entry.state_name)
			if stripped == entry.state_name or branch.find_entry(stripped) != null:
				continue
			entry.state_name = stripped

static func _promote_default_entries(model: ModelProfile) -> void:
	for branch in model.branches:
		if branch.default_entry != null:
			continue
		for entry: ModelStateEntry in branch.emotion_entries.duplicate():
			if not NameUtil.is_neutral_entry_name(entry.state_name):
				continue
			branch.default_entry = entry
			branch.emotion_entries.erase(entry)
			break

static func _merge_duplicate_emotions(model: ModelProfile) -> void:
	for emotion: ModelEmotion in model.emotions.duplicate():
		if NameUtil.is_neutral_entry_name(emotion.emotion_name):
			_remove_orphan_neutral_emotion(model, emotion)
			continue
		var stripped := NameUtil.strip_emotion_suffix(emotion.emotion_name)
		if stripped == emotion.emotion_name:
			continue
		var base := model.get_emotion(stripped)
		if base == null:
			emotion.emotion_name = stripped
			continue
		if _has_emotion_entry_named(model, emotion.emotion_name):
			continue
		_merge_emotion_into_base(model, base, emotion)

static func _remove_orphan_neutral_emotion(model: ModelProfile, emotion: ModelEmotion) -> void:
	if _has_emotion_entry_named(model, emotion.emotion_name):
		return
	if model.default_emotion.to_lower() == emotion.emotion_name.to_lower():
		model.default_emotion = ""
	model.emotions.erase(emotion)

static func _merge_emotion_into_base(model: ModelProfile, base: ModelEmotion, emotion: ModelEmotion) -> void:
	if base.trigger == null and emotion.trigger != null:
		base.trigger = emotion.trigger
	if base.twitch_event == null and emotion.twitch_event != null:
		base.twitch_event = emotion.twitch_event
	if base.movement_effect == null and emotion.movement_effect != null:
		base.movement_effect = emotion.movement_effect
	if base.filter_effect == null and emotion.filter_effect != null:
		base.filter_effect = emotion.filter_effect
	model.emotions.erase(emotion)
	if model.default_emotion.to_lower() == emotion.emotion_name.to_lower():
		model.default_emotion = base.emotion_name

static func _has_emotion_entry_named(model: ModelProfile, entry_name: String) -> bool:
	for branch in model.branches:
		for entry in branch.emotion_entries:
			if entry.state_name.to_lower() == entry_name.to_lower():
				return true
	return false
