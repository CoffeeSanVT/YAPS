class_name TriggerUiSlot
extends RefCounted

var _container: Container
var _ui: Node

static func ensure(holder: Object, slot_property: StringName, container: Container) -> TriggerUiSlot:
	var slot := holder.get(slot_property) as TriggerUiSlot
	if slot == null:
		slot = TriggerUiSlot.new(container)
		holder.set(slot_property, slot)
	return slot

func _init(container: Container) -> void:
	_container = container

func clear() -> void:
	if _ui != null:
		_ui.queue_free()
	_ui = null
	NodeUtil.clear_children(_container)

func show_trigger(trigger: BaseTrigger, configure_key_bind: Callable) -> Node:
	clear()
	if trigger == null or trigger.trigger_name == &"":
		return null
	var ui_prefab: PackedScene = trigger.ui_prefab
	if ui_prefab == null:
		return null
	_ui = TriggerUtil.instantiate_trigger_ui(ui_prefab, _container, trigger, configure_key_bind)
	return _ui
