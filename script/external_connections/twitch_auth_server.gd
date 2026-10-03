class_name TwitchAuthServer
extends RefCounted

const TAG := "[TwitchAuth] "
const OAUTH_PORT := 7170
const CALLBACK_PAGE_PATH := "res://assets/web/callback_page.html"
const REDIRECT_PAGE_PATH := "res://assets/web/implicit_redirect.html"
const MAX_REQUEST_BUFFER := 16 * 1024
const STREAM_TIMEOUT_SEC := 10.0

signal token_received(access_token: String)
signal authorization_failed(reason: String)

var _server: TCPServer
var _stream: StreamPeerTCP
var _active := false
var _buffer := ""
var _stream_since_msec := 0
var state := ""

func begin(client_id: String, redirect_uri: String, scopes: PackedStringArray) -> String:
	stop()
	if not _start_server():
		authorization_failed.emit("OAuth server could not listen on port %d (already in use?)" % OAUTH_PORT)
		return ""
	state = generate_state()
	var joined_scopes := "+".join(scopes)
	return "%s?response_type=token&client_id=%s&redirect_uri=%s&scope=%s&state=%s&force_verify=true" % [
		TwitchClient.OAUTH_AUTHORIZE_URL,
		client_id,
		redirect_uri.uri_encode(),
		joined_scopes,
		state,
	]

func reset() -> void:
	state = ""

func poll() -> void:
	if not _active:
		return
	_accept_connection()
	if _stream == null:
		return
	if _stream_timed_out():
		push_warning(TAG + "connection idle for %.0fs; dropping" % STREAM_TIMEOUT_SEC)
		_drop_stream()
		return
	if not _read_request():
		return
	_route_request()

func _accept_connection() -> void:
	if _server != null and _server.is_connection_available() and _stream == null:
		_stream = _server.take_connection()
		_buffer = ""
		_stream_since_msec = Time.get_ticks_msec()

func _stream_timed_out() -> bool:
	return Time.get_ticks_msec() - _stream_since_msec > int(STREAM_TIMEOUT_SEC * 1000.0)

func _drop_stream() -> void:
	if _stream != null:
		_stream.disconnect_from_host()
	_stream = null
	_buffer = ""

func _read_request() -> bool:
	var available := _stream.get_available_bytes()
	if available <= 0:
		return false
	_buffer += _stream.get_utf8_string(available)
	if _buffer.length() > MAX_REQUEST_BUFFER:
		push_warning(TAG + "request too large; dropping connection")
		_drop_stream()
		return false
	return _buffer.contains("\r\n\r\n")

func _route_request() -> void:
	var request := _buffer
	_buffer = ""
	var path := _extract_path(request)
	if path.begins_with("/token"):
		handle_token(path)
		return
	var error := extract_query_param(path, "error")
	if not error.is_empty():
		var desc := extract_query_param(path, "error_description")
		_fail(desc if not desc.is_empty() else error, true)
		return
	serve_redirect_page()

func _extract_path(request: String) -> String:
	var first_line := request.get_slice("\r\n", 0)
	if first_line.begins_with("GET "):
		var parts := first_line.split(" ")
		if parts.size() >= 2:
			return parts[1]
	return ""

func stop() -> void:
	_active = false
	_drop_stream()
	if _server != null:
		_server.stop()
		_server = null

func finish_with_page(title: String, message: String, color: String) -> void:
	serve_page(title, message, color)
	stop()

func handle_token(path: String) -> void:
	var callback_state := extract_query_param(path, "state")
	if callback_state.is_empty() or callback_state != state:
		_fail("Invalid state parameter.", true)
		return
	state = ""
	var token := extract_query_param(path, "access_token")
	if token.is_empty():
		_fail("Access token not found.", true)
		return
	token_received.emit(token)

func serve_page(title: String, message: String, color: String) -> void:
	var html := FileAccess.get_file_as_string(CALLBACK_PAGE_PATH)
	html = html.replace("{{COLOR}}", color).replace("{{TITLE}}", title).replace("{{MESSAGE}}", message)
	_send_http_response(_http_html_response(html))

func serve_redirect_page() -> void:
	_send_http_response(_http_html_response(FileAccess.get_file_as_string(REDIRECT_PAGE_PATH)))

func _http_html_response(html: String) -> String:
	return "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [html.to_utf8_buffer().size(), html]

func _fail(reason: String, serve_error_page: bool) -> void:
	if serve_error_page:
		serve_page("YAPS - Twitch", "Authorization failed: %s" % reason, "#e57373")
	stop()
	authorization_failed.emit(reason)

func _start_server() -> bool:
	_server = TCPServer.new()
	var err := _server.listen(OAUTH_PORT, "127.0.0.1")
	if err != OK:
		push_error(TAG + "failed to start OAuth server on port %d: %s" % [OAUTH_PORT, error_string(err)])
		_server = null
		return false
	_active = true
	print(TAG + "OAuth server started on port %d" % OAUTH_PORT)
	return true

func _send_http_response(response: String) -> void:
	if _stream == null:
		return
	_stream.put_data(response.to_utf8_buffer())
	_stream = null

static func generate_state() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func extract_query_param(path: String, param: String) -> String:
	if not "?" in path:
		return ""
	var query := path.get_slice("?", 1)
	for entry in query.split("&"):
		var eq := entry.find("=")
		if eq <= 0:
			continue
		if entry.substr(0, eq) == param:
			return entry.substr(eq + 1).uri_decode()
	return ""
