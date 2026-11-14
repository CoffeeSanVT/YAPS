extends WebSocketAction

const COMMAND := &"set_position"

var _tree: SceneTree

func _init(tree: SceneTree) -> void:
	super(COMMAND)
	_tree = tree

func exec(arg: String) -> String:
	var controller := UpdateModelTransform.find_controller(_tree)
	if controller == null:
		return JSON.stringify({"status": "error", "message": "transform controller not found"})
	var parts := arg.split(":", true, 1)
	var axis := parts[0].strip_edges().to_lower()
	if parts.size() != 2 or axis not in ["x", "y"]:
		return JSON.stringify({"status": "error", "message": "invalid position argument: %s" % arg})
	var position := controller.current_position()
	var current := position.x if axis == "x" else -position.y
	var value_and_options := parts[1].to_lower().split(":")
	var value_text := value_and_options[0].strip_edges()
	if not value_text.is_valid_float():
		return JSON.stringify({"status": "error", "message": "invalid position argument: %s" % arg})
	var parsed := TransformOptions.parse(
		value_text.to_float(), value_and_options.slice(1), current
	)
	if parsed.is_empty():
		return JSON.stringify({"status": "error", "message": "invalid position argument: %s" % arg})
	var value: float = parsed["value"]
	var interpolation := parsed["interpolation"] as TransformPreset
	if axis == "x":
		position.x = value
		controller.apply_position_axis(axis, value, interpolation)
	else:
		position.y = -value
		controller.apply_position_axis(axis, -value, interpolation)
	return JSON.stringify({"status": "ok", "axis": axis, "position": {"x": position.x, "y": -position.y}})
