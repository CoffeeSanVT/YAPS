extends Node

const TAG := "[Menu] "
const MAIN_SCENE := PathUtil.MAIN_SCENE

@export_category("UI References")
@export var input_container: Panel

var model_name: String
var input_field_showing: bool

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and input_field_showing:
		_hide_input()

func open_native_file_picker() -> void:
	if model_name.is_empty():
		push_warning(TAG + "Attempted to open file picker with empty model name.")
		return
	FileDialogHelper.open_files(self, _on_files_selected, PackedStringArray())

func _on_create_static_png() -> void:
	input_container.show()
	input_field_showing = true

func _on_files_selected(paths: PackedStringArray) -> void:
	LoadingOverlay.show_loading(&"LOADING_CREATING")
	ModelLoader.create_and_save_static_model(model_name, paths, func(model: ModelProfile) -> void:
		if model == null:
			LoadingOverlay.hide_loading()
			push_error(TAG + "Failed to create static model '%s'." % [model_name])
			return
		ModelLoader.model_loaded = model
		LoadingOverlay.set_status(&"LOADING_LOADING")
		await get_tree().process_frame
		get_tree().change_scene_to_file(MAIN_SCENE)
	, {}, func(progress: StringName) -> void:
		LoadingOverlay.set_status(progress)
	, self)

func _on_model_name_input_text_submitted(_new_text: String) -> void:
	open_native_file_picker()

func _on_create_model_button_up() -> void:
	open_native_file_picker()

func _on_model_name_input_text_changed(new_text: String) -> void:
	model_name = new_text

func _on_close_button_pressed() -> void:
	_hide_input()

func _hide_input() -> void:
	input_container.hide()
	input_field_showing = false
