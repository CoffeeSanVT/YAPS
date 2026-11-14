extends WebSocketAction

const COMMAND := &"get_presets"

var _loader: ModelLoader

func _init(loader: ModelLoader) -> void:
	super(COMMAND)
	_loader = loader

func exec(_arg: String) -> String:
	var model := _loader.model_loaded
	if model == null:
		return JSON.stringify({"status": "error", "message": "no model loaded"})
	return JSON.stringify({"status": "ok", "presets": ActionArguments.name_list(model.transform_presets, &"preset_name")})
