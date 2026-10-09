class_name TwitchEventSub
extends Node

const TAG := "[TwitchEventSub] "
const EVENTSUB_WS_URL := "wss://eventsub.wss.twitch.tv/ws"
const KEEPALIVE_GRACE_SECONDS := 10.0
const RECONNECT_MIN_DELAY := 1.0
const RECONNECT_MAX_DELAY := 60.0
const CREATE_RETRY_DELAY_SEC := 5.0
const CREATE_MAX_ATTEMPTS := 3

enum ConnectionState { IDLE, CONNECTING, CONNECTED, RECONNECT_PENDING }

var _api: TwitchApi
var _auth_headers: Callable
var _user_id: Callable
var _is_connected: Callable
var _event_keys: Dictionary = {}

var _ws_peer: WebSocketPeer
var state := ConnectionState.IDLE
var _session_id: String = ""
var _reconnect_url: String = ""
var _keepalive_timeout: float = 0.0
var _last_keepalive_time: float = 0.0
var _reconnect_attempts: int = 0

var _subs: Dictionary = {}
var _deleting_ids: Dictionary = {}
var _reconcile_in_flight := false

var _reconnect_timer: Timer
var _retry_timers: Dictionary = {}

func _ready() -> void:
	for key: StringName in TwitchEvent.EVENT_TYPES:
		_event_keys[TwitchEvent.EVENT_TYPES[key]] = key

func setup(api: TwitchApi, auth_headers: Callable, user_id: Callable, connection_check: Callable) -> void:
	_api = api
	_auth_headers = auth_headers
	_user_id = user_id
	_is_connected = connection_check

func _process(_delta: float) -> void:
	_process_eventsub_ws()

func _exit_tree() -> void:
	_shutdown_ws()
	_reconnect_timer = NodeUtil.free_timer(_reconnect_timer)
	_clear_retry_timers()

func start_session() -> void:
	_shutdown_ws()
	_ws_peer = WebSocketPeer.new()
	_last_keepalive_time = _now_sec()
	var err := _ws_peer.connect_to_url(EVENTSUB_WS_URL)
	if err != OK:
		push_error(TAG + "failed to connect to EventSub WebSocket: %s" % error_string(err))
		_reconnect()
		return
	state = ConnectionState.CONNECTING
	print(TAG + "connecting to EventSub WebSocket...")

func stop_session() -> void:
	_shutdown_ws()
	_subs.clear()
	_deleting_ids.clear()
	_reconcile_in_flight = false
	_clear_retry_timers()
	_reconnect_attempts = 0

func subscribe_event(event_type: StringName, reward_id: String = "") -> void:
	var key := _sub_key(event_type, reward_id)
	var sub: Dictionary = _subs.get(key, {})
	if sub.is_empty():
		sub = {"event_type": event_type, "reward_id": reward_id, "id": "", "refs": 0, "attempts": 0, "in_flight": false, "session": ""}
		_subs[key] = sub
	sub["refs"] = int(sub.get("refs", 0)) + 1
	_sync_subscriptions()

func unsubscribe_event(event_type: StringName, reward_id: String = "") -> void:
	var key := _sub_key(event_type, reward_id)
	var sub: Dictionary = _subs.get(key, {})
	if sub.is_empty():
		return
	var refs := int(sub.get("refs", 0)) - 1
	if refs > 0:
		sub["refs"] = refs
		return
	_subs.erase(key)
	_free_retry_timer(key)
	var sub_id := String(sub.get("id", ""))
	if not sub_id.is_empty():
		_deleting_ids[sub_id] = true
		_api.delete_eventsub_subscription(sub_id, _on_subscription_deleted)
	print(TAG + "unsubscribed from %s" % TwitchEvent.EVENT_TYPES.get(event_type, event_type))

func _on_subscription_deleted(sub_id: String) -> void:
	_deleting_ids.erase(sub_id)
	_sync_subscriptions()

func _now_sec() -> float:
	return Time.get_ticks_msec() / 1000.0

