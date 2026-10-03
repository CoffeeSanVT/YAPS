extends Button

func _on_pressed() -> void:
	LoadingOverlay.change_scene_to(&"LOADING_MENU", PathUtil.MENU_SCENE)
