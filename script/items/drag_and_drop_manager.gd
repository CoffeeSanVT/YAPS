class_name DragAndDropManager
extends Node

const TAG := "[DragAndDrop] "
const STATIC_IMAGE_EXTENSIONS := ["png", "jpg", "jpeg"]
const SELECT_ICON_SIZE := 24.0
const SELECT_MENU_MARGIN := 8.0
const DESELECT_DELAY := 3.0

@export_category("References")
@export var sub_viewport_container: SubViewportContainer
@export var spout_viewport: SubViewport
@export var model_container: Control

var _selected_item: Item
var _select_menu: PopupMenu
var _icon_cache := {}
var _deselect_timer: Timer
var _selected_was_dragging := false

func _ready() -> void:
	NodeUtil.connect_once(SignalBus, &"model_container_changed", _on_model_container_changed)
	get_window().files_dropped.connect(_on_files_dropped)
	_deselect_timer = NodeUtil.ensure_timer(self, _deselect_timer, _on_deselect_timeout, true)
	_deselect_timer.wait_time = DESELECT_DELAY
	call_deferred(&"_restore_items")

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"model_container_changed", _on_model_container_changed)
	DragSession.reset()
	if ModelLoader.model_loaded == null:
		return
	for item in ModelLoader.model_loaded.items:
		item.deactivate_triggers()

func _restore_items() -> void:
	if ModelLoader.model_loaded == null:
		LoadingOverlay.hide_loading()
		return
	for item in ModelLoader.model_loaded.items:
		item.instantiate_in_scene(_parent_for_item(item))
		item.activate_trigger()
		item.activate_twitch_event()
		item.update_auto_hide_timer()
	SignalBus.items_changed.emit()
	await ModelLoader.wait_for_texture_work()
	LoadingOverlay.hide_loading()

func get_model_parent() -> Control:
	return _get_image_parent()

func get_free_parent() -> Node:
	if is_instance_valid(spout_viewport):
		return spout_viewport
	return model_container

func _on_model_container_changed(container: Control) -> void:
	if not is_instance_valid(container):
		return
	model_container = container
	spout_viewport = container.get_parent() as SubViewport

func _parent_for_item(item: Item) -> Node:
	return _get_image_parent() if item.is_fixed_to_model else get_free_parent()

func _on_files_dropped(files: PackedStringArray) -> void:
	for file_path in files:
		_process_dropped_file(file_path)

func _process_dropped_file(file_path: String) -> void:
	if not _is_supported_image(file_path):
		push_warning(TAG + "Unsupported file type dropped and ignored: " + file_path)
		return
	if ImageUtil.is_animated_file(file_path):
		_process_animated_drop(file_path)
	else:
		_process_static_drop(file_path)

func _process_animated_drop(file_path: String) -> void:
	var animation := AnimatedImageRuntime.LoadFrames(file_path, ImageUtil.model_compress_enabled())
	if animation == null:
		_process_static_drop(file_path)
		return
	var texture: Texture2D = animation.Frames[0]
	var texture_rect := _create_dropped_item_rect(texture, file_path)
	var item: Item = texture_rect.item
	if item != null:
		item.set_animation_data(animation)
	var player := AnimatedImageRuntime.AttachPlayer(animation, texture_rect)
	if player != null and item != null:
		player.Loop = item.animation_loop
	SignalBus.items_changed.emit()

func _process_static_drop(file_path: String) -> void:
	IoService.request_gpu_image(file_path, func(image: Image) -> void:
		if image == null or image.is_empty():
			push_warning(TAG + "Failed to load dropped image: " + file_path)
			return
		var texture := ImageUtil.create_gpu_texture(image)
		_create_dropped_item_rect(texture, file_path)
		SignalBus.items_changed.emit()
	, self)

func _create_dropped_item_rect(texture: Texture2D, file_path: String) -> Draggable:
	var texture_rect := DragSession.create_for_item(texture, null)
	var ratio_pos := Vector2.ZERO
	var item := ModelLoader.add_dropped_item_to_model(file_path, ratio_pos, texture_rect.scale)
	texture_rect.item = item
	if item != null:
		item.instance = texture_rect
	else:
		push_warning(TAG + "add_dropped_item_to_model returned null for: " + file_path)
	_get_image_parent().add_child(texture_rect)
	if item != null:
		item.apply_z_index()
		item.apply_transform_to_instance()
	return texture_rect

func _input(event: InputEvent) -> void:
	if event.is_action("scale_item"):
		_handle_wheel(event as InputEventMouseButton)
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	_handle_select_click()

func _handle_wheel(mb: InputEventMouseButton) -> void:
	if mb == null or not mb.pressed:
		return
	var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
	var target := _get_draggable_at(_get_mouse_in_viewport())
	if target != null and target.is_dragging():
		target.scale_wheel(up)

func _handle_select_click() -> void:
	if not _pointer_over_canvas():
		push_warning(TAG + "right-click ignored: mouse is over UI panels")
		return
	_open_select_menu()

