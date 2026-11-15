extends PanelContainer

@export_category("UI References")
@export var name_input: LineEdit
@export var confirm_button: Button
@export var close_button: TextureButton
@export var title_label: Label

signal name_confirmed(name: String)

var _name_validator: Callable

func configure(title_key: StringName, placeholder_key: StringName, name_validator: Callable, confirm_key: StringName = &"CREATE", initial_name: String = "") -> void:
	title_label.set_meta(&"localization_key", title_key)
	confirm_button.set_meta(&"localization_key", confirm_key)
	name_input.placeholder_text = tr(placeholder_key)
	name_input.text = initial_name
	_name_validator = name_validator

func _ready() -> void:
	name_input.text_submitted.connect(_on_text_submitted)
	confirm_button.pressed.connect(_on_confirm)
	close_button.pressed.connect(queue_free)
	if _name_validator.is_valid():
		name_input.text_changed.connect(_update_confirmation)
		_update_confirmation(name_input.text)

func _update_confirmation(value: String) -> void:
	confirm_button.disabled = not _name_validator.call(value.strip_edges())

func _on_text_submitted(_text: String) -> void:
	_on_confirm()

func _on_confirm() -> void:
	if confirm_button.disabled:
		return
	var emotion_name := name_input.text.strip_edges()
	if emotion_name.is_empty():
		emotion_name = &"Emotion"
	name_confirmed.emit(emotion_name)
	queue_free()
