class_name TwitchAuthServer
extends RefCounted

const TAG := "[TwitchAuth] "
const OAUTH_AUTHORIZE_URL := "https://id.twitch.tv/oauth2/authorize"
const OAUTH_PORT := 7170
const OAUTH_PORT_ATTEMPTS := 5
const MAX_REQUEST_BUFFER := 16 * 1024
const STREAM_TIMEOUT_SEC := 10.0
const MAX_PENDING_STREAMS := 8
const RESULT_PAGE_TEMPLATE := "<!doctype html><html><head><meta charset=\"utf-8\"><title>%s</title><style>body{background:#2c2b2d;color:#f7dfd1;font-family:system-ui,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}div{background:#48444a;padding:24px 32px;border-radius:12px;text-align:center;max-width:420px}h2{margin:0 0 8px;font-size:22px}</style></head><body><div><h2 style=\"color:%s\">%s</h2><p>%s</p></div></body></html>"

signal code_received(code: String)
signal authorization_failed(reason: String)

enum PollResult { PENDING, COMPLETE, DROP }

var port := OAUTH_PORT

var _server: TCPServer
var _streams: Array[Dictionary] = []
var _pending_stream: StreamPeerTCP
var _active := false
var state := ""

func redirect_uri() -> String:
	return "http://localhost:%d/callback" % port

func begin(client_id: String, scopes: PackedStringArray, challenge: String) -> String:
	stop()
	if not _start_server():
		authorization_failed.emit("OAuth server could not listen on port %d (already in use?)" % OAUTH_PORT)
		return ""
	state = generate_state()
	return "%s?response_type=code&client_id=%s&redirect_uri=%s&scope=%s&state=%s&code_challenge=%s&code_challenge_method=S256&force_verify=true" % [
		OAUTH_AUTHORIZE_URL,
		client_id,
		redirect_uri().uri_encode(),
		" ".join(scopes).uri_encode(),
		state,
		challenge,
	]

func reset() -> void:
	state = ""

func poll() -> void:
	if not _active:
		return
	_accept_connections()
	var index := _streams.size() - 1
	while index >= 0:
		var entry: Dictionary = _streams[index]
		var outcome := _poll_stream(entry)
		if outcome == PollResult.COMPLETE:
			_streams.remove_at(index)
			_route_request(entry.buffer, entry.stream)
			return
		if outcome == PollResult.DROP:
			_streams.remove_at(index)
			_drop_stream(entry.stream)
		index -= 1

func _accept_connections() -> void:
	if _server == null:
		return
	while _server.is_connection_available() and _streams.size() < MAX_PENDING_STREAMS:
		_streams.append({
			"stream": _server.take_connection(),
			"since": Time.get_ticks_msec(),
			"buffer": "",
		})

func _poll_stream(entry: Dictionary) -> PollResult:
	if Time.get_ticks_msec() - int(entry.since) > int(STREAM_TIMEOUT_SEC * 1000.0):
		push_warning(TAG + "connection idle for %.0fs; dropping" % STREAM_TIMEOUT_SEC)
		return PollResult.DROP
	var stream: StreamPeerTCP = entry.stream
	var available := stream.get_available_bytes()
	if available <= 0:
		return PollResult.PENDING
	entry.buffer = String(entry.buffer) + stream.get_utf8_string(available)
	if entry.buffer.length() > MAX_REQUEST_BUFFER:
		push_warning(TAG + "request too large; dropping connection")
		return PollResult.DROP
	if not entry.buffer.contains("\r\n\r\n"):
		return PollResult.PENDING
	return PollResult.COMPLETE

func _extract_path(request: String) -> String:
	var first_line := request.get_slice("\r\n", 0)
	if first_line.begins_with("GET "):
		var parts := first_line.split(" ")
		if parts.size() >= 2:
			return parts[1]
	return ""

func stop() -> void:
	_active = false
	_drop_stream(_pending_stream)
	_pending_stream = null
	for entry: Dictionary in _streams:
		_drop_stream(entry.stream)
	_streams.clear()
	if _server != null:
		_server.stop()
		_server = null

func finish_with_page(title: String, message: String, color: String) -> void:
	serve_page(title, message, color, _pending_stream)
	stop()

func handle_code(path: String, stream: StreamPeerTCP) -> void:
	var callback_state := extract_query_param(path, "state")
	if callback_state.is_empty() or callback_state != state:
		if state.is_empty() and _pending_stream != null:
			_drop_stream(stream)
			return
		_fail("Invalid state parameter.", stream)
		return
	state = ""
	var code := extract_query_param(path, "code")
	if code.is_empty():
		_fail("Authorization code not found.", stream)
		return
	_pending_stream = stream
	code_received.emit(code)

func serve_page(title: String, message: String, color: String, stream: StreamPeerTCP) -> void:
	var html := RESULT_PAGE_TEMPLATE % [title.xml_escape(), color, title.xml_escape(), message.xml_escape()]
	_send_http_response(stream, _http_html_response(html))

func _http_html_response(html: String) -> String:
	return "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [html.to_utf8_buffer().size(), html]

func _fail(reason: String, stream: StreamPeerTCP = null) -> void:
	if stream != null:
		serve_page("YAPS - Twitch", "Authorization failed: %s" % reason, "#e57373", stream)
	stop()
	authorization_failed.emit(reason)

func _start_server() -> bool:
	_server = TCPServer.new()
	var err := OK
	for attempt in OAUTH_PORT_ATTEMPTS:
		var candidate := OAUTH_PORT + attempt
		err = _server.listen(candidate, "127.0.0.1")
		if err == OK:
			port = candidate
			_active = true
			print(TAG + "OAuth server started on port %d" % port)
			return true
	push_error(TAG + "failed to start OAuth server on ports %d-%d: %s" % [OAUTH_PORT, OAUTH_PORT + OAUTH_PORT_ATTEMPTS - 1, error_string(err)])
	_server = null
	return false

func _route_request(request: String, stream: StreamPeerTCP) -> void:
	var path := _extract_path(request)
	if path.begins_with("/callback"):
		var error := extract_query_param(path, "error")
		if not error.is_empty():
			var desc := extract_query_param(path, "error_description")
			_fail(desc if not desc.is_empty() else error, stream)
			return
		handle_code(path, stream)
		return
	_drop_stream(stream)

func _drop_stream(stream: StreamPeerTCP) -> void:
	if stream != null:
		stream.disconnect_from_host()

func _send_http_response(stream: StreamPeerTCP, response: String) -> void:
	if stream == null:
		return
	var status := stream.get_status()
	if status != StreamPeerTCP.STATUS_CONNECTED and status != StreamPeerTCP.STATUS_CONNECTING:
		return
	stream.put_data(response.to_utf8_buffer())
	_drop_stream(stream)

static func generate_state() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func generate_code_verifier() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()

static func code_challenge(verifier: String) -> String:
	var encoded := Marshalls.raw_to_base64(verifier.sha256_buffer())
	while encoded.ends_with("="):
		encoded = encoded.left(encoded.length() - 1)
	return encoded.replace("+", "-").replace("/", "_")

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
