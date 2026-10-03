extends Node

const TAG := "[Screenshot] "
const SCREENSHOT_DIR_NAME := "screenshots"

var _capturing := false

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"take_screenshot"):
		return
	var state := ApplicationState.get_state()
	if state == ApplicationState.AppState.LOADING or state == ApplicationState.AppState.RE_MAPPING_INPUT:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	_capture()

func _capture() -> void:
	if _capturing:
		return
	_capturing = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error(TAG + "failed to capture viewport image")
		_capturing = false
		return
	var folder := _screenshot_folder()
	var err := PathUtil.ensure_dir(folder)
	if err != OK:
		push_error(TAG + "could not create folder '%s': %s" % [folder, error_string(err)])
		_capturing = false
		return
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := folder.path_join("yaps_%s.png" % timestamp)
	err = image.save_png(path)
	if err != OK:
		push_error(TAG + "failed to save '%s': %s" % [path, error_string(err)])
	else:
		print(TAG + "saved " + path)
	_capturing = false

func _screenshot_folder() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").path_join(SCREENSHOT_DIR_NAME)
	return PathUtil.get_config_folder_path().path_join(SCREENSHOT_DIR_NAME)
