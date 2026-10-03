extends PanelContainer

@export_category("UI References")
@export var name_input: LineEdit
@export var confirm_button: Button
@export var close_button: TextureButton

signal name_confirmed(name: String)

func _ready() -> void:
	name_input.text_submitted.connect(_on_text_submitted)
	confirm_button.pressed.connect(_on_confirm)
	close_button.pressed.connect(queue_free)

func _on_text_submitted(_text: String) -> void:
	_on_confirm()

func _on_confirm() -> void:
	var emotion_name := name_input.text.strip_edges()
	if emotion_name.is_empty():
		emotion_name = &"Emotion"
	name_confirmed.emit(emotion_name)
	queue_free()
