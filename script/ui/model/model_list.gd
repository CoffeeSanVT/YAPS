extends Node

const TAG := "[ModelList] "
const MAIN_SCENE := PathUtil.MAIN_SCENE
const PREWARM_ATTEMPTS := 50
const PREWARM_POLL_INTERVAL := 0.2

@export_category("UI References")
@export var list_ui: ItemList
@export var delete_panel: Control
@export var delete_message_label: Label
@export var rename_panel: Control
@export var rename_line: LineEdit
var models: Array[ModelProfile] = []

var _context_menu: PopupMenu
var _selected_index: int = -1
var _cached_main_scene: Node
var _switching := false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		if delete_panel.visible:
			delete_panel.hide()
		elif rename_panel.visible:
			rename_panel.hide()

func _ready() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)

	ModelLoader.list_found_models(func(found: Array) -> void:
		models = found
		_refresh_list()
	)
	ResourceLoader.load_threaded_request(MAIN_SCENE)
	_prewarm_main_scene.call_deferred()

func _prewarm_main_scene() -> void:
	for _attempt in PREWARM_ATTEMPTS:
		var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_cached_main_scene = (ResourceLoader.load_threaded_get(MAIN_SCENE) as PackedScene).instantiate()
			return
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		await get_tree().create_timer(PREWARM_POLL_INTERVAL).timeout

func _swap_to_cached_main_scene() -> void:
	var main := _cached_main_scene
	_cached_main_scene = null
	var tree := get_tree()
	tree.root.add_child(main)
	tree.current_scene.queue_free()
	tree.current_scene = main

func _exit_tree() -> void:
	if is_instance_valid(_context_menu):
		_context_menu.queue_free()

func _refresh_list() -> void:
	list_ui.clear()
	for model in models:
		list_ui.add_item(model.model_name)

func _on_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index == MOUSE_BUTTON_RIGHT:
		_selected_index = index
		_context_menu.clear()
		_context_menu.add_item(tr(&"RENAME"), 0)
		_context_menu.add_item(tr(&"DELETE"), 1)
		_context_menu.position = list_ui.get_global_mouse_position()
		_context_menu.popup()
		return
	if _switching:
		return
	_switching = true
	await LoadingOverlay.show_loading(&"LOADING_LOADING")
	ModelLoader.model_loaded = models[index]
	if _cached_main_scene != null:
		_swap_to_cached_main_scene()
	else:
		get_tree().change_scene_to_file(MAIN_SCENE)

func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		0:
			_start_rename()
		1:
			_delete_model()

func _start_rename() -> void:
	if _selected_index < 0 or _selected_index >= models.size():
		return
	rename_line.text = models[_selected_index].model_name
	rename_panel.show()
	rename_line.grab_focus()
	rename_line.select_all()

func _apply_rename() -> void:
	if _selected_index < 0 or _selected_index >= models.size():
		return
	var new_name := rename_line.text.strip_edges()
	rename_panel.hide()
	if new_name.is_empty() or new_name == models[_selected_index].model_name:
		return
	var old_path := PathUtil.get_model_folder_path(models[_selected_index].model_name)
	var new_path := PathUtil.get_model_folder_path(new_name)
	if DirAccess.dir_exists_absolute(new_path):
		push_error(TAG + "Model folder already exists: " + new_path)
		return
	var rename_err := DirAccess.rename_absolute(old_path, new_path)
	if rename_err != OK:
		push_error(TAG + "Failed to rename model folder '%s' -> '%s': %s" % [old_path, new_path, error_string(rename_err)])
		return
	models[_selected_index].model_name = new_name
	models[_selected_index].resource_path = new_path.path_join(ModelProfileStore.MODEL_FILE_NAME)
	ModelLoader.save_model_profile(models[_selected_index])
	_refresh_list()

func _delete_model() -> void:
	if _selected_index < 0 or _selected_index >= models.size():
		return
	delete_message_label.text = String(tr(&"DELETE_MODEL_MESSAGE")) % models[_selected_index].model_name
	delete_panel.show()

func _on_delete_confirmed() -> void:
	delete_panel.hide()
	_perform_delete_model(_selected_index)

func _on_delete_canceled() -> void:
	delete_panel.hide()

func _perform_delete_model(index: int) -> void:
	if index < 0 or index >= models.size():
		return
	var model := models[index]
	var folder := PathUtil.get_model_folder_path(model.model_name)
	if not PathUtil.delete_dir_recursive(folder):
		push_error(TAG + "Model folder not fully removed: " + folder)
	models.remove_at(index)
	_selected_index = -1
	_refresh_list()

