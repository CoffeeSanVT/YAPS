class_name ModelState
extends Resource

const TALKING := &"Talking"
const SILENCE := &"Silence"

@export_category("State")
@export var state_name: String = ""
@export var default_entry: ModelStateEntry
@export var emotion_entries: Array[ModelStateEntry] = []

func _init(name: String = "", default_state_entry: ModelStateEntry = null) -> void:
	state_name = name
	default_entry = default_state_entry

func entry_for(emotion_name: String) -> ModelStateEntry:
	if emotion_name.is_empty():
		return default_entry
	var entry := _find_entry(emotion_name)
	return entry if entry != null else default_entry

func find_entry(entry_name: String) -> ModelStateEntry:
	if default_entry != null and default_entry.state_name.to_lower() == entry_name.to_lower():
		return default_entry
	return _find_entry(entry_name)

func _find_entry(entry_name: String) -> ModelStateEntry:
	for entry in emotion_entries:
		if entry.state_name.to_lower() == entry_name.to_lower():
			return entry
	return null

func unique_entry_name(base: String) -> String:
	if find_entry(base) == null:
		return base
	return NameUtil.unique_name(base, func(candidate: String) -> bool: return find_entry(candidate) != null)

func resolve_default_entry() -> ModelStateEntry:
	if default_entry != null:
		return default_entry
	return emotion_entries[0] if not emotion_entries.is_empty() else null

func all_entries() -> Array[ModelStateEntry]:
	var entries: Array[ModelStateEntry] = []
	if default_entry != null:
		entries.append(default_entry)
	entries.append_array(emotion_entries)
	return entries

func add_emotion_entry(entry: ModelStateEntry) -> void:
	var existing := entry_for(entry.state_name)
	if existing != null and existing != default_entry:
		emotion_entries[emotion_entries.find(existing)] = entry
		return
	emotion_entries.append(entry)
