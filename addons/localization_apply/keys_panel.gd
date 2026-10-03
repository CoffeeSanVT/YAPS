@tool
extends OptionButton

const TRANSLATION_DIR := "res://localization"

func _ready() -> void:
	_populate()

func _on_refresh_button_up() -> void:
	_populate()

func _populate() -> void:
	clear()
	for key in _get_keys_from_translations():
		add_item(key)

func _on_apply_button_up() -> void:
	var selection = EditorInterface.get_selection()

	for node in selection.get_selected_nodes():
		var translation_node = TranslationNode.new()
		node.add_child(translation_node)
		node.set_meta("localization_key", StringName(get_item_text(selected)))
		
		var scene_root = get_tree().edited_scene_root
		
		if scene_root:
			translation_node.owner = scene_root
			translation_node.name = "TranslationNode"
		else:
			push_warning("Could not find the edited scene root.")

func _translation_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path(TRANSLATION_DIR)
	return TRANSLATION_DIR

func _get_keys_from_translations() -> PackedStringArray:
	var keys := PackedStringArray()

	var dir := DirAccess.open(_translation_dir())
	if not dir:
		push_error("Não foi possível abrir a pasta de traduções em: " + _translation_dir())
		return keys

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".translation"):
			var translation := load("res://localization/" + file_name) as Translation
			if translation:
				for key in translation.get_message_list():
					if not key in keys:
						keys.append(key)
		file_name = dir.get_next()
	dir.list_dir_end()

	return keys
