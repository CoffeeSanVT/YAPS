extends PanelContainer

signal completed(assignments: Dictionary)
signal canceled

const NAME_DIALOG := preload("uid://twgitjdha3g2")
const CONTEXT_BRANCHES := [ModelState.TALKING, ModelState.SILENCE]
const MIN_RECOMMENDED_IMAGE_SIDE := 720
const MAX_RECOMMENDED_IMAGE_SIDE := 2048
const MAX_RECOMMENDED_FRAMES := 30
const TOAST_PANEL := preload("res://script/ui/utils/toast_panel.gd")

enum ExpressionAction { RENAME, DELETE }

@export_category("UI References")
@export var expressions: Tree
@export var gallery: ItemList
@export var instruction: Label
@export var create_button: Button
@export var cancel_button: Button
@export var complete_button: Button
@export var image_menu: PopupMenu
@export var expression_branches: PopupMenu
@export var expression_menu: PopupMenu
@export var optimization_warning: TextureRect
@export var toast_panel: TOAST_PANEL

var _paths: PackedStringArray
var _assignments: Dictionary = {}
var _expressions_by_name: Dictionary[String, TreeItem] = {}
var _expression_root: TreeItem
var _name_dialog: Control
var _name_overlay := ModalOverlay.new()
var _context_image := -1
var _context_expression: TreeItem

func configure(paths: PackedStringArray) -> void:
	_paths = paths

func _ready() -> void:
	_expression_root = expressions.create_item()
	var silence := _add_branch(_expression_root, "", ModelState.SILENCE)
	_add_branch(_expression_root, "", ModelState.TALKING)
	for path in _paths:
		var emotion: String = _inferred_assignment(path).get("emotion", "")
		if not emotion.is_empty() and not _expressions_by_name.has(emotion.to_lower()):
			_add_expression(emotion)
	gallery.call(&"populate", _paths, _is_preview_blocked)
	expressions.item_selected.connect(_refresh_gallery)
	expressions.gui_input.connect(_open_expression_menu)
	expression_menu.add_item("RENAME", ExpressionAction.RENAME)
	expression_menu.add_item("DELETE", ExpressionAction.DELETE)
	expression_menu.id_pressed.connect(_on_expression_action)
	gallery.multi_selected.connect(_assign_image)
	gallery.item_clicked.connect(_open_image_menu)
	for index in CONTEXT_BRANCHES.size():
		expression_branches.add_item(CONTEXT_BRANCHES[index].to_upper(), index)
	image_menu.add_submenu_node_item("MODEL_CREATION_ADD", expression_branches)
	expression_branches.id_pressed.connect(_create_expression_from_image)
	create_button.pressed.connect(_open_name_dialog)
	cancel_button.pressed.connect(_cancel)
	complete_button.pressed.connect(_complete)
	silence.select(0)
	_refresh_gallery()
	expressions.grab_focus()
	IoService.run_io(_inspect_images.bind(_paths), _show_optimization_warning, self)

static func _inspect_images(paths: PackedStringArray) -> Vector2i:
	var warnings := Vector2i.ZERO
	for path in paths:
		var source := PathUtil.get_real_path(path)
		var image_size := Vector2i.ZERO
		if ImageUtil.is_animated_file(source):
			var animation := AnimatedImageRuntime.InspectAnimation(source, MAX_RECOMMENDED_FRAMES + 1)
			image_size = Vector2i(animation.x, animation.y)
			if animation.z > MAX_RECOMMENDED_FRAMES:
				warnings.y += 1
		else:
			var image := ImageUtil.load_image(path)
			if image != null:
				image_size = image.get_size()
		if image_size.x <= 0 or image_size.y <= 0:
			continue
		if (mini(image_size.x, image_size.y) < MIN_RECOMMENDED_IMAGE_SIDE
			or maxi(image_size.x, image_size.y) > MAX_RECOMMENDED_IMAGE_SIDE
			or image_size.x % 2 != 0 or image_size.y % 2 != 0):
			warnings.x += 1
	return warnings

func _show_optimization_warning(warnings: Vector2i) -> void:
	if warnings == Vector2i.ZERO or not is_visible_in_tree() or is_queued_for_deletion():
		return
	var details := PackedStringArray()
	if warnings.x > 0:
		details.append(tr("MODEL_CREATION_OPTIMIZATION_SIZE") % warnings.x)
	if warnings.y > 0:
		details.append(tr("MODEL_CREATION_OPTIMIZATION_FRAMES") % warnings.y)
	var message := "\n".join(details)
	optimization_warning.tooltip_text = message
	optimization_warning.show()
	toast_panel.show_toast(message, TOAST_PANEL.Kind.WARNING)