func _open_select_menu() -> void:
	var all: Array = ModelLoader.model_loaded.items if ModelLoader.model_loaded != null else []
	if all.is_empty():
		push_warning(TAG + "selection menu: model has no items")
		return
	var menu := _ensure_select_menu()
	menu.clear()
	if _selected_item != null:
		menu.add_item(tr(&"NONE"))
		menu.set_item_metadata(0, null)
	var hovered := _hit_draggable_at_mouse()
	for item: Item in all:
		var index := menu.get_item_count()
		menu.add_icon_item(_select_icon_for(item), String(item.state_name).capitalize())
		menu.set_item_metadata(index, item)
		if hovered != null and item.instance == hovered:
			menu.set_item_checked(index, true)
	menu.reset_size()
	var max_pos := Vector2(get_window().size) - Vector2(menu.size) - Vector2(SELECT_MENU_MARGIN, SELECT_MENU_MARGIN)
	var pos := get_viewport().get_mouse_position().clamp(Vector2.ZERO, max_pos.max(Vector2.ZERO))
	menu.position = pos
	get_viewport().set_input_as_handled()
	DragSession.select_menu_open = true
	menu.popup()

func _ensure_select_menu() -> PopupMenu:
	if is_instance_valid(_select_menu):
		return _select_menu
	_select_menu = PopupMenu.new()
	_select_menu.theme = load("uid://b2abxxvicwo1p")
	_select_menu.index_pressed.connect(_on_select_menu_index)
	_select_menu.popup_hide.connect(func() -> void: DragSession.select_menu_open = false)
	add_child(_select_menu)
	return _select_menu

func _on_select_menu_index(index: int) -> void:
	_select_item(_select_menu.get_item_metadata(index) as Item)

func _hit_draggable_at_mouse() -> Draggable:
	var pos := _get_mouse_in_viewport()
	var hit := _get_draggable_at(pos)
	if hit != null and not hit.is_opaque_at_viewport(pos):
		return null
	return hit

func _select_icon_for(item: Item) -> Texture2D:
	var source: Texture2D = item.instance.texture if is_instance_valid(item.instance) and item.instance.texture != null else null
	var cached: Array = _icon_cache.get(item.asset_path, [null, null])
	if cached[0] == source and cached[1] != null:
		return cached[1]
	if source == null:
		source = item.load_image()
	var icon: Texture2D = null
	if source != null:
		var image := source.get_image()
		if image != null:
			if image.is_compressed():
				image.decompress()
			var w := float(image.get_width())
			var h := float(image.get_height())
			if w > 0.0 and h > 0.0:
				var k := minf(1.0, SELECT_ICON_SIZE / maxf(w, h))
				image.resize(maxi(1, int(w * k)), maxi(1, int(h * k)), Image.INTERPOLATE_LANCZOS)
				icon = ImageTexture.create_from_image(image)
	_icon_cache[item.asset_path] = [source, icon]
	return icon

func _select_item(item: Item) -> void:
	_deselect_timer.stop()
	_selected_was_dragging = false
	if _selected_item == item:
		if item != null:
			SignalBus.item_selected.emit(item)
			_start_deselect_timer()
		return
	_set_selected_visual(_selected_item, false)
	_selected_item = item
	_set_selected_visual(_selected_item, true)
	SignalBus.item_selected.emit(item)
	_start_deselect_timer()

func _start_deselect_timer() -> void:
	if _selected_item == null or not is_instance_valid(_selected_item.instance):
		return
	if _selected_item.instance.is_dragging():
		return
	_deselect_timer.start()

func _process(_delta: float) -> void:
	_watch_selected_drag()

func _watch_selected_drag() -> void:
	if _selected_item == null or not is_instance_valid(_selected_item.instance):
		return
	if _selected_item.instance.is_dragging():
		_deselect_timer.stop()
		_selected_was_dragging = true
	elif _selected_was_dragging:
		_selected_was_dragging = false
		_deselect_timer.start()

func _on_deselect_timeout() -> void:
	_select_item(null)

func _set_selected_visual(item: Item, value: bool) -> void:
	if item == null or not is_instance_valid(item.instance):
		DragSession.selected_draggable = null
		if item != null and value:
			push_warning(TAG + "cannot select '%s': no instance (missing asset?)" % item.state_name)
		return
	if value and not item.enabled:
		item.set_enabled(true)
	var applied := item.instance.set_selected(value)
	if value and not applied:
		push_warning(TAG + "selection refused for '%s' (state=%d)" % [item.state_name, item.instance.state])
	DragSession.selected_draggable = item.instance if (value and applied) else null

func _pointer_over_canvas() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null:
		return true
	var current := hovered as Node
	while current != null:
		if current is CanvasLayer:
			return false
		current = current.get_parent()
	return true

func _get_draggable_at(pos: Vector2) -> Draggable:
	return DragSession.topmost_among(get_tree().get_nodes_in_group(DragSession.MODEL_ITEMS_GROUP), pos)

func _get_image_parent() -> Control:
	var model := model_container.find_child(&"model", true, false) as Control
	return model if model != null else model_container

func _is_supported_image(file_path: String) -> bool:
	var ext := file_path.get_extension().to_lower()
	return ext in STATIC_IMAGE_EXTENSIONS or ImageUtil.is_animated_file(file_path)

func _get_mouse_in_viewport() -> Vector2:
	if sub_viewport_container == null:
		push_warning(TAG + "sub_viewport_container is null; returning zero mouse position.")
		return Vector2.ZERO
	return DragSession.mouse_in_viewport(sub_viewport_container, spout_viewport)

