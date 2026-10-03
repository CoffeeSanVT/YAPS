class_name PathUtil

const TAG := "[PathUtil] "
const MENU_SCENE := "uid://dugepc7rcnkkn"
const MAIN_SCENE := "uid://diojcxynpg5x1"
const ITEMS_SUBFOLDER := "assets/items"
const EXPRESSIONS_SUBFOLDER := "assets/expressions"
const FRAMES_SUBFOLDER := "assets/frames"

static func get_executable_dir() -> String:
	return OS.get_executable_path().get_base_dir()

static func get_config_folder_path() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://")
	return get_executable_dir()

static func get_models_folder_path() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://model")
	return get_executable_dir().path_join("model")

static func ensure_dir(dir_path: String) -> Error:
	if DirAccess.dir_exists_absolute(dir_path):
		return OK
	return DirAccess.make_dir_recursive_absolute(dir_path)

static func ensure_model_folder() -> void:
	var model_folder_path := get_models_folder_path()
	var err := ensure_dir(model_folder_path)
	if err != OK:
		push_warning(TAG + "could not create model folder at " + model_folder_path + " (" + error_string(err) + ")")

static func get_model_folder_path(model_name: String) -> String:
	return get_models_folder_path().path_join(model_name)

static func get_real_path(asset_path: String) -> String:
	if not asset_path.begins_with("res://") and asset_path.is_absolute_path():
		return asset_path
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path(asset_path)
	return get_executable_dir().path_join(asset_path.replace("res://", ""))

static func expression_asset_path(model_name: String, file_name: String) -> String:
	return "res://model/%s/%s/%s" % [model_name, EXPRESSIONS_SUBFOLDER, file_name]

static func expressions_folder_path(model_name: String) -> String:
	return get_model_folder_path(model_name).path_join(EXPRESSIONS_SUBFOLDER)

static func frames_internal_folder_path(expression_name: String) -> String:
	return FRAMES_SUBFOLDER.path_join(expression_name)

static func frame_asset_path(model_name: String, expression_name: String, file_name: String) -> String:
	return frames_res_path(model_name, expression_name).path_join(file_name)

static func frames_res_path(model_name: String, expression_name: String) -> String:
	return "res://model/%s/%s/%s" % [model_name, FRAMES_SUBFOLDER, expression_name]

static func frames_folder_path(model_name: String, expression_name: String) -> String:
	return get_model_folder_path(model_name).path_join(FRAMES_SUBFOLDER).path_join(expression_name)

static func item_asset_path(model_name: String, file_name: String) -> String:
	return "res://model/%s/%s/%s" % [model_name, ITEMS_SUBFOLDER, file_name]

static func delete_dir_recursive(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		push_error(TAG + "Cannot open folder for deletion '%s': %s" % [path, error_string(DirAccess.get_open_error())])
		return false
	var removed := true
	dir.list_dir_begin()
	while true:
		var file := dir.get_next()
		if file == "":
			break
		if file.begins_with("."):
			continue
		var full_path := path.path_join(file)
		if dir.current_is_dir():
			removed = delete_dir_recursive(full_path) and removed
		else:
			var file_err := dir.remove(full_path)
			if file_err != OK:
				push_warning(TAG + "Failed to remove file '%s': %s" % [full_path, error_string(file_err)])
				removed = false
	dir.list_dir_end()
	var dir_err := dir.remove(path)
	if dir_err != OK:
		push_warning(TAG + "Failed to remove directory '%s': %s" % [path, error_string(dir_err)])
		removed = false
	return removed
