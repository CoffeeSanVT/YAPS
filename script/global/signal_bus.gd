@warning_ignore_start("unused_signal")
extends Node

signal locale_refresh_requested()
signal locale_changed(locale: String)

signal remapping_started(action_name: String)
signal remapping_success(action_name: String, shortcut_key: String)

signal fps_limit_changed(value: int)
signal performance_overlay_changed(visible: bool)
signal window_resolution_changed(value: Vector2i)
signal texture_filter_changed(value: int)
signal antialias_changed(value: int)
signal outline_settings_changed()

signal mic_threshold_changed(value: float)
signal mic_device_changed(device_name: String)
signal mic_visualizer_changed(visible: bool)
signal mic_monitoring_changed(enabled: bool)
signal mic_gain_changed(gain_db: float)
signal mic_input_detected(volume: float)
signal mic_input_smoothed(smoothed_db: float)
signal mic_input_exceed_threshold(exceeded: bool)

signal spout_enabled_changed(value: bool)
signal websocket_enabled_changed(value: bool)
signal websocket_port_changed(value: int)
signal websocket_actions_changed
signal twitch_connected(username: String)
signal twitch_disconnected
signal twitch_event_received(event_type: StringName, event_data: Dictionary, subscription_reward_id: String)
signal twitch_reward_revoked(subscription_reward_id: String)
signal twitch_auth_failed(reason: String)
signal twitch_rewards_fetched(rewards: Array)

signal background_type_changed(value: int)
signal background_image_changed(texture: Texture2D)
signal background_color_changed(color: Color)

signal model_triggers_changed()
signal states_changed()
signal state_frames_changed()
signal model_images_reloaded()
signal model_effects_changed()
signal model_emotion_effects_changed(emotion: Resource, effect: Resource, category: int)
signal items_changed()
signal item_selected(item: Item)
signal presets_changed()
signal rename_editing_started()
signal rename_editing_finished()
signal model_transform_values(position: Vector2, scale_value: float, rotation: float)
signal model_container_changed(container: Control)