func _shutdown_ws() -> void:
	if _ws_peer != null:
		_ws_peer.close()
		_ws_peer = null
	state = ConnectionState.IDLE
	_session_id = ""
	_reconnect_url = ""
	_keepalive_timeout = 0.0
	_last_keepalive_time = 0.0

func _process_eventsub_ws() -> void:
	if _ws_peer == null:
		return
	_ws_peer.poll()
	match _ws_peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			_process_ws_open()
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			_process_ws_closed()

func _process_ws_open() -> void:
	if _ws_peer.get_available_packet_count() > 0:
		while _ws_peer.get_available_packet_count() > 0:
			_handle_ws_message(_ws_peer.get_packet().get_string_from_utf8())
		_last_keepalive_time = _now_sec()
	if state != ConnectionState.CONNECTED:
		state = ConnectionState.CONNECTED
		_reconnect_attempts = 0
		print(TAG + "EventSub WebSocket connected")
	elif _keepalive_timeout > 0.0 and _now_sec() - _last_keepalive_time > _keepalive_timeout:
		push_warning(TAG + "EventSub keepalive timeout (no message for %.1fs); reconnecting" % _keepalive_timeout)
		_ws_peer.close()
		_ws_peer = null
		_reconnect()

func _process_ws_closed() -> void:
	var code := _ws_peer.get_close_code()
	var reason := _ws_peer.get_close_reason()
	print(TAG + "EventSub WebSocket closed: %d - %s" % [code, reason])
	_ws_peer = null
	_session_id = ""
	if _is_connected.call() and (not _reconnect_url.is_empty() or not _subs.is_empty()):
		_reconnect()
	else:
		state = ConnectionState.IDLE

func _reconnect() -> void:
	_keepalive_timeout = 0.0
	_last_keepalive_time = _now_sec()
	if state == ConnectionState.RECONNECT_PENDING:
		return
	var delay := minf(RECONNECT_MAX_DELAY, RECONNECT_MIN_DELAY * pow(2.0, _reconnect_attempts))
	_reconnect_attempts += 1
	state = ConnectionState.RECONNECT_PENDING
	print(TAG + "scheduling EventSub reconnect in %.1fs (attempt %d)" % [delay, _reconnect_attempts])
	_reconnect_timer = NodeUtil.ensure_timer(self, _reconnect_timer, _attempt_reconnect, true)
	_reconnect_timer.start(delay)

func _attempt_reconnect() -> void:
	if state != ConnectionState.RECONNECT_PENDING:
		return
	if not _is_connected.call():
		state = ConnectionState.IDLE
		return
	if _reconnect_url.is_empty():
		start_session()
		return
	var url := _reconnect_url
	_reconnect_url = ""
	_ws_peer = WebSocketPeer.new()
	var err := _ws_peer.connect_to_url(url)
	if err != OK:
		push_error(TAG + "failed to reconnect to EventSub: %s" % error_string(err))
		start_session()
		return
	state = ConnectionState.CONNECTING
	print(TAG + "reconnecting to EventSub...")

func _handle_ws_message(message: String) -> void:
	var json: Variant = JSON.parse_string(message)
	if json == null:
		return
	var metadata: Dictionary = json.get("metadata", {})
	var payload: Dictionary = json.get("payload", {})
	var message_type: String = metadata.get("message_type", "")
	match message_type:
		"session_welcome":
			_handle_session_welcome(payload)
		"notification":
			_handle_notification(payload)
		"session_reconnect":
			_handle_session_reconnect(payload)
		"revocation":
			_handle_revocation(payload)
		"session_keepalive":
			pass

func _handle_session_welcome(payload: Dictionary) -> void:
	var session: Dictionary = payload.get("session", {})
	_session_id = session.get("id", "")
	_keepalive_timeout = float(session.get("keepalive_timeout_seconds", 30.0)) + KEEPALIVE_GRACE_SECONDS
	_last_keepalive_time = _now_sec()
	_reconnect_url = ""
	print(TAG + "EventSub session established: %s" % _session_id)
	for key: String in _subs:
		_subs[key]["id"] = ""
		_subs[key]["attempts"] = 0
	_reconcile_subscriptions()

