extends VBoxContainer

@export_category("Connection")
@export var connect_button: Button
@export var connected_container: VBoxContainer
@export var username_label: Label
@export var disconnect_button: Button
@export var refresh_rewards_button: Button
@export var rewards_count_label: Label
@export var auth_status_label: Label

func _ready() -> void:
	_populate_ui()
	SignalBus.twitch_connected.connect(_on_connection_changed)
	SignalBus.twitch_disconnected.connect(_on_connection_changed)
	SignalBus.twitch_auth_failed.connect(_on_twitch_auth_failed)
	SignalBus.twitch_rewards_fetched.connect(_on_rewards_fetched)
	NodeUtil.attach_locale(self, _populate_ui)
	connect_button.pressed.connect(_on_connect_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	if refresh_rewards_button != null:
		refresh_rewards_button.pressed.connect(_on_refresh_rewards_pressed)
	_update_rewards_ui()

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"twitch_connected", _on_connection_changed)
	NodeUtil.safe_disconnect(SignalBus, &"twitch_disconnected", _on_connection_changed)
	NodeUtil.safe_disconnect(SignalBus, &"twitch_auth_failed", _on_twitch_auth_failed)
	NodeUtil.safe_disconnect(SignalBus, &"twitch_rewards_fetched", _on_rewards_fetched)

func _populate_ui() -> void:
	_update_connection_state()
	_update_rewards_ui()

func _on_connect_pressed() -> void:
	TwitchClient.start_auth()

func _on_disconnect_pressed() -> void:
	TwitchClient.disconnect_twitch()

func _on_refresh_rewards_pressed() -> void:
	TwitchClient.fetch_channel_redeems()

func _on_rewards_fetched(_rewards: Array) -> void:
	_update_rewards_ui()

func _on_connection_changed(_username: String = "") -> void:
	_clear_auth_error()
	_update_connection_state()
	_update_rewards_ui()

func _on_twitch_auth_failed(reason: String) -> void:
	if auth_status_label == null:
		return
	auth_status_label.text = tr(&"TWITCH_AUTH_ERROR") % reason
	auth_status_label.show()

func _clear_auth_error() -> void:
	if auth_status_label != null:
		auth_status_label.text = ""
		auth_status_label.hide()

func _update_connection_state() -> void:
	var connected := TwitchClient.state == TwitchClient.ConnectionState.CONNECTED
	connect_button.visible = not connected
	connected_container.visible = connected
	if connected:
		username_label.text = TwitchClient.username

func _update_rewards_ui() -> void:
	if refresh_rewards_button == null or rewards_count_label == null:
		return
	refresh_rewards_button.disabled = TwitchClient.state != TwitchClient.ConnectionState.CONNECTED
	rewards_count_label.text = tr(&"TWITCH_REWARDS_COUNT") % TwitchClient.channel_rewards.size()
