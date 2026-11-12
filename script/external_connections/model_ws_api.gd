class_name ModelWsApi
extends Node

const CMD_GET_ITEMS := &"get_items"
const CMD_SET_ITEM := &"set_item"
const CMD_GET_EMOTIONS := &"get_emotions"
const CMD_SET_EMOTION := &"set_emotion"
const CMD_GET_PRESETS := &"get_presets"
const CMD_APPLY_PRESET := &"apply_preset"
const CMD_GET_FLIP := &"get_flip"
const CMD_SET_FLIP := &"set_flip"
const CMD_SET_POSITION := &"set_position"
const CMD_SET_ROTATION := &"set_rotation"
const CMD_SET_SIZE := &"set_size"
const TRANSFORM_ADD := "add"
const TRANSFORM_SUBTRACT := "subtract"
const TRANSFORM_INTERPOLATE := "interpolate"
const TRANSITIONS := {
	"linear": Tween.TRANS_LINEAR, "sine": Tween.TRANS_SINE, "quint": Tween.TRANS_QUINT,
	"quart": Tween.TRANS_QUART, "quad": Tween.TRANS_QUAD, "expo": Tween.TRANS_EXPO,
	"elastic": Tween.TRANS_ELASTIC, "cubic": Tween.TRANS_CUBIC, "circ": Tween.TRANS_CIRC,
	"bounce": Tween.TRANS_BOUNCE, "back": Tween.TRANS_BACK, "spring": Tween.TRANS_SPRING,
}
const EASES := {
	"in": Tween.EASE_IN, "out": Tween.EASE_OUT,
	"in_out": Tween.EASE_IN_OUT, "out_in": Tween.EASE_OUT_IN,
}

var _loader: ModelLoader

func _init(loader: ModelLoader) -> void:
	_loader = loader

func _ready() -> void:
	WebSocketServer.register_action(CMD_GET_ITEMS, _get_items)
	WebSocketServer.register_action(CMD_SET_ITEM, _set_item)
	WebSocketServer.register_action(CMD_GET_EMOTIONS, _get_emotions)
	WebSocketServer.register_action(CMD_SET_EMOTION, _set_emotion)
	WebSocketServer.register_action(CMD_GET_PRESETS, _get_presets)
	WebSocketServer.register_action(CMD_APPLY_PRESET, _apply_preset)
	WebSocketServer.register_action(CMD_GET_FLIP, _get_flip)
	WebSocketServer.register_action(CMD_SET_FLIP, _set_flip)
	WebSocketServer.register_action(CMD_SET_POSITION, _set_position)
	WebSocketServer.register_action(CMD_SET_ROTATION, _set_rotation)
	WebSocketServer.register_action(CMD_SET_SIZE, _set_size)

func _exit_tree() -> void:
	WebSocketServer.unregister_action(CMD_GET_ITEMS)
	WebSocketServer.unregister_action(CMD_SET_ITEM)
	WebSocketServer.unregister_action(CMD_GET_EMOTIONS)
	WebSocketServer.unregister_action(CMD_SET_EMOTION)
	WebSocketServer.unregister_action(CMD_GET_PRESETS)
	WebSocketServer.unregister_action(CMD_APPLY_PRESET)
	WebSocketServer.unregister_action(CMD_GET_FLIP)
	WebSocketServer.unregister_action(CMD_SET_FLIP)
	WebSocketServer.unregister_action(CMD_SET_POSITION)
	WebSocketServer.unregister_action(CMD_SET_ROTATION)
	WebSocketServer.unregister_action(CMD_SET_SIZE)

static func set_emotion_command(emotion_name: String) -> String:
	return "%s:%s" % [CMD_SET_EMOTION, emotion_name]

static func set_item_command(item_name: String) -> String:
	return "%s:%s" % [CMD_SET_ITEM, item_name]

static func apply_preset_command(preset_name: String) -> String:
	return "%s:%s" % [CMD_APPLY_PRESET, preset_name]

static func set_flip_command(value: bool) -> String:
	return "%s:%s" % [CMD_SET_FLIP, "true" if value else "false"]

static func set_position_command(axis: String, value: float, mode: String = "") -> String:
	return _with_transform_mode("%s:%s:%s" % [CMD_SET_POSITION, axis, value], mode)

static func set_rotation_command(angle: float, mode: String = "") -> String:
	return _with_transform_mode("%s:%s" % [CMD_SET_ROTATION, angle], mode)