func _reconcile_subscriptions() -> void:
	if _reconcile_in_flight:
		return
	if _session_id.is_empty() or _subs.is_empty():
		_sync_subscriptions()
		return
	_reconcile_in_flight = true
	_api.fetch_eventsub_subscriptions(_on_subscriptions_fetched)

func _on_subscriptions_fetched(remote_subs: Array) -> void:
	_reconcile_in_flight = false
	if _session_id.is_empty():
		return
	for key: String in _subs:
		var sub: Dictionary = _subs[key]
		if not String(sub.get("id", "")).is_empty():
			continue
		var remote_id := _matching_remote_id(sub, remote_subs)
		if remote_id.is_empty():
			continue
		sub["id"] = remote_id
		print(TAG + "adopted existing subscription for %s (%s)" % [TwitchEvent.EVENT_TYPES.get(sub.get("event_type", &""), sub.get("event_type", &"")), remote_id])
	_sync_subscriptions()

func _matching_remote_id(sub: Dictionary, remote_subs: Array) -> String:
	var event_type: StringName = sub.get("event_type", &"")
	var sub_type := String(TwitchEvent.EVENT_TYPES.get(event_type, ""))
	if sub_type.is_empty():
		return ""
	var reward_id := String(sub.get("reward_id", ""))
	var broadcaster_id := String(_user_id.call())
	for remote: Variant in remote_subs:
		if not (remote is Dictionary):
			continue
		var remote_dict: Dictionary = remote
		if String(remote_dict.get("type", "")) != sub_type:
			continue
		if String(remote_dict.get("status", "")) != "enabled":
			continue
		var transport: Dictionary = remote_dict.get("transport", {})
		if String(transport.get("method", "")) != "websocket":
			continue
		var condition: Dictionary = remote_dict.get("condition", {})
		if String(condition.get("broadcaster_user_id", "")) != broadcaster_id:
			continue
		if event_type == &"channel_points" and String(condition.get("reward_id", "")) != reward_id:
			continue
		return String(remote_dict.get("id", ""))
	return ""

func _handle_notification(payload: Dictionary) -> void:
	var subscription: Dictionary = payload.get("subscription", {})
	var event: Dictionary = payload.get("event", {})
	var key: StringName = _event_keys.get(subscription.get("type", ""), &"")
	if key == &"":
		return
	var condition: Dictionary = subscription.get("condition", {})
	SignalBus.twitch_event_received.emit(key, event, String(condition.get("reward_id", "")))

func _handle_session_reconnect(payload: Dictionary) -> void:
	var session: Dictionary = payload.get("session", {})
	_reconnect_url = session.get("reconnect_url", "")
	print(TAG + "received reconnect signal, URL: %s" % _reconnect_url)

func _handle_revocation(payload: Dictionary) -> void:
	var subscription: Dictionary = payload.get("subscription", {})
	var sub_type: String = subscription.get("type", "")
	var sub_id := String(subscription.get("id", ""))
	var status: String = subscription.get("status", "")
	push_warning(TAG + "subscription revoked: %s (status: %s)" % [sub_type, status])
	var condition: Dictionary = subscription.get("condition", {})
	var revoked_reward := String(condition.get("reward_id", ""))
	for key: String in _subs.keys():
		if String(_subs[key].get("id", "")) == sub_id:
			_subs.erase(key)
			_free_retry_timer(key)
	if _event_keys.get(sub_type, &"") == &"channel_points" and not revoked_reward.is_empty():
		SignalBus.twitch_reward_revoked.emit(revoked_reward)

static func _sub_key(event_type: StringName, reward_id: String) -> String:
	return String(event_type) if reward_id.is_empty() else "%s|%s" % [event_type, reward_id]

