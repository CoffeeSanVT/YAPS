class_name NodeUtil
extends RefCounted

const TAG := "[NodeUtil] "


static func stop_tween(tween: Tween) -> Tween:
	if tween != null and tween.is_valid():
		tween.kill()
	return null



static func ensure_timer(holder: Node, timer: Timer, handler: Callable, one_shot: bool) -> Timer:
	if is_instance_valid(timer):
		return timer
	var created := Timer.new()
	created.one_shot = one_shot
	created.timeout.connect(handler)
	holder.add_child(created)
	return created

static func free_timer(timer: Timer) -> Timer:
	if is_instance_valid(timer):
		timer.stop()
		timer.queue_free()
	return null



static func safe_disconnect(emitter: Object, signal_name: StringName, callable: Callable) -> void:
	if is_instance_valid(emitter) and emitter.is_connected(signal_name, callable):
		emitter.disconnect(signal_name, callable)

static func connect_once(emitter: Object, signal_name: StringName, callable: Callable) -> void:
	if is_instance_valid(emitter) and not emitter.is_connected(signal_name, callable):
		emitter.connect(signal_name, callable)

static func connect_many(entries: Array) -> void:
	for entry: Array in entries:
		connect_once(entry[0], entry[1], entry[2])

static func disconnect_many(entries: Array) -> void:
	for entry: Array in entries:
		safe_disconnect(entry[0], entry[1], entry[2])



static func clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

static func instantiate_into(prefab: PackedScene, container: Container, warning_context: String) -> Node:
	if prefab == null:
		push_warning(TAG + "%s has no ui_prefab; cannot build its UI." % warning_context)
		return null
	var ui: Node = prefab.instantiate()
	container.add_child(ui)
	return ui

static func option_index_by_metadata(button: OptionButton, value: Variant, fallback: int = 0) -> int:
	for i: int in button.item_count:
		if button.get_item_metadata(i) == value:
			return i
	return fallback



static func attach_locale(node: Node, handler: Callable) -> void:
	SignalBus.locale_refresh_requested.connect(handler)
	node.tree_exiting.connect(func() -> void:
		NodeUtil.safe_disconnect(SignalBus, &"locale_refresh_requested", handler)
	)

