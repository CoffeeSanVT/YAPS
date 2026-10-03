extends Control

@export_category("UI References")
@export var items_container: Control
@export var scroll_container: ScrollContainer
@export var panel_prefab: PackedScene

const SELECTED_FLASH := Color(1.5, 1.5, 1.5)

var _refresh_queued := false
var _panels_by_item := {}
var _flash_tween: Tween

func _ready() -> void:
	NodeUtil.connect_once(SignalBus, &"items_changed", _queue_refresh)
	NodeUtil.connect_once(SignalBus, &"item_selected", _on_item_selected)
	_refresh_now()

func _queue_refresh(_item: Item = null) -> void:
	_refresh_queued = true

func _process(_delta: float) -> void:
	if _refresh_queued:
		_refresh_queued = false
		_refresh_now()

func _refresh_now() -> void:
	_flash_tween = NodeUtil.stop_tween(_flash_tween)
	for child in items_container.get_children():
		items_container.remove_child(child)
		child.free()
	_panels_by_item.clear()

	if ModelLoader.model_loaded == null:
		return

	if ModelLoader.model_loaded.items.size() == 0:
		var no_items_label := Label.new()
		no_items_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		no_items_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var font := load("uid://dmld38g0i2q0a")
		no_items_label.add_theme_font_override("font", font)
		no_items_label.text = tr("EMPTY_ASSETS_LIST")
		items_container.add_child(no_items_label)

	for item in ModelLoader.model_loaded.items:
		var panel := panel_prefab.instantiate()
		items_container.add_child(panel)
		panel.setup(item)
		panel.changed.connect(_queue_refresh)
		_panels_by_item[item] = panel

func _on_item_selected(item: Item) -> void:
	if item == null or not _panels_by_item.has(item):
		return
	var panel: Control = _panels_by_item[item]
	if not is_instance_valid(panel):
		return
	_flash_tween = NodeUtil.stop_tween(_flash_tween)
	if scroll_container != null:
		scroll_container.ensure_control_visible(panel)
	panel.self_modulate = SELECTED_FLASH
	_flash_tween = create_tween()
	_flash_tween.tween_property(panel, "self_modulate", Color.WHITE, 0.5)
