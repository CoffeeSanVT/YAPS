extends Panel

@export_category("Panels")
@export var model_panel: Control
@export var expression_panel: Control
@export var assets_panel: Control
@export var config_panel: Control

const ASSETS_TAB := 2

var _index: int = -1
var _panels: Array[Control]
var _option_was_open: OptionButton = null
var _panel_tweens: Dictionary = {}

func _ready() -> void:
	_panels = [model_panel, expression_panel, assets_panel, config_panel]
	NodeUtil.connect_once(SignalBus, &"item_selected", _on_item_selected)
	
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_handle_application_focus()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_handle_application_focus(false)

func _on_item_selected(item: Item) -> void:
	if item == null or _index == ASSETS_TAB:
		return
	_on_tab_pressed(ASSETS_TAB)

func _process(_delta: float) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is not OptionButton:
		_option_was_open = null
		return
	if focus.get_popup().visible:
		_option_was_open = focus
	elif _option_was_open == focus:
		get_viewport().gui_release_focus()
		_option_was_open = null

func _on_tab_pressed(tab_index: int) -> void:
	if _index == tab_index and _index != -1:
		_tween_exit(_panels[_index])
		_index = -1
		return

	_index = tab_index
	_handle_change_panels()

func _handle_change_panels() -> void:
	for i in _panels.size():
		var panel := _panels[i]

		if i != _index:
			_tween_exit(panel)
		else:
			var first_open := not panel.visible
			panel.show()
			_tween_enter(panel, first_open)

func _on_model_button_up() -> void:
	_on_tab_pressed(0)

func _on_expressions_button_up() -> void:
	_on_tab_pressed(1)

func _on_assets_button_up() -> void:
	_on_tab_pressed(2)

func _on_config_button_up() -> void:
	_on_tab_pressed(3)

func _handle_application_focus(in_screen: bool = true) -> void:
	if in_screen:
		$".".show()
		if _index != -1:
			_panels[_index].show()
	else:
		$".".hide()
		if _index != -1:
			_panels[_index].hide()

func _tween_enter(panel: Control, first_open: bool = false) -> void:
	_kill_panel_tween(panel)
	var tween: Tween = create_tween()
	_panel_tweens[panel] = tween
	var panel_in_pos: float = 0
	var panel_out_pos: float = panel.get_meta("out_screen_x_pos", 0)

	panel.offset_transform_pivot_ratio.x = panel_out_pos
	if first_open:
		panel.offset_transform_position_ratio.x = panel_out_pos

	tween.tween_property(panel, "offset_transform_position_ratio:x", panel_in_pos, 0.2)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_EXPO)

func _tween_exit(panel: Control) -> void:
	_kill_panel_tween(panel)
	var tween: Tween = create_tween()
	_panel_tweens[panel] = tween
	var panel_in_pos: float = 0
	var panel_out_pos: float = panel.get_meta("out_screen_x_pos", 0)

	panel.offset_transform_pivot_ratio.x = panel_in_pos

	tween.tween_property(panel, "offset_transform_position_ratio:x", panel_out_pos , 0.2)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_EXPO)
	tween.tween_callback(func() -> void: panel.hide())
	get_viewport().gui_release_focus()

func _kill_panel_tween(panel: Control) -> void:
	NodeUtil.stop_tween(_panel_tweens.get(panel))
	_panel_tweens.erase(panel)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			if focus.get_global_rect().has_point(event.position):
				return
		get_viewport().gui_release_focus()