static func set_size_command(value: float, mode: String = "") -> String:
	return _with_transform_mode("%s:%s" % [CMD_SET_SIZE, value], mode)

static func _with_transform_mode(command: String, mode: String) -> String:
	return command if mode.is_empty() else "%s:%s" % [command, mode]

func _respond(payload: Dictionary) -> void:
	WebSocketServer.send_to_all(JSON.stringify(payload))

func _get_model() -> ModelProfile:
	return _loader.model_loaded

func _get_items(_arg: String) -> void:
	var model := _get_model()
	if model == null:
		_respond({"status": "error", "message": "no model loaded"})
		return
	var items_data: Array[Dictionary] = []
	for item in model.items:
		items_data.append({
			"name": item.state_name,
			"enabled": item.enabled
		})
	_respond({"status": "ok", "items": items_data})

func _set_item(arg: String) -> void:
	var model := _get_model()
	if model == null:
		_respond({"status": "error", "message": "no model loaded"})
		return
	var parsed := _split_optional_bool(arg)
	var item := _find_named(model.items, &"state_name", parsed["name"]) as Item
	if item == null:
		_respond({"status": "error", "message": "item not found: %s" % parsed["name"]})
		return
	item.set_enabled(parsed["value"] if parsed["has_value"] else not item.enabled)
	_respond({"status": "ok", "item": parsed["name"], "enabled": item.enabled})

func _get_emotions(_arg: String) -> void:
	var model := _get_model()
	if model == null:
		_respond({"status": "error", "message": "no model loaded"})
		return
	_respond({"status": "ok", "emotions": _name_list(model.emotions, &"emotion_name")})

func _set_emotion(arg: String) -> void:
	var parsed := _split_optional_bool(arg)
	var emotion_name: String = parsed["name"]
	var last_error := ""
	for machine in get_tree().get_nodes_in_group(&"model_state_machine"):
		if machine.active_emotion != null and machine.active_emotion.emotion_name.to_lower() == emotion_name.to_lower():
			if not parsed["has_value"] or not parsed["value"]:
				machine.force_emotion("")
				_respond({"status": "ok", "emotion": ""})
			else:
				_respond({"status": "ok", "emotion": emotion_name})
			return
		if parsed["has_value"] and not parsed["value"]:
			continue
		var error: String = machine.force_emotion(emotion_name)
		if error.is_empty():
			_respond({"status": "ok", "emotion": emotion_name})
			return
		last_error = error
	if parsed["has_value"] and not parsed["value"]:
		var model := _get_model()
		if model != null and model.get_emotion(emotion_name) != null:
			_respond({"status": "ok", "emotion": emotion_name})
			return
	_respond({"status": "error", "message": "emotion not found: %s (%s)" % [emotion_name, last_error]})

func _get_presets(_arg: String) -> void:
	var model := _get_model()
	if model == null:
		_respond({"status": "error", "message": "no model loaded"})
		return
	_respond({"status": "ok", "presets": _name_list(model.transform_presets, &"preset_name")})

func _apply_preset(arg: String) -> void:
	var model := _get_model()
	if model == null:
		_respond({"status": "error", "message": "no model loaded"})
		return
	var preset := _find_named(model.transform_presets, &"preset_name", arg) as TransformPreset
	if preset == null:
		_respond({"status": "error", "message": "preset not found: " + arg})
		return
	var controller := UpdateModelTransform.find_controller(get_tree())
	if controller != null:
		controller.apply_preset(preset)
	_respond({"status": "ok", "preset": arg})

func _get_flip(_arg: String) -> void:
	var model := _get_model()
	if model == null:
		_respond({"status": "error", "message": "no model loaded"})
		return
	_respond({"status": "ok", "flip": model.flip_x})

func _set_flip(arg: String) -> void:
	var model := _get_model()
	if model == null:
		_respond({"status": "error", "message": "no model loaded"})
		return
	var value: Variant
	var normalized := arg.strip_edges().to_lower()
	match normalized:
		"":
			value = not model.flip_x
		"true", "1", "on", "flip":
			value = true
		"false", "0", "off":
			value = false
		_:
			_respond({"status": "error", "message": "invalid flip value: %s" % arg})
			return
	model.flip_x = value
	ModelLoader.save_model()
	SignalBus.model_flip_changed.emit(value)
	_respond({"status": "ok", "flip": value})

func _transform_controller() -> UpdateModelTransform:
	return UpdateModelTransform.find_controller(get_tree())

