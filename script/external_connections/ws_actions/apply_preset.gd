extends WebSocketAction

const COMMAND := &"apply_preset"

var _loader: ModelLoader
var _tree: SceneTree

func _init(loader: ModelLoader, tree: SceneTree) -> void:
	super(COMMAND)
	_loader = loader
	_tree = tree

func exec(arg: String) -> String:
	var model := _loader.model_loaded
	if model == null:
		return JSON.stringify({"status": "error", "message": "no model loaded"})
	var preset := ActionArguments.find_named(model.transform_presets, &"preset_name", arg) as TransformPreset
	if preset == null:
		return JSON.stringify({"status": "error", "message": "preset not found: " + arg})
	var controller := UpdateModelTransform.find_controller(_tree)
	if controller != null:
		controller.apply_preset(preset)
	return JSON.stringify({"status": "ok", "preset": arg})
