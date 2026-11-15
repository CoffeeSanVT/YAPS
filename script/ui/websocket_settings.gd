extends VBoxContainer

const SECTION_HEADING_FONT := preload("res://assets/fonts/PlusJakartaSans-Bold.tres")

@export_category("Connection")
@export var toggle: CheckButton
@export var port_container: Control
@export var port_spinbox: SpinBox
@export var url_container: HBoxContainer
@export var url_label: Label
@export var copy_button: Button

@export_category("Actions")
@export var actions_foldable: VBoxContainer

func _ready() -> void:
	toggle.button_pressed = Settings.settings.websocket_enabled
	port_spinbox.value = Settings.settings.websocket_port
	_update_port_visible(Settings.settings.websocket_enabled)
	_update_url(Settings.settings.websocket_port)
	_populate_actions()

	port_spinbox.value_changed.connect(_on_port_changed)
	copy_button.pressed.connect(_on_copy_pressed)
	NodeUtil.attach_locale(self, _populate_actions)
	SignalBus.websocket_actions_changed.connect(_populate_actions)
	SignalBus.states_changed.connect(_populate_actions)
	SignalBus.items_changed.connect(_populate_actions, CONNECT_DEFERRED)
	SignalBus.presets_changed.connect(_populate_actions)
	SignalBus.model_triggers_changed.connect(_populate_actions, CONNECT_DEFERRED)

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"websocket_actions_changed", _populate_actions)
	NodeUtil.safe_disconnect(SignalBus, &"states_changed", _populate_actions)
	NodeUtil.safe_disconnect(SignalBus, &"items_changed", _populate_actions)
	NodeUtil.safe_disconnect(SignalBus, &"presets_changed", _populate_actions)
	NodeUtil.safe_disconnect(SignalBus, &"model_triggers_changed", _populate_actions)

func _on_toggled(toggled_on: bool) -> void:
	SignalBus.websocket_enabled_changed.emit(toggled_on)
	_update_port_visible(toggled_on)

func _on_port_changed(value: float) -> void:
	SignalBus.websocket_port_changed.emit(int(value))
	_update_url(int(value))

func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(url_label.text)

func _update_port_visible(enabled: bool) -> void:
	port_container.visible = enabled
	url_container.visible = enabled
	actions_foldable.visible = enabled

func _update_url(port: int) -> void:
	url_label.text = "ws://%s:%d" % [WebSocketServer.DEFAULT_BIND_ADDRESS, port]

func _populate_actions() -> void:
	for child in actions_foldable.get_children():
		actions_foldable.remove_child(child)
		child.queue_free()

	var profile: ModelProfile = ModelLoader.model_loaded
	var emotions := PackedStringArray([ModelWsApi.CMD_GET_EMOTIONS])
	var items := PackedStringArray([ModelWsApi.CMD_GET_ITEMS])
	var presets := PackedStringArray([ModelWsApi.CMD_GET_PRESETS])
	if profile != null:
		for emotion in profile.emotions:
			emotions.append(ModelWsApi.set_emotion_command(emotion.emotion_name))
		for item in profile.items:
			items.append(ModelWsApi.set_item_command(item.state_name))
		for preset in profile.transform_presets:
			presets.append(ModelWsApi.apply_preset_command(preset.preset_name))

	if emotions.size() == 1:
		emotions.append(ModelWsApi.set_emotion_command("<emotion>"))
	if items.size() == 1:
		items.append(ModelWsApi.set_item_command("<item>"))
	if presets.size() == 1:
		presets.append(ModelWsApi.apply_preset_command("<preset>"))

	_add_action_section(&"EMOTIONS", emotions)
	_add_action_section(&"ASSETS", items)
	_add_action_section(&"PRESETS", presets)
	_add_action_section(&"TRANSFORM", PackedStringArray([
		ModelWsApi.CMD_GET_FLIP,
		ModelWsApi.CMD_SET_FLIP,
		ModelWsApi.set_flip_command(true),
		ModelWsApi.set_flip_command(false),
		ModelWsApi.set_position_command("x", 0.0),
		ModelWsApi.set_position_command("y", 0.0),
		ModelWsApi.set_position_command("x", 0.1, ModelWsApi.TRANSFORM_ADD),
		"%s:%s" % [ModelWsApi.set_position_command("x", 5.0), ModelWsApi.TRANSFORM_INTERPOLATE],
		ModelWsApi.set_rotation_command(0.0),
		ModelWsApi.set_rotation_command(15.0, ModelWsApi.TRANSFORM_SUBTRACT),
		"%s:%s:0.5:sine:out" % [ModelWsApi.set_rotation_command(15.0, ModelWsApi.TRANSFORM_SUBTRACT), ModelWsApi.TRANSFORM_INTERPOLATE],
		ModelWsApi.set_size_command(1.0),
		ModelWsApi.set_size_command(0.1, ModelWsApi.TRANSFORM_ADD),
		"%s:%s" % [ModelWsApi.set_size_command(1.0), ModelWsApi.TRANSFORM_INTERPOLATE],
	]))

func _add_action_section(title_key: StringName, commands: PackedStringArray) -> void:
	if actions_foldable.get_child_count() > 0:
		actions_foldable.add_child(HSeparator.new())

	var section := VBoxContainer.new()
	actions_foldable.add_child(section)

	var heading := Label.new()
	heading.text = tr(title_key)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_override(&"font", SECTION_HEADING_FONT)
	heading.add_theme_font_size_override(&"font_size", 18)
	section.add_child(heading)

	for key in commands:
		var label := RichTextLabel.new()
		label.text = key
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.selection_enabled = true
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.scroll_active = false
		label.fit_content = true
		section.add_child(label)
