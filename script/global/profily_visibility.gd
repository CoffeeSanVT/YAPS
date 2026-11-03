extends Node

var _ram_usage: Node

func _ready() -> void:
	SignalBus.performance_overlay_changed.connect(_on_visibility_changed)
	var manager := ProfilyManager.instance
	if manager != null:
		manager.active_toggled.connect(_on_active_toggled)
		_wire_ram_source(manager)
	_apply_visibility(Settings.settings.show_performance_overlay)

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"performance_overlay_changed", _on_visibility_changed)
	var manager := ProfilyManager.instance
	if manager != null:
		NodeUtil.safe_disconnect(manager, &"active_toggled", _on_active_toggled)

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

func _on_visibility_changed(value: bool) -> void:
	_apply_visibility(value)

func _apply_visibility(value: bool) -> void:
	var manager := ProfilyManager.instance
	if manager == null:
		return
	if value:
		manager.enable()
	else:
		manager.disable()

func _on_active_toggled(active: bool) -> void:
	if Settings.settings.show_performance_overlay != active:
		SignalBus.performance_overlay_changed.emit(active)
