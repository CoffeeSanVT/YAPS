class_name SpoutViewportUtil

const TAG := "[SpoutViewport] "
const SENDER_NAME := "YAPS"

static func apply_enabled(model_container: Control, enabled: bool) -> Control:
	if model_container == null:
		push_warning(TAG + "Cannot apply Spout: model_container is null.")
		return model_container
	if enabled and not available():
		push_warning(TAG + "Spout enabled in settings but SpoutViewport class unavailable. Falling back to plain viewport.")
		enabled = false
	var viewport := model_container.get_parent()
	var is_spout := is_spout_viewport(viewport)
	if is_spout == enabled:
		return model_container
	var viewport_name := viewport.name
	var parent := viewport.get_parent()
	var index := viewport.get_index()
	var children := viewport.get_children()
	var replacement := create_viewport(enabled)
	viewport.name = viewport_name + "_old"
	parent.add_child(replacement)
	for child: Node in children:
		viewport.remove_child(child)
		replacement.add_child(child)
	parent.move_child(replacement, index)
	viewport.queue_free()
	replacement.name = viewport_name
	if parent is SubViewportContainer and not parent.stretch:
		replacement.size = Vector2i(parent.size)
	return replacement.find_child(&"ModelContainer", false, false) as Control

static func available() -> bool:
	return ClassDB.class_exists(&"SpoutViewport")

static func is_spout_viewport(node: Node) -> bool:
	return available() and node.get_class() == &"SpoutViewport"

static func create_viewport(enabled: bool) -> SubViewport:
	var replacement: SubViewport = null
	if enabled and available():
		replacement = ClassDB.instantiate(&"SpoutViewport") as SubViewport
	else:
		if enabled:
			push_error(TAG + "SpoutViewport class requested but not available. Creating plain SubViewport instead.")
		replacement = SubViewport.new()
	replacement.unique_name_in_owner = true
	replacement.disable_3d = true
	replacement.transparent_bg = true
	replacement.handle_input_locally = false
	replacement.oversampling = false
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		replacement.size = tree.root.size
	replacement.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if enabled and replacement.get_class() == &"SpoutViewport":
		replacement.set(&"sender_name", SENDER_NAME)
	return replacement
