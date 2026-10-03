class_name TwitchApi
extends Node

signal token_expired

const TAG := "[TwitchApi] "
const HELIX_API_URL := "https://api.twitch.tv/helix"
const ONESHOT_TIMEOUT_SEC := 10

var _auth_headers: Callable

func setup(auth_headers: Callable) -> void:
	_auth_headers = auth_headers

func validate_token(on_done: Callable) -> void:
	_oneshot_request(HELIX_API_URL + "/users", _auth_headers.call(), HTTPClient.METHOD_GET, "", func(result: int, response_code: int, response_body: PackedByteArray) -> void:
		var user_id := ""
		var login := ""
		if not _request_failed(result, response_code, "validate token request"):
			var json: Variant = _parse_json(response_body)
			if json != null and json.has("data") and (json.data as Array).size() > 0:
				var user: Dictionary = json.data[0]
				user_id = String(user.get("id", ""))
				login = String(user.get("login", ""))
			else:
				push_error(TAG + "invalid response from /helix/users")
		on_done.call(user_id, login)
	)

func fetch_channel_redeems(user_id: String, on_done: Callable) -> void:
	var url := HELIX_API_URL + "/channel_points/custom_rewards?broadcaster_id=%s" % user_id
	_oneshot_request(url, _auth_headers.call(), HTTPClient.METHOD_GET, "", func(result: int, response_code: int, response_body: PackedByteArray) -> void:
		if _request_failed(result, response_code, "fetch rewards request"):
			return
		var json: Variant = _parse_json(response_body)
		if json == null or not json.has("data"):
			push_error(TAG + "invalid response from /channel_points/custom_rewards")
			return
		var rewards: Array[Dictionary] = []
		for reward: Dictionary in json.data:
			rewards.append({
				"id": String(reward.get("id", "")),
				"title": String(reward.get("title", "")),
			})
		on_done.call(rewards)
	)

func create_eventsub_subscription(body: Dictionary, sub_type: String, on_done: Callable) -> void:
	var headers: PackedStringArray = _auth_headers.call()
	headers.append("Content-Type: application/json")
	_oneshot_request(HELIX_API_URL + "/eventsub/subscriptions", headers, HTTPClient.METHOD_POST, JSON.stringify(body), func(result: int, response_code: int, response_body: PackedByteArray) -> void:
		var sub_id := ""
		if result != HTTPRequest.RESULT_SUCCESS:
			push_error(TAG + "failed to create EventSub subscription for %s" % sub_type)
		elif response_code == 401:
			_token_expired("EventSub subscription for %s" % sub_type)
		elif response_code != 202:
			push_error(TAG + "EventSub subscription failed for %s: %d - %s" % [sub_type, response_code, _response_error_message(response_body)])
		else:
			sub_id = _extract_subscription_id(response_body)
		on_done.call(sub_id)
	)

func delete_eventsub_subscription(sub_id: String) -> void:
	var url := HELIX_API_URL + "/eventsub/subscriptions?id=%s" % sub_id.uri_encode()
	_oneshot_request(url, _auth_headers.call(), HTTPClient.METHOD_DELETE, "", func(result: int, response_code: int, _response_body: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS:
			push_warning(TAG + "failed to delete EventSub subscription %s (result %d)" % [sub_id, result])
		elif response_code == 401:
			_token_expired("EventSub subscription deletion")
		elif response_code != 204:
			push_warning(TAG + "failed to delete EventSub subscription %s (code %d)" % [sub_id, response_code])
		else:
			print(TAG + "deleted EventSub subscription %s" % sub_id)
	)

func _oneshot_request(url: String, headers: PackedStringArray, method: int, body: String, on_done: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = ONESHOT_TIMEOUT_SEC
	add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, response_body: PackedByteArray) -> void:
		http.queue_free()
		on_done.call(result, response_code, response_body)
	)
	var err := http.request(url, headers, method, body)
	if err != OK:
		push_error(TAG + "failed to send request to %s: %s" % [url, error_string(err)])
		http.queue_free()
		on_done.call(HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedByteArray())

func _request_failed(result: int, response_code: int, context: String) -> bool:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error(TAG + "%s failed with result: %d" % [context, result])
		return true
	if response_code == 401:
		_token_expired(context)
		return true
	if response_code != 200:
		push_error(TAG + "%s failed with code: %d" % [context, response_code])
		return true
	return false

func _token_expired(context: String) -> void:
	push_warning(TAG + "access token expired during %s" % context)
	token_expired.emit()

func _parse_json(body: PackedByteArray) -> Variant:
	return JSON.parse_string(body.get_string_from_utf8())

func _response_error_message(response_body: PackedByteArray) -> String:
	var json: Variant = _parse_json(response_body)
	if json != null and json.has("message"):
		return String(json.message)
	return ""

func _extract_subscription_id(response_body: PackedByteArray) -> String:
	var json: Variant = _parse_json(response_body)
	if json is Dictionary and json.has("data") and (json.data as Array).size() > 0:
		return String((json.data as Array)[0].get("id", ""))
	return ""
