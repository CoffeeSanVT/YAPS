extends Node

const SETTINGS_RELATIVE_PATH := "settings.tres"

var settings: SettingsData
var settings_save_path := ""
var settings_dir := ""

var _saver := IoService.DeferredSaver.new()

func _ready() -> void:
	PhysicsServer3D.set_active(false)
	get_window().focus_exited.connect(_on_window_focus_exited)
	settings_save_path = PathUtil.get_config_folder_path().path_join(SETTINGS_RELATIVE_PATH)
	settings_dir = settings_save_path.get_base_dir()

	settings = _load_or_create_settings()

	SignalBus.fps_limit_changed.connect(_on_fps_limit_changed)
	SignalBus.performance_overlay_changed.connect(_apply_setting.bind(&"show_performance_overlay"))
	SignalBus.window_resolution_changed.connect(_on_window_resolution_changed)
	SignalBus.texture_filter_changed.connect(_apply_setting.bind(&"texture_filter"))
	SignalBus.antialias_changed.connect(_apply_setting.bind(&"antialias"))
	SignalBus.mic_device_changed.connect(_apply_setting.bind(&"mic_device"))
	SignalBus.mic_visualizer_changed.connect(_apply_setting.bind(&"show_mic_visualizer"))
	SignalBus.spout_enabled_changed.connect(_apply_setting.bind(&"spout_enabled"))
	SignalBus.websocket_enabled_changed.connect(_apply_setting.bind(&"websocket_enabled"))
	SignalBus.websocket_port_changed.connect(_apply_setting.bind(&"websocket_port"))
	SignalBus.mic_threshold_changed.connect(_apply_setting.bind(&"mic_threshold"))
	SignalBus.locale_changed.connect(_on_locale_changed)
	SignalBus.twitch_connected.connect(_on_twitch_connected)
	SignalBus.twitch_disconnected.connect(_on_twitch_disconnected)

	Engine.max_fps = settings.max_fps
	_on_window_resolution_changed(settings.window_resolution)
	TranslationServer.set_locale(settings.preferred_locale)

	if settings.mic_device != "" and settings.mic_device in AudioServer.get_input_device_list():
		AudioServer.set_input_device(settings.mic_device)

func _on_window_focus_exited() -> void:
	var viewport := get_viewport()
	if is_instance_valid(viewport):
		viewport.gui_release_focus()

func _load_or_create_settings() -> SettingsData:
	if ResourceLoader.exists(settings_save_path):
		var saved: SettingsData = ResourceLoader.load(settings_save_path) as SettingsData
		if saved:
			return saved

	return SettingsData.new()

func save_settings() -> void:
	_saver.save_resource(settings, settings_save_path, settings_dir)

func _apply_setting(value: Variant, property: StringName) -> void:
	settings.set(property, value)
	save_settings()

func _on_fps_limit_changed(value: int) -> void:
	settings.max_fps = value
	Engine.max_fps = value
	save_settings()

func _on_window_resolution_changed(value: Vector2i) -> void:
	settings.window_resolution = value
	save_settings()
	var window: Window = get_window()
	window.content_scale_size = value
	window.set_size(value)
	_center_window.call_deferred(window)

func _center_window(window: Window) -> void:
	var screen_index := DisplayServer.SCREEN_OF_MAIN_WINDOW
	var screen_pos: Vector2i = DisplayServer.screen_get_position(screen_index)
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen_index)
	var window_size: Vector2i = window.get_size()
	@warning_ignore("integer_division")
	var offset: Vector2i = ((screen_size - window_size) / 2).max(Vector2i.ZERO)
	window.position = screen_pos + offset

func _on_locale_changed(locale: String) -> void:
	settings.preferred_locale = locale
	TranslationServer.set_locale(locale)
	save_settings()
	SignalBus.locale_refresh_requested.emit()

func _on_twitch_connected(username: String) -> void:
	settings.twitch_username = username
	save_settings()

func _on_twitch_disconnected() -> void:
	TwitchTokenStore.clear_token()
	settings.twitch_username = ""
	settings.twitch_user_id = ""
	save_settings()