func _set_position(arg: String) -> void:
	var controller := _transform_controller()
	if controller == null:
		_respond({"status": "error", "message": "transform controller not found"})
		return
	var parts := arg.split(":", true, 1)
	var axis := parts[0].strip_edges().to_lower()
	if parts.size() != 2 or axis not in ["x", "y"]:
		_respond({"status": "error", "message": "invalid position argument: %s" % arg})
		return
	var position := controller.current_position()
	var current := position.x if axis == "x" else -position.y
	var parsed := _parse_transform_args(parts[1], current)
	if parsed.is_empty():
		_respond({"status": "error", "message": "invalid position argument: %s" % arg})
		return
	var value: float = parsed["value"]
	var interpolation := parsed["interpolation"] as TransformPreset
	if axis == "x":
		position.x = value
		controller.apply_position_axis(axis, value, interpolation)
	else:
		position.y = -value
		controller.apply_position_axis(axis, -value, interpolation)
	_respond({"status": "ok", "axis": axis, "position": {"x": position.x, "y": -position.y}})

func _set_rotation(arg: String) -> void:
	var controller := _transform_controller()
	if controller == null:
		_respond({"status": "error", "message": "transform controller not found"})
		return
	var parsed := _parse_transform_args(arg, controller.current_rotation())
	if parsed.is_empty():
		_respond({"status": "error", "message": "invalid rotation value: %s" % arg})
		return
	var angle: float = parsed["value"]
	controller.apply_rotation(angle, parsed["interpolation"] as TransformPreset)
	_respond({"status": "ok", "rotation": angle})

func _set_size(arg: String) -> void:
	var controller := _transform_controller()
	if controller == null:
		_respond({"status": "error", "message": "transform controller not found"})
		return
	var parsed := _parse_transform_args(arg, controller.current_scale())
	if parsed.is_empty():
		_respond({"status": "error", "message": "invalid size value: %s" % arg})
		return
	var value: float = parsed["value"]
	controller.apply_scale(value, parsed["interpolation"] as TransformPreset)
	_respond({"status": "ok", "size": value})

static func _parse_transform_args(arg: String, current: float) -> Dictionary:
	var parts := arg.strip_edges().to_lower().split(":")
	var text := parts[0].strip_edges()
	if not text.is_valid_float():
		return {}
	var value := text.to_float()
	var next := 1
	if next < parts.size():
		match parts[next].strip_edges():
			TRANSFORM_ADD:
				value = current + value
				next += 1
			TRANSFORM_SUBTRACT:
				value = current - value
				next += 1
	if not is_finite(value):
		return {}

	var interpolation: TransformPreset
	if next < parts.size():
		if parts[next].strip_edges() != TRANSFORM_INTERPOLATE:
			return {}
		interpolation = _parse_interpolation(parts.slice(next + 1))
		if interpolation == null:
			return {}
	return {"value": value, "interpolation": interpolation}

static func _parse_interpolation(parts: PackedStringArray) -> TransformPreset:
	if parts.size() > 3:
		return null

	var options := TransformPreset.new()
	var duration := parts[0].strip_edges() if parts.size() > 0 else ""
	var transition := parts[1].strip_edges() if parts.size() > 1 else ""
	var ease := parts[2].strip_edges() if parts.size() > 2 else ""
	if not duration.is_empty():
		if not duration.is_valid_float():
			return null
		options.duration = duration.to_float()
		if not is_finite(options.duration) or options.duration < 0.0:
			return null
	if not transition.is_empty():
		if not TRANSITIONS.has(transition):
			return null
		options.trans_type = TRANSITIONS[transition]
	if not ease.is_empty():
		if not EASES.has(ease):
			return null
		options.ease_type = EASES[ease]
	return options

static func _split_optional_bool(arg: String) -> Dictionary:
	var colon := arg.rfind(":")
	if colon >= 0:
		var normalized := arg.substr(colon + 1).strip_edges().to_lower()
		var value := false
		match normalized:
			"true", "1", "on":
				value = true
			"false", "0", "off":
				value = false
			_:
				return {"name": arg, "has_value": false, "value": false}
		return {"name": arg.substr(0, colon), "has_value": true, "value": value}
	return {"name": arg, "has_value": false, "value": false}

static func _find_named(entries: Array, prop: StringName, value: String) -> Variant:
	for entry: Variant in entries:
		if entry.get(prop) == value:
			return entry
	return null

static func _name_list(entries: Array, prop: StringName) -> Array[String]:
	var names: Array[String] = []
	for entry: Variant in entries:
		names.append(String(entry.get(prop)))
	return names
