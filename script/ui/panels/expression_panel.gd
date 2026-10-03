extends ModelEntityPanel

@export_category("Frames")
@export var frames_list: VBoxContainer
@export var frame_rate_spin: SpinBox
@export var animation_chance_spin: SpinBox
@export var loop_toggle: CheckButton
@export var override_toggle: CheckButton
@export var override_chance_toggle: CheckButton
@export var override_silence_toggle: CheckButton
@export var override_silence_label: Label

@export_category("Actions")
@export var tile_text: Label
@export var rename_button: TextureButton

const TRASH_ICON_NORMAL := "uid://g8ajdb2xdmqu"
const TRASH_ICON_PRESSED := "uid://66ckvqaenf7y"
const TRASH_ICON_HOVER := "uid://c7jgar1rs0shf"
const TRASH_ICON_DISABLED := "uid://dm5jhnakge0ff"
const TRASH_ICON_FOCUSED := "uid://menup57lhvdt"

var state_entry: ModelStateEntry

func _ready() -> void:
	_setup_rename_util(rename_button)
	SignalBus.model_images_reloaded.connect(_populate_frames)
	SignalBus.state_frames_changed.connect(_populate_frames)

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"model_images_reloaded", _populate_frames)
	NodeUtil.safe_disconnect(SignalBus, &"state_frames_changed", _populate_frames)

func set_state_entry(entry: ModelStateEntry) -> void:
	state_entry = entry
	tile_text.text = String(entry.state_name).capitalize()
	if override_toggle != null:
		override_toggle.set_pressed_no_signal(entry.override_frame_rate)
	_update_frame_rate_spin()
	if override_chance_toggle != null:
		override_chance_toggle.set_pressed_no_signal(entry.override_animation_chance)
	if animation_chance_spin != null:
		_update_chance_spin()
	if loop_toggle != null:
		loop_toggle.set_pressed_no_signal(entry.loop_animation)
	if override_silence_toggle != null:
		override_silence_toggle.set_pressed_no_signal(entry.override_silence)
		_update_silence_toggle_label()
	_populate_frames()

func _populate_frames() -> void:
	NodeUtil.clear_children(frames_list)
	if state_entry == null:
		return
	for frame_path in state_entry.frames:
		_add_frame_row(frame_path)

func _add_frame_row(frame_path: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 40)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(32, 32)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ModelLoader.textures.request_texture(frame_path, func(tex: ImageTexture) -> void:
		thumb.texture = tex
	, thumb)
	row.add_child(thumb)

	var label := Label.new()
	label.text = frame_path.get_file().get_basename()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)

	var delete_button := TextureButton.new()
	delete_button.texture_normal = load(TRASH_ICON_NORMAL)
	delete_button.texture_pressed = load(TRASH_ICON_PRESSED)
	delete_button.texture_hover = load(TRASH_ICON_HOVER)
	delete_button.texture_disabled = load(TRASH_ICON_DISABLED)
	delete_button.texture_focused = load(TRASH_ICON_FOCUSED)
	delete_button.custom_minimum_size = Vector2(24, 24)
	delete_button.custom_maximum_size = Vector2(24, 24)
	delete_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	delete_button.tooltip_text = tr(&"DELETE")
	delete_button.pressed.connect(_on_frame_delete_pressed.bind(frame_path))
	row.add_child(delete_button)

	frames_list.add_child(row)

func _on_add_frame_pressed() -> void:
	if state_entry == null:
		return
	FileDialogHelper.open_file(self, _on_frame_image_selected)

func _on_frame_image_selected(path: String) -> void:
	if state_entry == null:
		return
	ModelLoader.add_frame_to_state(state_entry, path, _refresh_frames)

func _on_frame_delete_pressed(frame_path: String) -> void:
	if state_entry == null:
		return
	ModelLoader.remove_frame_from_state(state_entry, frame_path)
	_refresh_frames()

func _on_frame_rate_changed(value: float) -> void:
	_set_entry_value(&"frame_rate", value)

func _on_override_toggled(pressed: bool) -> void:
	if state_entry == null:
		return
	state_entry.override_frame_rate = pressed
	if pressed and ModelLoader.model_loaded != null and ModelLoader.model_loaded.global_frame_rate > 0.0:
		state_entry.frame_rate = ModelLoader.model_loaded.global_frame_rate
	_update_frame_rate_spin()
	ModelLoader.save_model()

func _update_frame_rate_spin() -> void:
	var global_rate := ModelLoader.model_loaded.global_frame_rate if ModelLoader.model_loaded != null else 0.0
	frame_rate_spin.set_value_no_signal(state_entry.effective_frame_rate(global_rate))
	frame_rate_spin.editable = state_entry.override_frame_rate

func _on_override_chance_toggled(pressed: bool) -> void:
	if state_entry == null:
		return
	state_entry.override_animation_chance = pressed
	if pressed and ModelLoader.model_loaded != null and ModelLoader.model_loaded.global_animation_chance > 0.0:
		state_entry.animation_chance = ModelLoader.model_loaded.global_animation_chance
	_update_chance_spin()
	ModelLoader.save_model()

func _update_chance_spin() -> void:
	var global_chance := ModelLoader.model_loaded.global_animation_chance if ModelLoader.model_loaded != null else 0.0
	animation_chance_spin.set_value_no_signal(state_entry.effective_animation_chance(global_chance))
	animation_chance_spin.editable = state_entry.override_animation_chance

func _on_animation_chance_changed(value: float) -> void:
	_set_entry_value(&"animation_chance", value)

func _set_entry_value(property: StringName, value: float) -> void:
	if state_entry == null:
		return
	state_entry.set(property, value)
	_refresh_frames()

func _on_loop_toggled(pressed: bool) -> void:
	if state_entry == null:
		return
	state_entry.loop_animation = pressed
	if animation_chance_spin != null:
		_update_chance_spin()
	_refresh_frames()

func _on_silence_override_toggled(pressed: bool) -> void:
	if state_entry == null:
		return
	_set_override_for_emotion(pressed)
	ModelLoader.save_model()
	var machine := get_tree().get_first_node_in_group(&"model_state_machine") as ModelStateMachine
	if machine != null:
		machine.resolve()
	SignalBus.states_changed.emit()

func _set_override_for_emotion(pressed: bool) -> void:
	var profile := ModelLoader.model_loaded
	if profile == null:
		state_entry.override_silence = pressed
		return
	for branch in profile.branches:
		for entry in branch.all_entries():
			if entry.state_name.to_lower() == state_entry.state_name.to_lower():
				entry.override_silence = pressed

func _update_silence_toggle_label() -> void:
	if override_silence_label == null:
		return
	var key := &"OVERRIDE_SILENCE"
	var profile := ModelLoader.model_loaded
	if profile != null:
		var branch := profile.branch_of(state_entry)
		if branch != null and branch.state_name == ModelState.SILENCE:
			key = &"OVERRIDE_TALKING"
	override_silence_label.set_meta(&"localization_key", key)
	override_silence_label.text = tr(key)

func _refresh_frames() -> void:
	_populate_frames()
	SignalBus.state_frames_changed.emit()

func _on_rename_pressed() -> void:
	if state_entry == null:
		return
	_rename_util.rename_property(tile_text, state_entry, &"state_name", _is_state_name_taken)

func _is_state_name_taken(candidate: String) -> bool:
	return ModelLoader.model_loaded != null and ModelLoader.model_loaded.has_entry_named(candidate, state_entry)
