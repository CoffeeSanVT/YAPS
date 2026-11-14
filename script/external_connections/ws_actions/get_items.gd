extends WebSocketAction

const COMMAND := &"get_items"

var _loader: ModelLoader

func _init(loader: ModelLoader) -> void:
	super(COMMAND)
	_loader = loader

func exec(_arg: String) -> String:
	var model := _loader.model_loaded
	if model == null:
		return JSON.stringify({"status": "error", "message": "no model loaded"})
	var items_data: Array[Dictionary] = []
	for item in model.items:
		items_data.append({
			"name": item.state_name,
			"enabled": item.enabled
		})
	return JSON.stringify({"status": "ok", "items": items_data})
