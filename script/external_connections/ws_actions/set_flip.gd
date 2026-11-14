extends WebSocketAction

const COMMAND := &"set_flip"

var _loader: ModelLoader

func _init(loader: ModelLoader) -> void:
	super(COMMAND)
	_loader = loader

func exec(arg: String) -> String:
	var model := _loader.model_loaded
	if model == null:
		return JSON.stringify({"status": "error", "message": "no model loaded"})
	var value: Variant
	var normalized := arg.strip_edges().to_lower()
	match normalized:
		"":
			value = not model.flip_x
		"flip":
			value = true
		_:
			value = ActionArguments.parse_bool(normalized)
			if typeof(value) != TYPE_BOOL:
				return JSON.stringify({"status": "error", "message": "invalid flip value: %s" % arg})
	model.flip_x = value
	ModelLoader.save_model()
	SignalBus.model_flip_changed.emit(value)
	return JSON.stringify({"status": "ok", "flip": value})
