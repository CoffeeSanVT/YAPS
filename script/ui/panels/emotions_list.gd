extends VBoxContainer

@export_category("UI References")
@export var emotion_list: VBoxContainer
@export var add_button: Button

@export_category("Prefabs")
@export var emotion_panel_prefab: PackedScene
@export var add_emotion_dialog_prefab: PackedScene

var _overlay: ModalOverlay

func _ready() -> void:
	add_button.pressed.connect(_on_add_emotion_pressed)
	SignalBus.states_changed.connect(_refresh)
	NodeUtil.attach_locale(self, _refresh)
	SignalBus.model_emotion_effects_changed.connect(_on_emotion_effect_changed)
	_refresh()

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"states_changed", _refresh)
	NodeUtil.safe_disconnect(SignalBus, &"model_emotion_effects_changed", _on_emotion_effect_changed)
	if _overlay != null:
		_overlay.dispose()

func _refresh() -> void:
	if ModelLoader.model_loaded == null:
		return
	NodeUtil.clear_children(emotion_list)

	_create_neutral_panel()
	for emotion in ModelLoader.model_loaded.emotions:
		var panel := emotion_panel_prefab.instantiate()
		panel.connect(&"trigger_option_changed", _save_emotion_trigger)
		emotion_list.add_child(panel)
		panel.set_emotion(emotion)

func _create_neutral_panel() -> void:
	var panel := emotion_panel_prefab.instantiate()
	emotion_list.add_child(panel)
	panel.set_neutral(ModelLoader.model_loaded.ensure_neutral_emotion())

func _on_add_emotion_pressed() -> void:
	var dialog := add_emotion_dialog_prefab.instantiate()
	dialog.name_confirmed.connect(_on_emotion_name_confirmed)
	_show_modal(dialog, Vector2i(320, 170))

func _on_emotion_name_confirmed(emotion_name: String) -> void:
	_open_emotion_image_picker(emotion_name)

func _open_emotion_image_picker(emotion_name: String) -> void:
	FileDialogHelper.open_files(self, _on_emotion_images_selected.bind(emotion_name), FileDialogHelper.IMAGE_FILTERS, tr(&"ADD_EMOTION"), Vector2i(700, 500))

func _on_emotion_images_selected(paths: PackedStringArray, emotion_name: String) -> void:
	if paths.size() != 2:
		_open_emotion_image_picker(emotion_name)
		return
	var talking_path := ""
	var silence_path := ""
	for path: String in paths:
		if ModelLoader.resolve_branch_for_file(path) == ModelState.TALKING:
			talking_path = path
		else:
			silence_path = path
	ModelLoader.add_emotion_with_images(emotion_name, talking_path, silence_path)

func _show_modal(modal: Control, modal_size: Vector2i) -> void:
	if _overlay == null:
		_overlay = ModalOverlay.new()
	_overlay.show_modal(self, modal, modal_size)

func _save_emotion_trigger(emotion_name: String, trigger: BaseTrigger) -> void:
	var emotion := ModelLoader.model_loaded.get_emotion(emotion_name)
	if emotion != null:
		ModelStateMachine.replace_emotion_trigger(self, emotion, &"trigger", trigger)

	ModelLoader.save_and_sync_triggers()

func _on_emotion_effect_changed(emotion: ModelEmotion, effect: BaseEffect, category: int) -> void:
	ModelLoader.set_emotion_effect(emotion, effect, category)
