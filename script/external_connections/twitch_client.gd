extends Node

const TAG := "[TwitchClient] "
const CLIENT_ID := "23a387zabsw54epn13osbt6pv1o7cn"
const MAX_AUTO_RECOVERS := 3

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
var _refresh_token: String = ""
var _code_verifier := ""
var _refreshing := false
var _auto_recover_attempts := 0
var _auth := TwitchAuthServer.new()
var _api: TwitchApi
var _eventsub: TwitchEventSub

func _ready() -> void:
	_auth.code_received.connect(_on_code_received)
	_auth.authorization_failed.connect(_on_auth_page_failed)
	_api = TwitchApi.new()
	add_child(_api)
	_api.setup(_auth_headers, CLIENT_ID)
	_api.token_expired.connect(_on_token_expired)
	_eventsub = TwitchEventSub.new()
	add_child(_eventsub)
	_eventsub.setup(_api, _auth_headers, _get_user_id, _is_connected)
	var tokens := TwitchTokenStore.load_tokens()
	var saved_token: String = tokens.get(TwitchTokenStore.KEY_ACCESS, "")
	if not saved_token.is_empty():
		_access_token = saved_token
		_refresh_token = String(tokens.get(TwitchTokenStore.KEY_REFRESH, ""))
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
	_code_verifier = TwitchAuthServer.generate_code_verifier()
	var url := _auth.begin(CLIENT_ID, REQUIRED_SCOPES, TwitchAuthServer.code_challenge(_code_verifier))
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
	_refresh_token = ""
	_auth.reset()
	_eventsub.stop_session()
	TwitchTokenStore.clear_token()
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

func _on_code_received(code: String) -> void:
	if state != ConnectionState.AUTHENTICATING:
		return
	print(TAG + "received authorization code; exchanging for tokens")
	_api.exchange_authorization_code(code, _auth.redirect_uri(), _code_verifier, _on_code_exchanged)

func _on_code_exchanged(new_access_token: String, new_refresh_token: String, error_message: String) -> void:
	if state != ConnectionState.AUTHENTICATING:
		return
	if not error_message.is_empty() or new_access_token.is_empty():
		push_warning(TAG + "authorization failed: " + error_message)
		_auth.finish_with_page("YAPS - Twitch", "Authorization failed: %s" % error_message, "#e57373")
		state = ConnectionState.DISCONNECTED
		SignalBus.twitch_auth_failed.emit(error_message)
		return
	_access_token = new_access_token
	_refresh_token = new_refresh_token
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
		TwitchTokenStore.clear_token()
		SignalBus.twitch_auth_failed.emit("token validation returned no user id")
		return
	user_id = validated_user_id
	username = validated_username
	state = ConnectionState.CONNECTED
	_auto_recover_attempts = 0
	Settings.settings.twitch_user_id = user_id
	Settings.settings.twitch_username = username
	if not TwitchTokenStore.save_tokens(_access_token, _refresh_token):
		push_warning(TAG + "could not persist access token")
	print(TAG + "authenticated as %s" % username)
	_eventsub.start_session()
	SignalBus.twitch_connected.emit(username)
	fetch_channel_redeems()

func _on_token_expired(_context: String) -> void:
	if state == ConnectionState.DISCONNECTED or _refreshing:
		return
	if _refresh_token.is_empty():
		disconnect_twitch()
		return
	_refreshing = true
	print(TAG + "access token expired; attempting refresh")
	_api.refresh_access_token(_refresh_token, _on_token_refreshed)

func _on_token_refreshed(new_access_token: String, new_refresh_token: String, error_message: String) -> void:
	_refreshing = false
	if state == ConnectionState.DISCONNECTED:
		return
	if not error_message.is_empty() or new_access_token.is_empty():
		push_warning(TAG + "token refresh failed: %s" % error_message)
		disconnect_twitch()
		SignalBus.twitch_auth_failed.emit("token refresh failed: %s" % error_message)
		return
	_access_token = new_access_token
	if not new_refresh_token.is_empty():
		_refresh_token = new_refresh_token
	_auto_recover_attempts += 1
	if _auto_recover_attempts > MAX_AUTO_RECOVERS:
		push_warning(TAG + "giving up after %d failed re-authentications" % _auto_recover_attempts)
		disconnect_twitch()
		return
	_api.validate_token(_on_token_validated)
