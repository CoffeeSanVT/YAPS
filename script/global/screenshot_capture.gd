extends Node

const TAG := "[Screenshot] "
const ENABLE_ARGUMENT := "--doc-screenshot"
const SCREENSHOT_DIR_NAME := "screenshots"

var _capturing := false

func _ready() -> void:
	set_process_input(ENABLE_ARGUMENT in OS.get_cmdline_args() or ENABLE_ARGUMENT in OS.get_cmdline_user_args())

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"take_screenshot", true, true):
		return
	get_viewport().set_input_as_handled()
	if not event.is_echo():
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
	var suffix := 2
	while FileAccess.file_exists(path):
		path = folder.path_join("yaps_%s_%d.png" % [timestamp, suffix])
		suffix += 1
	err = image.save_png(path)
	if err != OK:
		push_error(TAG + "failed to save '%s': %s" % [path, error_string(err)])
	else:
		print(TAG + "saved " + path)
	_capturing = false

func _screenshot_folder() -> String:
	return PathUtil.get_config_folder_path().path_join(SCREENSHOT_DIR_NAME)
