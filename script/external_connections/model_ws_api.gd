class_name ModelWsApi
extends Node

const CMD_GET_STATES := &"get_states"
const CMD_SET_STATE := &"set_state"
const CMD_GET_ITEMS := &"get_items"
const CMD_SET_ITEM := &"set_item"
const CMD_GET_EMOTIONS := &"get_emotions"
const CMD_SET_EMOTION := &"set_emotion"
const CMD_GET_PRESETS := &"get_presets"
const CMD_APPLY_PRESET := &"apply_preset"

var _loader: ModelLoader

func _init(loader: ModelLoader) -> void:
	_loader = loader

func _ready() -> void:
	WebSocketServer.register_action(CMD_GET_STATES, _get_states)
	WebSocketServer.register_action(CMD_SET_STATE, _set_state)
	WebSocketServer.register_action(CMD_GET_ITEMS, _get_items)
	WebSocketServer.register_action(CMD_SET_ITEM, _set_item)
	WebSocketServer.register_action(CMD_GET_EMOTIONS, _get_emotions)
	WebSocketServer.register_action(CMD_SET_EMOTION, _set_emotion)
	WebSocketServer.register_action(CMD_GET_PRESETS, _get_presets)
	WebSocketServer.register_action(CMD_APPLY_PRESET, _apply_preset)

func _exit_tree() -> void:
	WebSocketServer.unregister_action(CMD_GET_STATES)
	WebSocketServer.unregister_action(CMD_SET_STATE)
	WebSocketServer.unregister_action(CMD_GET_ITEMS)
	WebSocketServer.unregister_action(CMD_SET_ITEM)
	WebSocketServer.unregister_action(CMD_GET_EMOTIONS)
	WebSocketServer.unregister_action(CMD_SET_EMOTION)
	WebSocketServer.unregister_action(CMD_GET_PRESETS)
	WebSocketServer.unregister_action(CMD_APPLY_PRESET)

static func set_emotion_command(emotion_name: String) -> String:
	return "%s:%s" % [CMD_SET_EMOTION, emotion_name]

static func set_item_command(item_name: String) -> String:
	return "%s:%s" % [CMD_SET_ITEM, item_name]

static func apply_preset_command(preset_name: String) -> String:
	return "%s:%s" % [CMD_APPLY_PRESET, preset_name]

func _respond(payload: Dictionary) -> void:
	_respond_raw(JSON.stringify(payload))

func _respond_raw(payload: String) -> void:
	WebSocketServer.send_to_all(payload)

func _get_model() -> ModelProfile:
	return _loader.model_loaded

func _get_states(_arg: String) -> void:
	var model := _get_model()
	if model == null:
		_respond({"status": "error", "message": "no model loaded"})
		return
	var paths: Array[String] = []
	for branch in model.branches:
		if branch.default_entry != null:
			paths.append(branch.default_entry.state_name)
		for entry in branch.emotion_entries:
			paths.append("%s/%s" % [branch.state_name, entry.state_name])
	_respond({"status": "ok", "states": paths})

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

func _set_state(arg: String) -> void:
	var last_error := ""
	for machine in get_tree().get_nodes_in_group(&"model_state_machine"):
		var current_path := _current_entry_path(machine)
		if not current_path.is_empty() and current_path == arg:
			machine.force_emotion("")
			_respond({"status": "ok", "state": _current_entry_path(machine)})
			return
		var error: String = machine.force_entry_by_path(arg)
		if error.is_empty():
			_respond({"status": "ok", "state": _current_entry_path(machine)})
			return
		last_error = error
	_respond({"status": "error", "message": "state not found: %s (%s)" % [arg, last_error]})

func _current_entry_path(machine: ModelStateMachine) -> String:
	var model := _loader.model_loaded
	var entry := machine.current_entry
	if entry == null or model == null:
		return ""
	for branch in model.branches:
		if branch.default_entry == entry:
			return entry.state_name
		if entry in branch.emotion_entries:
			return "%s/%s" % [branch.state_name, entry.state_name]
	return entry.state_name

func _set_item(arg: String) -> void:
	var model := _get_model()
	if model == null:
		_respond({"status": "error", "message": "no model loaded"})
		return
	var item := _find_named(model.items, &"state_name", arg) as Item
	if item == null:
		_respond({"status": "error", "message": "item not found: " + arg})
		return
	item.set_enabled(not item.enabled)
	_respond({"status": "ok", "item": arg, "enabled": item.enabled})

func _get_emotions(_arg: String) -> void:
	var model := _get_model()
	if model == null:
		_respond({"status": "error", "message": "no model loaded"})
		return
	_respond({"status": "ok", "emotions": _name_list(model.emotions, &"emotion_name")})

func _set_emotion(arg: String) -> void:
	var last_error := ""
	for machine in get_tree().get_nodes_in_group(&"model_state_machine"):
		if machine.active_emotion != null and machine.active_emotion.emotion_name.to_lower() == arg.to_lower():
			machine.force_emotion("")
			_respond({"status": "ok", "emotion": ""})
			return
		var error: String = machine.force_emotion(arg)
		if error.is_empty():
			_respond({"status": "ok", "emotion": arg})
			return
		last_error = error
	_respond({"status": "error", "message": "emotion not found: %s (%s)" % [arg, last_error]})

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
