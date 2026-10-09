extends Node

const TAG := "[WebSocketServer] "
const DEFAULT_PORT := 19190
const DEFAULT_BIND_ADDRESS := "127.0.0.1"

var port: int = DEFAULT_PORT

var _peer: WebSocketMultiplayerPeer
var _actions: Dictionary = {}

func _ready() -> void:
	SignalBus.websocket_enabled_changed.connect(_on_websocket_enabled_changed)
	SignalBus.websocket_port_changed.connect(_on_websocket_port_changed)
	port = Settings.settings.websocket_port
	if Settings.settings.websocket_enabled:
		start()

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"websocket_enabled_changed", _on_websocket_enabled_changed)
	NodeUtil.safe_disconnect(SignalBus, &"websocket_port_changed", _on_websocket_port_changed)
	stop()

func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	while _peer.get_available_packet_count() > 0:
		var message := _peer.get_packet().get_string_from_utf8()
		_dispatch(message)

func start() -> void:
	stop()
	_peer = WebSocketMultiplayerPeer.new()
	var err: int = _peer.create_server(port, DEFAULT_BIND_ADDRESS)
	if err != OK:
		push_error(TAG + "failed to start on port %d: %s" % [port, error_string(err)])
		_peer = null
		return
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	print(TAG + "server started: ws://%s:%d" % [DEFAULT_BIND_ADDRESS, port])

func stop() -> void:
	if _peer == null:
		return
	_peer.close()
	_peer = null
	print(TAG + "server stopped")

func register_action(key: StringName, action: Callable) -> void:
	if key.is_empty():
		return
	_actions[key] = action
	SignalBus.websocket_actions_changed.emit()

func unregister_action(key: StringName) -> void:
	if not _actions.erase(key):
		return
	SignalBus.websocket_actions_changed.emit()

func send_to_all(message: String) -> void:
	if _peer == null:
		return
	_peer.set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
	_peer.put_packet(message.to_utf8_buffer())

func _dispatch(message: String) -> void:
	var colon := message.find(":")
	var command := StringName(message.substr(0, colon) if colon >= 0 else message)
	var arg := message.substr(colon + 1) if colon >= 0 else ""
	if _actions.has(command):
		_actions[command].call(arg)
		return
	push_warning(TAG + "unknown command discarded: \"%s\"" % command)

func _on_peer_connected(id: int) -> void:
	print(TAG + "client connected (%d)" % id)

func _on_peer_disconnected(id: int) -> void:
	print(TAG + "client disconnected (%d)" % id)

func _on_websocket_enabled_changed(enabled: bool) -> void:
	if enabled:
		start()
	else:
		stop()

func _on_websocket_port_changed(new_port: int) -> void:
	var was_listening := _peer != null
	stop()
	port = new_port
	if was_listening:
		start()

