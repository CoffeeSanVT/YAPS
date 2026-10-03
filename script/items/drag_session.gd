class_name DragSession
extends RefCounted


static var selected_draggable: Draggable
static var active_draggable: Draggable
static var select_menu_open := false

const MODEL_ITEMS_GROUP := &"model_items"

static func viewport_to_ratio(viewport_pos: Vector2, vp_size: Vector2) -> Vector2:
	if vp_size == Vector2.ZERO:
		return Vector2.ZERO
	return (viewport_pos / vp_size) * 2.0 - Vector2.ONE

static func ratio_to_viewport(ratio: Vector2, vp_size: Vector2) -> Vector2:
	return (ratio + Vector2.ONE) * 0.5 * vp_size

static func mouse_in_viewport(container: SubViewportContainer, viewport: Viewport) -> Vector2:
	if container == null:
		return Vector2.ZERO
	var local := container.get_local_mouse_position()
	if not is_instance_valid(viewport):
		return local
	return local.clamp(Vector2.ZERO, Vector2(viewport.size) - Vector2.ONE)

static func topmost_among(nodes: Array[Node], viewport_pos: Vector2) -> Draggable:
	var top: Draggable = null
	var top_z := 0
	for node in nodes:
		var child := node as Draggable
		if child == null or not child.visible or not child.is_inside_tree():
			continue
		if not get_rect_for(child).has_point(viewport_pos):
			continue
		var z := effective_z(child)
		if top == null or z >= top_z:
			top = child
			top_z = z
	return top

static func effective_z(node: CanvasItem) -> int:
	var z := 0
	var current := node
	while current != null:
		z += current.z_index
		current = current.get_parent() as CanvasItem
	return z

static func get_rect_for(node: Control) -> Rect2:
	var draggable := node as Draggable
	if draggable != null:
		return draggable.get_scaled_rect()
	return Rect2(node.position, node.size)

static func create_for_item(initial_texture: Texture2D, target_item: Item) -> Draggable:
	var rect := Draggable.new()
	rect.texture = initial_texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.size = Item.fit_size(initial_texture.get_size())
	rect.offset_transform_enabled = true
	rect.item = target_item
	rect.add_to_group(MODEL_ITEMS_GROUP)
	return rect

static func reset() -> void:
	selected_draggable = null
	active_draggable = null
	select_menu_open = false