func _sync_subscriptions() -> void:
	if not _is_connected.call():
		return
	if _session_id.is_empty():
		if state == ConnectionState.IDLE and not _subs.is_empty():
			start_session()
		return
	for key: String in _subs:
		if String(_subs[key].get("id", "")).is_empty():
			_create_eventsub_subscription(key)

func _create_eventsub_subscription(key: String) -> void:
	var sub: Dictionary = _subs.get(key, {})
	if sub.is_empty() or bool(sub.get("in_flight", false)):
		return
	var event_type: StringName = sub["event_type"]
	if not TwitchEvent.EVENT_TYPES.has(event_type):
		push_error(TAG + "unknown event type: %s" % event_type)
		return
	sub["attempts"] = int(sub.get("attempts", 0)) + 1
	sub["in_flight"] = true
	sub["session"] = _session_id
	var sub_type := String(TwitchEvent.EVENT_TYPES[event_type])
	var reward_id := String(sub.get("reward_id", ""))
	_api.create_eventsub_subscription(_subscription_body(event_type, reward_id), sub_type, func(sub_id: String, response_code: int, _error_message: String) -> void:
		if not _subs.has(key):
			return
		var current: Dictionary = _subs[key]
		current["in_flight"] = false
		if _session_id != String(current.get("session", "")):
			print(TAG + "discarding stale session response for %s; resyncing" % sub_type)
			_sync_subscriptions()
			return
		if sub_id.is_empty():
			_on_create_failed(key, sub_type)
			return
		if response_code == 409 and _deleting_ids.has(sub_id):
			print(TAG + "subscription for %s is being deleted; retrying later" % sub_type)
			_on_create_failed(key, sub_type)
			return
		current["id"] = sub_id
		if response_code == 409:
			print(TAG + "subscription already exists for %s; reusing %s" % [sub_type, sub_id])
		else:
			print(TAG + "subscribed to %s (reward: %s)" % [sub_type, reward_id if not reward_id.is_empty() else "any"])
	)

func _on_create_failed(key: String, sub_type: String) -> void:
	var sub: Dictionary = _subs.get(key, {})
	if sub.is_empty():
		return
	var attempts := int(sub.get("attempts", 0))
	if attempts >= CREATE_MAX_ATTEMPTS:
		push_error(TAG + "gave up creating subscription for %s after %d attempts; re-enable the trigger to retry" % [sub_type, attempts])
		_free_retry_timer(key)
		return
	var delay := minf(RECONNECT_MAX_DELAY, CREATE_RETRY_DELAY_SEC * pow(2.0, attempts - 1))
	var timer: Timer = _retry_timers.get(key)
	_retry_timers[key] = NodeUtil.ensure_timer(self, timer, _sync_subscriptions, true)
	_retry_timers[key].start(delay)
	print(TAG + "retrying failed subscription for %s in %.1fs (%d/%d)" % [sub_type, delay, attempts, CREATE_MAX_ATTEMPTS])

func _free_retry_timer(key: String) -> void:
	var timer: Timer = _retry_timers.get(key)
	if timer != null:
		NodeUtil.free_timer(timer)
	_retry_timers.erase(key)

func _clear_retry_timers() -> void:
	for key: String in _retry_timers.keys():
		var timer: Timer = _retry_timers[key]
		if timer != null:
			NodeUtil.free_timer(timer)
	_retry_timers.clear()

func _subscription_body(event_type: StringName, reward_id: String) -> Dictionary:
	var broadcaster_id: String = _user_id.call()
	var version := "1"
	var condition: Dictionary = {"broadcaster_user_id": broadcaster_id}
	if event_type == &"follow":
		version = "2"
		condition["moderator_user_id"] = broadcaster_id
	elif event_type == &"channel_points" and not reward_id.is_empty():
		condition["reward_id"] = reward_id
	return {
		"type": TwitchEvent.EVENT_TYPES[event_type],
		"version": version,
		"condition": condition,
		"transport": {"method": "websocket", "session_id": _session_id},
	}
