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

static func set_position_command(axis: String, value: float) -> String:
	return "%s:%s:%s" % [CMD_SET_POSITION, axis, value]

static func set_rotation_command(angle: float) -> String:
	return "%s:%s" % [CMD_SET_ROTATION, angle]

static func set_size_command(value: float) -> String:
	return "%s:%s" % [CMD_SET_SIZE, value]

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
	var parsed := _split_axis_value(arg)
	if parsed.is_empty():
		_respond({"status": "error", "message": "invalid position argument: %s" % arg})
		return
	var axis: String = parsed["axis"]
	var value: float = parsed["value"]
	var position := controller.current_position()
	if axis == "x":
		position.x = value
	else:
		position.y = -value
	controller.apply_position(position)
	_respond({"status": "ok", "axis": axis, "position": {"x": position.x, "y": -position.y}})

func _set_rotation(arg: String) -> void:
	var controller := _transform_controller()
	if controller == null:
		_respond({"status": "error", "message": "transform controller not found"})
		return
	var text := arg.strip_edges()
	if not text.is_valid_float():
		_respond({"status": "error", "message": "invalid rotation value: %s" % arg})
		return
	var angle := text.to_float()
	controller.apply_rotation(angle)
	_respond({"status": "ok", "rotation": angle})

func _set_size(arg: String) -> void:
	var controller := _transform_controller()
	if controller == null:
		_respond({"status": "error", "message": "transform controller not found"})
		return
	var text := arg.strip_edges()
	if not text.is_valid_float():
		_respond({"status": "error", "message": "invalid size value: %s" % arg})
		return
	var value := text.to_float()
	controller.apply_scale(value)
	_respond({"status": "ok", "size": value})

static func _split_axis_value(arg: String) -> Dictionary:
	var colon := arg.find(":")
	if colon < 0:
		return {}
	var axis := arg.substr(0, colon).strip_edges().to_lower()
	var text := arg.substr(colon + 1).strip_edges()
	if not (axis == "x" or axis == "y") or not text.is_valid_float():
		return {}
	return {"axis": axis, "value": text.to_float()}

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
