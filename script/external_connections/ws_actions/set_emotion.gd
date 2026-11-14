extends WebSocketAction

const COMMAND := &"set_emotion"

var _loader: ModelLoader
var _tree: SceneTree

func _init(loader: ModelLoader, tree: SceneTree) -> void:
	super(COMMAND)
	_loader = loader
	_tree = tree

func exec(arg: String) -> String:
	var separator := arg.rfind(":")
	var enabled: Variant = ActionArguments.parse_bool(arg.substr(separator + 1)) if separator >= 0 else null
	var has_enabled := typeof(enabled) == TYPE_BOOL
	var emotion_name := arg.left(separator) if has_enabled else arg
	var disable := has_enabled and not bool(enabled)
	var last_error := ""
	for machine in _tree.get_nodes_in_group(&"model_state_machine"):
		if machine.active_emotion != null and machine.active_emotion.emotion_name.to_lower() == emotion_name.to_lower():
			if not has_enabled or disable:
				machine.force_emotion("")
				return JSON.stringify({"status": "ok", "emotion": ""})
			return JSON.stringify({"status": "ok", "emotion": emotion_name})
		if disable:
			continue
		var error: String = machine.force_emotion(emotion_name)
		if error.is_empty():
			return JSON.stringify({"status": "ok", "emotion": emotion_name})
		last_error = error
	if disable:
		var model := _loader.model_loaded
		if model != null and model.get_emotion(emotion_name) != null:
			return JSON.stringify({"status": "ok", "emotion": emotion_name})
	return JSON.stringify({"status": "error", "message": "emotion not found: %s (%s)" % [emotion_name, last_error]})
