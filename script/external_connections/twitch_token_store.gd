class_name TwitchTokenStore

const TAG := "[TwitchTokenStore] "
const TOKEN_FILE_NAME := "twitch_token.dat"
const KEY_SALT := "yaps/twitch-token/v1"
const KEY_ACCESS := "access_token"
const KEY_REFRESH := "refresh_token"

static func load_tokens() -> Dictionary:
	var path := token_path()
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open_encrypted_with_pass(path, FileAccess.READ, KEY_SALT)
	if file == null:
		push_warning(TAG + "could not open token file (%s); re-authentication required" % error_string(FileAccess.get_open_error()))
		return {}
	var raw := file.get_as_text().strip_edges()
	file.close()
	var parsed: Variant = null
	if raw.begins_with("{"):
		parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		return {
			KEY_ACCESS: String(parsed.get(KEY_ACCESS, "")),
			KEY_REFRESH: String(parsed.get(KEY_REFRESH, "")),
		}
	if not raw.is_empty():
		return {KEY_ACCESS: raw, KEY_REFRESH: ""}
	return {}

static func save_tokens(access_token: String, refresh_token: String) -> bool:
	if access_token.is_empty():
		clear_token()
		return true
	var file := FileAccess.open_encrypted_with_pass(token_path(), FileAccess.WRITE, KEY_SALT)
	if file == null:
		push_error(TAG + "could not save tokens: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify({KEY_ACCESS: access_token, KEY_REFRESH: refresh_token}))
	file.close()
	return true

static func clear_token() -> void:
	var path := token_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

static func token_path() -> String:
	return PathUtil.get_config_folder_path().path_join(TOKEN_FILE_NAME)
