extends Node

const TAG := "[FileLogger] "
const LOG_DIR_NAME := "logs"
const MAX_LOG_FILES := 10

class FileLog extends Logger:
	const ERR_TYPE_WARNING := 1
	const ERR_TYPE_SCRIPT := 2
	const ERR_TYPE_SHADER := 3
	const TAG_PATTERN := "^\\[([A-Za-z0-9_]+)\\]\\s*"

	var _mutex := Mutex.new()
	var _file: FileAccess
	var _tag_regex := RegEx.new()

	func _init(log_path: String) -> void:
		_tag_regex.compile(TAG_PATTERN)
		DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
		_file = FileAccess.open(log_path, FileAccess.WRITE)
		if _file == null:
			push_error(TAG + "Failed to open log file: " + log_path)

	func _log_message(message: String, error: bool) -> void:
		_write(_format(message.strip_edges(), "ERROR" if error else "INFO"))

	func _log_error(
			function: String,
			file: String,
			line: int,
			_code: String,
			rationale: String,
			_editor_notify: bool,
			error_type: int,
			_script_backtraces: Array
	) -> void:
		var message := rationale.strip_edges()
		if _code.strip_edges() != "":
			message += " " + _code.strip_edges()
		var location := "%s (%s:%d)" % [function, file.get_file(), line]
		_write(_format(message, _error_type_label(error_type), location))

	func _format(message: String, level: String, location := "") -> String:
		var timestamp := _timestamp()
		var match_result := _tag_regex.search(message)
		if match_result != null:
			var tag := match_result.get_string(1)
			var text := message.substr(match_result.get_end()).strip_edges()
			return "[%s] [%s: %s] %s" % [timestamp, level, tag, text]
		if location.is_empty():
			return "[%s] [%s] %s" % [timestamp, level, message]
		return "[%s] [%s: %s] %s" % [timestamp, level, location, message]

	func _timestamp() -> String:
		return Time.get_time_string_from_system()

	func _write(line: String) -> void:
		_mutex.lock()
		if _file != null:
			_file.store_line(line)
			_file.flush()
		_mutex.unlock()

	func _error_type_label(error_type: int) -> String:
		match error_type:
			ERR_TYPE_WARNING:
				return "WARNING"
			ERR_TYPE_SCRIPT:
				return "SCRIPT ERROR"
			ERR_TYPE_SHADER:
				return "SHADER ERROR"
			_:
				return "ERROR"

func _init() -> void:
	var log_path := _log_path()
	if log_path.is_empty():
		return
	OS.add_logger(FileLog.new(log_path))

func _log_path() -> String:
	var base_dir: String
	if OS.has_feature("editor"):
		base_dir = ProjectSettings.globalize_path("user://")
	else:
		base_dir = OS.get_executable_path().get_base_dir()
		if base_dir.is_empty():
			return ""
	var log_dir := base_dir.path_join(LOG_DIR_NAME)
	_cleanup_old_logs(log_dir)
	var timestamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	return log_dir.path_join("yaps_%s.log" % timestamp)

func _cleanup_old_logs(log_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(log_dir):
		return
	var dir := DirAccess.open(log_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var files: Array[String] = []
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".log"):
			files.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	files.sort()
	while files.size() >= MAX_LOG_FILES:
		dir.remove(files.pop_front())
