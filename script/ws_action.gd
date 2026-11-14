@abstract
class_name WebSocketAction
extends RefCounted

var _commandName: StringName

func _init(command: StringName) -> void:
	_commandName = command

func registerCommand() -> void:
	WebSocketServer.register_action(_commandName, _dispatch)

func unregisterCommand() -> void:
	WebSocketServer.unregister_action(_commandName)

func _dispatch(args: String) -> void:
	WebSocketServer.send_to_all(exec(args))

@abstract
func exec(_args: String) -> String
