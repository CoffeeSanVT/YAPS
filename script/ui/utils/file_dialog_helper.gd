class_name FileDialogHelper

static var IMAGE_FILTERS := PackedStringArray(["*.png, *.apng, *.gif, *.webp, *.webm ; Image Files"])

static func open_files(parent: Node, on_selected: Callable, filters: PackedStringArray = IMAGE_FILTERS, title: String = "", centered_size: Vector2i = Vector2i.ZERO) -> void:
	_open(parent, FileDialog.FILE_MODE_OPEN_FILES, on_selected, filters, title, centered_size)

static func open_file(parent: Node, on_selected: Callable, filters: PackedStringArray = IMAGE_FILTERS, title: String = "", centered_size: Vector2i = Vector2i.ZERO) -> void:
	_open(parent, FileDialog.FILE_MODE_OPEN_FILE, on_selected, filters, title, centered_size)

static func _open(parent: Node, mode: FileDialog.FileMode, on_selected: Callable, filters: PackedStringArray, title: String, centered_size: Vector2i) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	if not filters.is_empty():
		dialog.filters = filters
	if not title.is_empty():
		dialog.title = title
	dialog.files_selected.connect(on_selected)
	dialog.file_selected.connect(on_selected)
	dialog.canceled.connect(dialog.queue_free)
	parent.add_child(dialog)
	if centered_size != Vector2i.ZERO:
		dialog.popup_centered(centered_size)
	else:
		dialog.popup()
	dialog.files_selected.connect(func(_p: Array) -> void: dialog.queue_free(), CONNECT_ONE_SHOT)
	dialog.file_selected.connect(func(_p: String) -> void: dialog.queue_free(), CONNECT_ONE_SHOT)
