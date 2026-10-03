@tool
extends EditorPlugin

var panel
var TOOL_PANEL: PackedScene = preload("res://addons/localization_apply/localization_panel.tscn")

func _enter_tree() -> void:
	panel = TOOL_PANEL.instantiate()

	add_control_to_dock(EditorPlugin.DOCK_SLOT_BOTTOM, panel)
	pass


func _exit_tree() -> void:
	remove_control_from_docks(panel)

	panel.queue_free()