func _has_open_menu() -> bool:
	return image_menu.visible or expression_menu.visible

func _is_preview_blocked() -> bool:
	return _has_open_menu() or is_instance_valid(_name_dialog)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not _has_open_menu():
		get_viewport().set_input_as_handled()
		if is_instance_valid(_name_dialog):
			_name_dialog.queue_free()
		else:
			_cancel()

func _exit_tree() -> void:
	_name_overlay.dispose()

func _active_assignment() -> Dictionary:
	var selected := expressions.get_selected()
	return selected.get_metadata(0) if selected != null else {}

func _assign_image(index: int, selected: bool) -> void:
	var assignment := _active_assignment()
	if assignment.is_empty() or assignment.branch == "":
		_refresh_gallery()
		return
	for path in _paths:
		if not _assignments.has(path) and _inferred_assignment(path) == assignment:
			_assignments[path] = assignment
	var path := _paths[index]
	_assignments.erase(path)
	_assignments[path] = assignment if selected else {}
	_refresh_gallery()

func _refresh_gallery() -> void:
	var active := _active_assignment()
	if active.is_empty():
		return
	instruction.text = tr("MODEL_CREATION_SELECT_BRANCH" if active.branch == "" else "MODEL_CREATION_ASSIGN")
	var has_images := false
	for index in _paths.size():
		var path := _paths[index]
		var assignment := _image_assignment(path)
		has_images = has_images or not assignment.is_empty()
		var highlighted: bool = not assignment.is_empty() and assignment.emotion == active.emotion
		if highlighted:
			highlighted = active.branch == "" or assignment.branch == active.branch
		if highlighted != gallery.is_selected(index):
			if highlighted:
				gallery.select(index, false)
			else:
				gallery.deselect(index)
	complete_button.disabled = not has_images

func _inferred_assignment(path: String) -> Dictionary:
	if NameUtil.is_frame_file_name(path.get_file()):
		return {}
	return _named_assignment(path.get_file().get_basename())

func _named_assignment(base_name: String) -> Dictionary:
	if not NameUtil.has_explicit_branch(base_name):
		return {}
	var branch := ModelState.TALKING if base_name.to_lower().ends_with("talking") else ModelState.SILENCE
	if NameUtil.is_neutral_entry_name(base_name):
		return { "emotion": "", "branch": branch }
	var emotion := NameUtil.strip_emotion_suffix(base_name)
	var expression: TreeItem = _expressions_by_name.get(emotion.to_lower())
	return { "emotion": expression.get_text(0) if expression != null else emotion, "branch": branch }

func _automatic_frame_assignment(path: String) -> Dictionary:
	var file := path.get_file()
	if not NameUtil.is_frame_file_name(file):
		return {}
	return _named_assignment(NameUtil.strip_frame_suffix(file.get_basename()))

func _image_assignment(path: String) -> Dictionary:
	return _assignments.get(path, _inferred_assignment(path))

func _add_expression(value: String) -> TreeItem:
	var expression := expressions.create_item(_expression_root)
	_expressions_by_name[value.to_lower()] = expression
	expression.set_text(0, value)
	expression.set_metadata(0, { "emotion": value, "branch": "" })
	_add_branch(expression, value, ModelState.SILENCE)
	_add_branch(expression, value, ModelState.TALKING)
	return expression

func _add_branch(parent: TreeItem, emotion: String, branch: StringName) -> TreeItem:
	var item := expressions.create_item(parent)
	item.set_text(0, tr(branch.to_upper()))
	item.set_metadata(0, { "emotion": emotion, "branch": branch })
	return item

