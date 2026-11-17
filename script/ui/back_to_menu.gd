extends Button

func _on_pressed() -> void:
	disabled = true
	await ModelLoader.wait_for_model_saves()
	LoadingOverlay.change_scene_to(&"LOADING_MENU", PathUtil.MENU_SCENE)
