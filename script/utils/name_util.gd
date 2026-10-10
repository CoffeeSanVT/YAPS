class_name NameUtil

const EMOTION_SUFFIX_PATTERN := "(?i)[\\s_-]+(?:talking|silence)$"
const STATIC_FRAME_SUFFIX_PATTERN := "(?i)(?:[\\s_-]+|^)(?:blink|close[\\s_-]eyes)$"

static var _emotion_suffix_regex := RegEx.create_from_string(EMOTION_SUFFIX_PATTERN)
static var _static_frame_suffix_regex := RegEx.create_from_string(STATIC_FRAME_SUFFIX_PATTERN)

static func unique_name(base: String, is_taken: Callable) -> String:
	var candidate := base
	var counter := 1
	while is_taken.call(candidate):
		candidate = "%s_%d" % [base, counter]
		counter += 1
	return candidate

static func emotion_name_for_file(file_name: String) -> String:
	return strip_emotion_suffix(file_name.get_basename())

static func strip_emotion_suffix(entry_name: String) -> String:
	return _emotion_suffix_regex.sub(entry_name, "", false)

static func strip_frame_suffix(entry_name: String) -> String:
	return _static_frame_suffix_regex.sub(entry_name, "", false)

static func is_frame_file_name(file_name: String) -> bool:
	return _static_frame_suffix_regex.search(file_name.get_basename()) != null

static func is_neutral_file_name(file_name: String) -> bool:
	return is_neutral_entry_name(file_name.get_basename())

static func is_neutral_entry_name(entry_name: String) -> bool:
	var lowered := entry_name.to_lower()
	return lowered == "talking" or lowered == "silence"