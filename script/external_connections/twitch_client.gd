extends Node

const TAG := "[TwitchClient] "
const CLIENT_ID := "23a387zabsw54epn13osbt6pv1o7cn"
const OAUTH_AUTHORIZE_URL := "https://id.twitch.tv/oauth2/authorize"
const REDIRECT_URI := "http://localhost:%d/callback" % TwitchAuthServer.OAUTH_PORT

const REQUIRED_SCOPES: PackedStringArray = [
	"moderator:read:followers",
	"channel:read:subscriptions",
	"channel:read:redemptions",
	"bits:read",
]

enum ConnectionState { DISCONNECTED, AUTHENTICATING, CONNECTED }

var state: ConnectionState = ConnectionState.DISCONNECTED
var username: String = ""
var user_id: String = ""
var channel_rewards: Array[Dictionary] = []

var _access_token: String = ""
var _auth := TwitchAuthServer.new()
var _api: TwitchApi
var _eventsub: TwitchEventSub

func _ready() -> void:
	_auth.token_received.connect(_on_token_received)
	_auth.authorization_failed.connect(_on_auth_page_failed)
	_api = TwitchApi.new()
	add_child(_api)
	_api.setup(_auth_headers)
	_api.token_expired.connect(disconnect_twitch)
	_eventsub = TwitchEventSub.new()
	add_child(_eventsub)
	_eventsub.setup(_api, _auth_headers, _get_user_id, _is_connected)
	var saved_token := TwitchTokenStore.load_token()
	if not saved_token.is_empty():
		_access_token = saved_token
		username = Settings.settings.twitch_username
		user_id = Settings.settings.twitch_user_id
		state = ConnectionState.AUTHENTICATING
		_api.validate_token(_on_token_validated)

func _process(_delta: float) -> void:
	_auth.poll()

func _exit_tree() -> void:
	_eventsub.stop_session()
	_auth.stop()

func start_auth() -> void:
	var url := _auth.begin(CLIENT_ID, REDIRECT_URI, REQUIRED_SCOPES)
	if url.is_empty():
		return
	state = ConnectionState.AUTHENTICATING
	OS.shell_open(url)
	print(TAG + "opened browser for authentication")

func disconnect_twitch() -> void:
	state = ConnectionState.DISCONNECTED
	username = ""
	user_id = ""
	_access_token = ""
	_auth.reset()
	_eventsub.stop_session()
	SignalBus.twitch_disconnected.emit()
	print(TAG + "disconnected")

func fetch_channel_redeems() -> void:
	if state != ConnectionState.CONNECTED or user_id.is_empty():
		push_warning(TAG + "not connected; cannot fetch channel rewards")
		return
	_api.fetch_channel_redeems(user_id, func(rewards: Array[Dictionary]) -> void:
		channel_rewards = rewards
		SignalBus.twitch_rewards_fetched.emit(channel_rewards)
		print(TAG + "fetched %d channel rewards" % channel_rewards.size())
	)

func subscribe_event(event_type: StringName, reward_id: String = "") -> void:
	_eventsub.subscribe_event(event_type, reward_id)

func unsubscribe_event(event_type: StringName, reward_id: String = "") -> void:
	_eventsub.unsubscribe_event(event_type, reward_id)

func _auth_headers() -> PackedStringArray:
	return [
		"Authorization: Bearer %s" % _access_token,
		"Client-Id: %s" % CLIENT_ID,
	]

func _get_user_id() -> String:
	return user_id

func _is_connected() -> bool:
	return state == ConnectionState.CONNECTED

func _on_token_received(token: String) -> void:
	_access_token = token
	TwitchTokenStore.save_token(token)
	_auth.finish_with_page("Authentication success", "You can now return to YAPS.", "#81c784")
	_api.validate_token(_on_token_validated)

func _on_auth_page_failed(reason: String) -> void:
	state = ConnectionState.DISCONNECTED
	push_warning(TAG + "authorization failed: " + reason)
	_auth.finish_with_page("YAPS - Twitch", "Authorization failed: %s" % reason, "#e57373")
	SignalBus.twitch_auth_failed.emit(reason)

func _on_token_validated(validated_user_id: String, validated_username: String) -> void:
	if validated_user_id.is_empty():
		state = ConnectionState.DISCONNECTED
		push_warning(TAG + "token validation returned no user id")
		SignalBus.twitch_auth_failed.emit("token validation returned no user id")
		return
	user_id = validated_user_id
	username = validated_username
	state = ConnectionState.CONNECTED
	Settings.settings.twitch_user_id = user_id
	Settings.settings.twitch_username = username
	SignalBus.twitch_connected.emit(username)
	print(TAG + "authenticated as %s" % username)
	_eventsub.start_session()
	fetch_channel_redeems()