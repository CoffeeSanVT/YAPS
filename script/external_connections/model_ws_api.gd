class_name ModelWsApi
extends Node

const GetItemsAction := preload("uid://bs8ga8cf1tfgh")
const SetItemAction := preload("uid://bcmlvyt0ghklf")
const GetEmotionsAction := preload("uid://b70tgspr3oj6f")
const SetEmotionAction := preload("uid://dadp8wwgww7w8")
const GetPresetsAction := preload("uid://cad06wna22ffm")
const ApplyPresetAction := preload("uid://b5gcrlr423qys")
const GetFlipAction := preload("uid://bwcsp5ugx5trc")
const SetFlipAction := preload("uid://cygy2wvriyob7")
const SetPositionAction := preload("uid://chie3omx3veug")
const SetRotationAction := preload("uid://culo765mskcck")
const SetSizeAction := preload("uid://31jvk33tuye3")

const CMD_GET_ITEMS := GetItemsAction.COMMAND
const CMD_SET_ITEM := SetItemAction.COMMAND
const CMD_GET_EMOTIONS := GetEmotionsAction.COMMAND
const CMD_SET_EMOTION := SetEmotionAction.COMMAND
const CMD_GET_PRESETS := GetPresetsAction.COMMAND
const CMD_APPLY_PRESET := ApplyPresetAction.COMMAND
const CMD_GET_FLIP := GetFlipAction.COMMAND
const CMD_SET_FLIP := SetFlipAction.COMMAND
const CMD_SET_POSITION := SetPositionAction.COMMAND
const CMD_SET_ROTATION := SetRotationAction.COMMAND
const CMD_SET_SIZE := SetSizeAction.COMMAND
const TRANSFORM_ADD := TransformOptions.TRANSFORM_ADD
const TRANSFORM_SUBTRACT := TransformOptions.TRANSFORM_SUBTRACT
const TRANSFORM_INTERPOLATE := TransformOptions.TRANSFORM_INTERPOLATE

var _loader: ModelLoader
var _actions: Array[WebSocketAction]

func _init(loader: ModelLoader) -> void:
	_loader = loader

func _ready() -> void:
	_actions = [
		GetItemsAction.new(_loader),
		SetItemAction.new(_loader),
		GetEmotionsAction.new(_loader),
		SetEmotionAction.new(_loader, get_tree()),
		GetPresetsAction.new(_loader),
		ApplyPresetAction.new(_loader, get_tree()),
		GetFlipAction.new(_loader),
		SetFlipAction.new(_loader),
		SetPositionAction.new(get_tree()),
		SetRotationAction.new(get_tree()),
		SetSizeAction.new(get_tree()),
	]
	for action in _actions:
		action.registerCommand()

func _exit_tree() -> void:
	for action in _actions:
		action.unregisterCommand()
	_actions.clear()

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
