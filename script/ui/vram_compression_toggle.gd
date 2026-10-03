extends CheckButton

func _ready() -> void:
	var model := ModelLoader.model_loaded
	if model == null:
		disabled = true
		return
	set_pressed_no_signal(model.vram_texture_compression)

func _on_toggled(value: bool) -> void:
	var model := ModelLoader.model_loaded
	if model == null:
		return
	model.vram_texture_compression = value
	ModelLoader.save_model()
	ModelLoader.reload_textures()