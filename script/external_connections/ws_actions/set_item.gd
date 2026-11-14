extends WebSocketAction

const COMMAND := &"set_item"

var _loader: ModelLoader

func _init(loader: ModelLoader) -> void:
	super(COMMAND)
	_loader = loader

func exec(arg: String) -> String:
	var model := _loader.model_loaded
	if model == null:
		return JSON.stringify({"status": "error", "message": "no model loaded"})
	var separator := arg.rfind(":")
	var enabled: Variant = ActionArguments.parse_bool(arg.substr(separator + 1)) if separator >= 0 else null
	var has_enabled := typeof(enabled) == TYPE_BOOL
	var item_name := arg.left(separator) if has_enabled else arg
	var item := ActionArguments.find_named(model.items, &"state_name", item_name) as Item
	if item == null:
		return JSON.stringify({"status": "error", "message": "item not found: %s" % item_name})
	item.set_enabled(enabled if has_enabled else not item.enabled)
	return JSON.stringify({"status": "ok", "item": item_name, "enabled": item.enabled})
