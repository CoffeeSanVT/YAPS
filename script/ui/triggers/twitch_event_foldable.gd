class_name TwitchEventFoldable
extends VBoxContainer

signal twitch_event_changed(twitch_event: TwitchEvent)

@export_category("UI References")
@export var twitch_toggle: CheckButton
@export var twitch_foldable: FoldableContainer
@export var twitch_content: VBoxContainer

var twitch_event: TwitchEvent
var _twitch_ui: Node
var _loading: bool = false

func _ready() -> void:
	twitch_toggle.toggled.connect(_on_twitch_toggled)

func setup(event: TwitchEvent) -> void:
	_loading = true
	twitch_event = event
	var active := twitch_event != null and twitch_event.event_type != &""
	twitch_toggle.set_pressed_no_signal(active)
	twitch_foldable.visible = active
	twitch_foldable.folded = not active
	if active:
		_instantiate_twitch_ui(twitch_event)
	_loading = false

func _on_twitch_toggled(pressed: bool) -> void:
	if _loading:
		return
	if pressed:
		if twitch_event == null:
			twitch_event = TwitchEvent.new()
		twitch_foldable.visible = true
		twitch_foldable.folded = false
		_instantiate_twitch_ui(twitch_event)
	else:
		_clear_twitch_ui()
		twitch_foldable.folded = true
		twitch_foldable.visible = false
		twitch_event = null
	twitch_event_changed.emit(twitch_event)

func _instantiate_twitch_ui(event: TwitchEvent) -> void:
	_clear_twitch_ui()
	var ui := event.ui_prefab.instantiate()
	_twitch_ui = ui
	twitch_content.add_child(ui)
	if ui is TwitchEventUi:
		(ui as TwitchEventUi).setup(event)

func _clear_twitch_ui() -> void:
	if _twitch_ui != null and is_instance_valid(_twitch_ui):
		_twitch_ui.queue_free()
	_twitch_ui = null
