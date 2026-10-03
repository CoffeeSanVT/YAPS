extends VBoxContainer

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
	NodeUtil.clear_children(actions_foldable)

	_add_action_labels(_target_commands())

func _add_action_labels(commands: PackedStringArray) -> void:
	for key in commands:
		var label := RichTextLabel.new()
		label.name = StringName("ActionLabel_%s" % key)
		label.text = key
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.selection_enabled = true
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.fit_content = true
		actions_foldable.add_child(label)

func _target_commands() -> PackedStringArray:
	var profile: ModelProfile = ModelLoader.model_loaded
	var commands: Array[String] = []
	if profile == null:
		return PackedStringArray(commands)
	for emotion in profile.emotions:
		commands.append(ModelWsApi.set_emotion_command(emotion.emotion_name))
	for item in profile.items:
		commands.append(ModelWsApi.set_item_command(item.state_name))
	for preset in profile.transform_presets:
		commands.append(ModelWsApi.apply_preset_command(preset.preset_name))
	return PackedStringArray(commands)
