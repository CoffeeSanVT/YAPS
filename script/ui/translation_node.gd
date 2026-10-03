class_name TranslationNode
extends Node

var metadata: StringName = &"localization_key"

func _ready() -> void:
	NodeUtil.attach_locale(self, _update_text)
	_update_text()

func _update_text() -> void:
	var parent: Node = get_parent()

	if !parent.has_meta(metadata):
		return

	var key: String = parent.get_meta(metadata)
	var localized_text: String = tr(key)

	if parent is TabBar:
		parent.name = localized_text
	elif parent is FoldableContainer:
		parent.title = localized_text
	elif parent is LineEdit:
		parent.placeholder_text = localized_text
	else:
		parent.text = localized_text
