class_name NameUtil

const EMOTION_SUFFIXES: PackedStringArray = ["_talking", "-talking", " talking", "_silence", "-silence", " silence"]

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
	var lowered := entry_name.to_lower()
	for suffix: String in EMOTION_SUFFIXES:
		if lowered.ends_with(suffix):
			return entry_name.substr(0, entry_name.length() - suffix.length())
	return entry_name

static func is_neutral_file_name(file_name: String) -> bool:
	return is_neutral_entry_name(file_name.get_basename())

static func is_neutral_entry_name(entry_name: String) -> bool:
	var lowered := entry_name.to_lower()
	return lowered == "talking" or lowered == "silence"
