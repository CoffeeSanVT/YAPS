class_name SettingsData
extends Resource

@export_category("Performance")
@export var max_fps: int = 60
@export var show_performance_overlay: bool = false

@export_category("Microphone")
@export var mic_threshold: float = -48
@export var mic_device: String = ""
@export var show_mic_visualizer: bool = false
@export var mic_monitoring: bool = false
@export var mic_gain_db: float = 0.0
@export var mic_smoothing_attack: float = AudioSystem.SMOOTHING_ATTACK_DEFAULT
@export var mic_smoothing_release: float = AudioSystem.SMOOTHING_RELEASE_DEFAULT
@export var mic_talk_hysteresis: float = AudioSystem.TALK_HYSTERESIS_DB_DEFAULT
@export var mic_talk_hold: int = AudioSystem.TALK_HOLD_MS_DEFAULT
@export var mic_smooth_emit_fps: float = AudioSystem.SMOOTH_EMIT_FPS_DEFAULT

@export_category("Display")
@export var texture_filter: int = CanvasItem.TEXTURE_FILTER_LINEAR
@export var antialias: int = 0
@export var window_resolution: Vector2i = Vector2i(1600, 900)

const ANTIALIAS_MODE_MSAA_4X := 4
const ANTIALIAS_MODE_MSAA_2X := 5

@export_category("Output")
@export var spout_enabled: bool = true

@export_category("WebSocket")
@export var websocket_enabled: bool = false
@export var websocket_port: int = WebSocketServer.DEFAULT_PORT

@export_category("Twitch")
@export var twitch_username: String = ""
@export var twitch_user_id: String = ""

@export_category("Localization")
@export var preferred_locale: String = "en"
