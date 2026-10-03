class_name TransformPresetPanel
extends "res://script/ui/model/transform_panel.gd"

const PRESET_PANEL_PREFAB: PackedScene = preload("uid://bp701ct6cxkc0")

@export_category("UI References")
@export var preset_list: VBoxContainer

var _current_position: Vector2 = Vector2.ZERO
var _current_scale: float = 1.0
var _current_rotation: float = 0.0
var _pending_refresh: bool = false

func _ready() -> void:
	super()
	SignalBus.presets_changed.connect(_refresh_list)
	_refresh_list()

func _exit_tree() -> void:
	super()
	NodeUtil.safe_disconnect(SignalBus, &"presets_changed", _refresh_list)

func _apply_transform_values(pos: Vector2, sc: float, rot: float) -> void:
	_current_position = pos
	_current_scale = sc
	_current_rotation = rot

func _on_save_pressed() -> void:
	if ModelLoader.model_loaded == null:
		return
	var preset := TransformPreset.new(
		"Preset %d" % (ModelLoader.model_loaded.transform_presets.size() + 1),
		_current_position,
		_current_scale,
		_current_rotation
	)
	ModelLoader.model_loaded.transform_presets.append(preset)
	ModelLoader.save_model()
	SignalBus.presets_changed.emit()
	_refresh_list()

func _on_panel_apply(preset: TransformPreset) -> void:
	_request_preset(preset)

func _on_panel_update(preset: TransformPreset) -> void:
	if ModelLoader.model_loaded == null:
		return
	if not ModelLoader.model_loaded.transform_presets.has(preset):
		return
	preset.position = _current_position
	preset.scale_value = _current_scale
	preset.rotation = _current_rotation
	ModelLoader.save_model()

func _on_panel_delete(preset: TransformPreset) -> void:
	if ModelLoader.model_loaded == null:
		return
	if not ModelLoader.model_loaded.transform_presets.has(preset):
		return
	if preset.trigger != null:
		preset.trigger.deactivate()
	ModelLoader.model_loaded.transform_presets.erase(preset)
	ModelLoader.save_model()
	SignalBus.presets_changed.emit()
	_refresh_list()

func _refresh_list() -> void:
	if _pending_refresh:
		return
	_pending_refresh = true
	NodeUtil.clear_children(preset_list)
	call_deferred(&"_populate_list")

func _populate_list() -> void:
	_pending_refresh = false
	if ModelLoader.model_loaded == null:
		return
	for preset in ModelLoader.model_loaded.transform_presets:
		var panel: PresetPanel = PRESET_PANEL_PREFAB.instantiate()
		panel.apply_requested.connect(_on_panel_apply)
		panel.update_requested.connect(_on_panel_update)
		panel.delete_requested.connect(_on_panel_delete)
		panel.setup(preset)
		preset_list.add_child(panel)
