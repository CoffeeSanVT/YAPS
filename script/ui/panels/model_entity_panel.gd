class_name ModelEntityPanel
extends PanelContainer


@warning_ignore("unused_private_class_variable")
var _trigger_slot: TriggerUiSlot
var _rename_util: RenameUtil

func _setup_rename_util(rename_button: TextureButton) -> void:
	_rename_util = RenameUtil.new(rename_button)
	_rename_util.attach(self)

func commit() -> void:
	ModelLoader.save_model()

func _trigger_category() -> String:
	return ""

func _trigger_stable_id() -> String:
	return ""

func _trigger_tile_label() -> Label:
	return null

func _trigger_action_prefix() -> String:
	return ""

func _show_trigger_ui(trigger: BaseTrigger, container: Container) -> Node:
	var slot := TriggerUiSlot.ensure(self, &"_trigger_slot", container)
	return slot.show_trigger(trigger, func(key_bind: KeyBindingPanel) -> void:
		TriggerUtil.setup_key_bind(key_bind, _trigger_category(), _trigger_stable_id(), _trigger_tile_label(), _on_shortcut_saved, _trigger_action_prefix())
	)

func _on_shortcut_saved(_action_name: String, _event: InputEvent, _combo_keys: Array[int]) -> void:
	pass
