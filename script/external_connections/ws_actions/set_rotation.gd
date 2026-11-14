extends WebSocketAction

const COMMAND := &"set_rotation"

var _tree: SceneTree

func _init(tree: SceneTree) -> void:
	super(COMMAND)
	_tree = tree

func exec(arg: String) -> String:
	var controller := UpdateModelTransform.find_controller(_tree)
	if controller == null:
		return JSON.stringify({"status": "error", "message": "transform controller not found"})
	var value_and_options := arg.to_lower().split(":")
	var value_text := value_and_options[0].strip_edges()
	if not value_text.is_valid_float():
		return JSON.stringify({"status": "error", "message": "invalid rotation value: %s" % arg})
	var parsed := TransformOptions.parse(
		value_text.to_float(), value_and_options.slice(1), controller.current_rotation()
	)
	if parsed.is_empty():
		return JSON.stringify({"status": "error", "message": "invalid rotation value: %s" % arg})
	var angle: float = parsed["value"]
	controller.apply_rotation(angle, parsed["interpolation"] as TransformPreset)
	return JSON.stringify({"status": "ok", "rotation": angle})
