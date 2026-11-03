extends Node

const MENU_SCENE := PathUtil.MENU_SCENE
const MAIN_SCENE := PathUtil.MAIN_SCENE

var _in_main_scene: bool
var _ram_usage: Node

func _ready() -> void:
	SignalBus.performance_overlay_changed.connect(_on_visibility_changed)
	var manager := ProfilyManager.instance
	if manager != null:
		manager.active_toggled.connect(_on_active_toggled)
		_wire_ram_source(manager)
	get_tree().node_added.connect(_on_root_child_added)
	_refresh_scene_state.call_deferred()

func _exit_tree() -> void:
	get_tree().node_added.disconnect(_on_root_child_added)
	NodeUtil.safe_disconnect(SignalBus, &"performance_overlay_changed", _on_visibility_changed)
	var manager := ProfilyManager.instance
	if manager != null:
		NodeUtil.safe_disconnect(manager, &"active_toggled", _on_active_toggled)

func _on_root_child_added(node: Node) -> void:
	if node.get_parent() != get_tree().root:
		return
	if not (_matches_scene(node, MAIN_SCENE) or _matches_scene(node, MENU_SCENE)):
		return
	_refresh_scene_state.call_deferred()

func _refresh_scene_state() -> void:
	var current := get_tree().current_scene
	var in_main := current != null and _matches_scene(current, MAIN_SCENE)
	if in_main == _in_main_scene:
		return
	_in_main_scene = in_main
	_apply_visibility(_should_show())

func _matches_scene(node: Node, scene_uid: String) -> bool:
	var path := node.scene_file_path
	if path.is_empty():
		return false
	if path == scene_uid:
		return true
	return ResourceLoader.get_resource_uid(path) == ResourceUID.text_to_id(scene_uid)

func _should_show() -> bool:
	return _in_main_scene and Settings.settings.show_performance_overlay

func _wire_ram_source(manager: ProfilyManager) -> void:
	_ram_usage = get_node_or_null(^"/root/RamUsage")
	if _ram_usage == null:
		return
	var module: Node = manager._modules.get(ProfilyTypes.ModuleType.RAM) as Node
	if module == null:
		return
	var monitor: Node = module.monitor()
	if monitor != null:
		monitor.custom_source = _read_ram_usage

func _read_ram_usage() -> Vector2:
	return _ram_usage.GetRamUsageMiB()

func _on_visibility_changed(_value: bool) -> void:
	_apply_visibility(_should_show())

func _apply_visibility(value: bool) -> void:
	var manager := ProfilyManager.instance
	if manager == null:
		return
	if value:
		manager.enable()
	else:
		manager.disable()

func _on_active_toggled(active: bool) -> void:
	if not _in_main_scene:
		return
	if Settings.settings.show_performance_overlay != active:
		SignalBus.performance_overlay_changed.emit(active)
