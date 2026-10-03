class_name TwitchTokenStore

const TAG := "[TwitchTokenStore] "
const TOKEN_FILE_NAME := "twitch_token.dat"
const KEY_SALT := "yaps/twitch-token/v1"

static func load_token() -> String:
	var path := token_path()
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open_encrypted_with_pass(path, FileAccess.READ, KEY_SALT)
	if file == null:
		push_warning(TAG + "could not open token file (%s); re-authentication required" % error_string(FileAccess.get_open_error()))
		return ""
	var token := file.get_as_text().strip_edges()
	file.close()
	return token

static func save_token(token: String) -> bool:
	if token.is_empty():
		clear_token()
		return true
	var file := FileAccess.open_encrypted_with_pass(token_path(), FileAccess.WRITE, KEY_SALT)
	if file == null:
		push_error(TAG + "could not save token: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(token)
	file.close()
	return true

static func clear_token() -> void:
	var path := token_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

static func token_path() -> String:
	return PathUtil.get_config_folder_path().path_join(TOKEN_FILE_NAME)
