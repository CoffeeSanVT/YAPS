class_name RenameUtil
extends RefCounted


enum LabelMode { NONE, CAPITALIZED, RAW }

var _renaming := false
var _rename_button: TextureButton

func _init(rename_button: TextureButton) -> void:
	_rename_button = rename_button

func attach(host: Node) -> void:
	SignalBus.rename_editing_started.connect(handle_editing_started)
	SignalBus.rename_editing_finished.connect(handle_editing_finished)
	host.tree_exited.connect(_on_host_tree_exited)

func _on_host_tree_exited() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"rename_editing_started", handle_editing_started)
	NodeUtil.safe_disconnect(SignalBus, &"rename_editing_finished", handle_editing_finished)
	if _renaming:
		_end()

func _start(label: Label, current_text: String, on_apply: Callable, is_taken: Callable = Callable()) -> void:
	if _renaming:
		return
	_renaming = true
	ApplicationState.set_state(ApplicationState.AppState.EDITING)
	SignalBus.rename_editing_started.emit()
	RenameUtil.start_rename(label, current_text, _on_confirmed.bind(on_apply, is_taken), _on_canceled)

func rename_property(label: Label, target: Object, property: StringName, is_taken: Callable = Callable(), label_mode: LabelMode = LabelMode.CAPITALIZED, on_confirmed: Callable = Callable()) -> void:
	var current := String(target.get(property)) if target != null else ""
	_start(label, current, func(new_name: String) -> void:
		if target != null and new_name.to_lower() != current.to_lower():
			target.set(property, new_name)
			if label != null:
				match label_mode:
					LabelMode.CAPITALIZED:
						label.text = new_name.capitalize()
					LabelMode.RAW:
						label.text = new_name
			ModelLoader.save_model()
		if on_confirmed.is_valid():
			on_confirmed.call(new_name)
	, is_taken)

func _on_confirmed(new_name: String, on_apply: Callable, is_taken: Callable) -> void:
	if not new_name.is_empty():
		if is_taken.is_valid():
			new_name = NameUtil.unique_name(new_name, is_taken)
		on_apply.call(new_name)
	_end()

func _on_canceled() -> void:
	_end()

func _restore_editing_ui() -> void:
	_renaming = false
	if is_instance_valid(_rename_button):
		_rename_button.disabled = false

func _end() -> void:
	_restore_editing_ui()
	ApplicationState.set_state(ApplicationState.AppState.NORMAL)
	SignalBus.rename_editing_finished.emit()

func handle_editing_started() -> void:
	if _renaming:
		return
	if _rename_button != null:
		_rename_button.disabled = true

func handle_editing_finished() -> void:
	_restore_editing_ui()



static func start_rename(label: Label, current_text: String, on_confirmed: Callable, on_canceled: Callable = Callable()) -> LineEdit:
	var line_edit := LineEdit.new()
	line_edit.text = current_text
	line_edit.custom_minimum_size = Vector2(label.size.x, 0)
	line_edit.size_flags_horizontal = label.size_flags_horizontal
	line_edit.size_flags_vertical = label.size_flags_vertical
	line_edit.custom_maximum_size = label.custom_maximum_size
	line_edit.set_meta("label_ref", label)
	line_edit.text_submitted.connect(_on_submitted.bind(line_edit, on_confirmed))
	line_edit.focus_exited.connect(_on_focus_exited.bind(line_edit, on_canceled))
	line_edit.gui_input.connect(_on_gui_input.bind(line_edit, on_canceled))
	label.get_parent().add_child(line_edit)
	label.get_parent().move_child(line_edit, label.get_index())
	label.visible = false
	line_edit.grab_focus()
	return line_edit

static func _finish_rename(line_edit: LineEdit) -> void:
	if not is_instance_valid(line_edit):
		return
	var label: Label = line_edit.get_meta("label_ref")
	if is_instance_valid(label):
		label.visible = true
	line_edit.queue_free()

static func _on_submitted(new_name: String, line_edit: LineEdit, on_confirmed: Callable) -> void:
	if not is_instance_valid(line_edit) or line_edit.has_meta("finished"):
		return
	line_edit.set_meta("finished", true)
	_finish_rename(line_edit)
	if on_confirmed.is_valid():
		on_confirmed.call(new_name.strip_edges())

static func _on_focus_exited(line_edit: LineEdit, on_canceled: Callable) -> void:
	_cancel_rename(line_edit, on_canceled)

static func _on_gui_input(event: InputEvent, line_edit: LineEdit, on_canceled: Callable) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_rename(line_edit, on_canceled)

static func _cancel_rename(line_edit: LineEdit, on_canceled: Callable) -> void:
	if not is_instance_valid(line_edit) or line_edit.has_meta("finished"):
		return
	line_edit.set_meta("finished", true)
	_finish_rename(line_edit)
	if on_canceled.is_valid():
		on_canceled.call()

