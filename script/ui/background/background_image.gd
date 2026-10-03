extends Button

@export_category("UI References")
@export var file_dialog: FileDialog

func _ready() -> void:
	file_dialog.file_selected.connect(_on_file_selected)
	NodeUtil.attach_locale(self, _on_locale_change)
	file_dialog.title = tr(&"OPEN_FILE")

func _on_locale_change() -> void:
	file_dialog.title = tr(&"OPEN_FILE")

func _on_pressed() -> void:
	file_dialog.popup_centered_ratio(0.5)

func _on_file_selected(path: String) -> void:
	IoService.request_gpu_image(path, func(image: Image) -> void:
		if image == null or image.is_empty():
			return
		SignalBus.background_image_changed.emit(ImageUtil.create_gpu_texture(image))
	, self)
