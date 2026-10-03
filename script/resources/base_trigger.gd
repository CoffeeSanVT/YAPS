class_name BaseTrigger
extends Resource

signal enabled_changed(trigger: BaseTrigger)

var trigger_name: StringName
var enabled: bool
var ui_prefab: PackedScene
@export var fade_duration: float = 0.25
@export var auto_hide_after: float = 0.0

func tick(_delta: float, _current_state: ModelStateEntry) -> void:
	pass

static var _available_options: Array[Dictionary] = []
static var _options_scanned := false

static func get_available_options() -> Array[Dictionary]:
	if not _options_scanned:
		_options_scanned = true
		_available_options = ClassScanner.scan_inheriters(&"BaseTrigger", &"trigger_name")
	return _available_options

static func get_key_trigger_options() -> Array[Dictionary]:
	return get_available_options().filter(
		func(option: Dictionary) -> bool:
			return option.id == &"key_pressed" or option.id == &"key_holding"
	)

static func localize_name(id: StringName) -> String:
	match id:
		&"key_pressed":
			return TranslationServer.translate(&"TRIGGER_KEY_PRESSED")
		&"key_holding":
			return TranslationServer.translate(&"TRIGGER_KEY_HOLD")
		&"start_talking":
			return TranslationServer.translate(&"TRIGGER_START_TALKING")
		&"volume_range":
			return TranslationServer.translate(&"TRIGGER_VOLUME_RANGE")
		&"twitch_event":
			return TranslationServer.translate(&"TRIGGER_TWITCH_EVENT")
	return String(id).capitalize()

func set_enabled(value: bool) -> void:
	if value == enabled:
		return
	enabled = value
	enabled_changed.emit(self)

func activate() -> void:
	pass

func deactivate() -> void:
	pass

func bind_changed(handler: Callable) -> void:
	NodeUtil.connect_once(self, &"enabled_changed", handler)
	activate()

func unbind_changed(handler: Callable) -> void:
	NodeUtil.safe_disconnect(self, &"enabled_changed", handler)
	deactivate()