func _open_image_menu(index: int, at_position: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_RIGHT or index != gallery.get_item_at_position(at_position, true):
		return
	_context_image = index
	_popup_at_mouse(image_menu)

func _popup_at_mouse(menu: PopupMenu) -> void:
	var mouse_position := Vector2i(get_viewport().get_mouse_position())
	if not get_viewport().gui_embed_subwindows:
		mouse_position = DisplayServer.mouse_get_position()
	menu.popup(Rect2i(mouse_position, Vector2i.ZERO))

func _create_expression_from_image(branch_index: int) -> void:
	image_menu.hide()
	_open_name_dialog(_paths[_context_image], CONTEXT_BRANCHES[branch_index])

func _open_name_dialog(image_path: String = "", branch: StringName = &"") -> void:
	_show_name_dialog(&"MODEL_CREATION_ADD", &"CREATE", "", _is_valid_expression_name, _create_expression.bind(image_path, branch))

func _show_name_dialog(title_key: StringName, confirm_key: StringName, initial_name: String, validator: Callable, on_confirmed: Callable) -> void:
	if is_instance_valid(_name_dialog):
		return
	var dialog := NAME_DIALOG.instantiate()
	dialog.configure(title_key, &"MODEL_CREATION_NAME", validator, confirm_key, initial_name)
	dialog.name_confirmed.connect(on_confirmed)
	dialog.tree_exited.connect(func() -> void:
		if is_inside_tree() and not is_queued_for_deletion():
			expressions.grab_focus()
	)
	_name_dialog = dialog
	_name_overlay.show_modal(self, dialog, Vector2i(320, 170))
	dialog.name_input.grab_focus()
	dialog.name_input.select_all()

func _is_valid_expression_name(value: String) -> bool:
	return not value.is_empty() and not NameUtil.is_neutral_entry_name(value) and not _expressions_by_name.has(value.to_lower())

func _create_expression(value: String, image_path: String, branch: StringName) -> void:
	var expression := _add_expression(value)
	var selected := expression
	if not image_path.is_empty():
		selected = expression.get_child(0 if branch == ModelState.SILENCE else 1)
		_assignments.erase(image_path)
		_assignments[image_path] = selected.get_metadata(0)
	selected.select(0)
	expressions.scroll_to_item(selected)
	_refresh_gallery()

func _open_expression_menu(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		return
	var item := expressions.get_item_at_position(event.position)
	if item == null or item.get_parent() != _expression_root:
		return
	var assignment: Dictionary = item.get_metadata(0)
	if assignment.emotion.is_empty():
		return
	_context_expression = item
	item.select(0)
	_refresh_gallery()
	expressions.accept_event()
	_popup_at_mouse(expression_menu)

func _on_expression_action(action: int) -> void:
	var item := _context_expression
	_context_expression = null
	expression_menu.hide()
	var old_name := item.get_text(0)
	match action:
		ExpressionAction.RENAME:
			var validator := func(value: String) -> bool:
				return value.nocasecmp_to(old_name) == 0 or _is_valid_expression_name(value)
			_show_name_dialog(&"MODEL_CREATION_RENAME", &"RENAME", old_name, validator, _rename_expression.bind(item))
		ExpressionAction.DELETE:
			_delete_expression(item)

func _rename_expression(new_name: String, item: TreeItem) -> void:
	var old_name := item.get_text(0)
	if new_name == old_name:
		return
	_reassign_expression_images(old_name, new_name)
	_expressions_by_name.erase(old_name.to_lower())
	_expressions_by_name[new_name.to_lower()] = item
	item.set_text(0, new_name)
	item.set_metadata(0, { "emotion": new_name, "branch": "" })
	for branch in item.get_children():
		var assignment: Dictionary = branch.get_metadata(0)
		branch.set_metadata(0, { "emotion": new_name, "branch": assignment.branch })
	_refresh_gallery()

func _delete_expression(item: TreeItem) -> void:
	var expression := item.get_text(0)
	_reassign_expression_images(expression, "")
	_expressions_by_name.erase(expression.to_lower())
	var next := item.get_next()
	if next == null:
		next = item.get_prev()
	item.free()
	next.select(0)
	_refresh_gallery()

func _reassign_expression_images(old_name: String, new_name: String) -> void:
	var matching_branches := {}
	for path in _paths:
		var assignment := _image_assignment(path)
		if not assignment.is_empty() and assignment.emotion == old_name:
			matching_branches[assignment.branch] = true
			_assignments[path] = {} if new_name.is_empty() else { "emotion": new_name, "branch": assignment.branch }
	for path in _paths:
		if _assignments.has(path):
			continue
		var frame := _automatic_frame_assignment(path)
		if not frame.is_empty() and frame.emotion == old_name and matching_branches.has(frame.branch):
			_assignments[path] = {} if new_name.is_empty() else { "emotion": new_name, "branch": frame.branch }

func _cancel() -> void:
	canceled.emit()
	queue_free()

func _complete() -> void:
	var assignments := _assignments.duplicate()
	var active_states: Array[Dictionary] = []
	for path in _paths:
		var assignment := _image_assignment(path)
		if not assignment.is_empty() and not active_states.has(assignment):
			active_states.append(assignment)
	for path in _paths:
		if not assignments.has(path) and _inferred_assignment(path).is_empty() and not active_states.has(_automatic_frame_assignment(path)):
			assignments[path] = {}
	hide()
	completed.emit(assignments)
	queue_free()
