class_name TwitchEventUi
extends VBoxContainer

const TAG := "[TwitchEventUI] "

@export var event_option: OptionButton
@export var login_warning_icon: TextureRect
@export var reward_row: HBoxContainer
@export var reward_option: OptionButton
@export var bits_row: HBoxContainer
@export var bits_spinbox: SpinBox
@export var pulse_check: CheckButton
@export var pulse_duration_row: HBoxContainer
@export var pulse_duration_spinbox: SpinBox

var _trigger: TwitchEvent
var _loading: bool = false

func _ready() -> void:
	_populate_event_options()
	event_option.item_selected.connect(_on_event_selected)
	reward_option.item_selected.connect(_on_reward_selected)
	bits_spinbox.value_changed.connect(_on_bits_changed)
	pulse_check.toggled.connect(_on_pulse_toggled)
	pulse_duration_spinbox.value_changed.connect(_on_pulse_duration_changed)
	NodeUtil.attach_locale(self, _on_locale_change)
	SignalBus.twitch_connected.connect(_on_connection_changed)
	SignalBus.twitch_disconnected.connect(_on_connection_changed)
	SignalBus.twitch_rewards_fetched.connect(_on_rewards_fetched)
	_update_login_warning()
	_reload_rewards()
	_update_reward_row_visible()
	_update_bits_row_visible()

func _populate_event_options() -> void:
	event_option.clear()
	for event_id in TwitchEvent.event_ids():
		event_option.add_item(TwitchEvent.localize_event_type(event_id))

func _exit_tree() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"twitch_connected", _on_connection_changed)
	NodeUtil.safe_disconnect(SignalBus, &"twitch_disconnected", _on_connection_changed)
	NodeUtil.safe_disconnect(SignalBus, &"twitch_rewards_fetched", _on_rewards_fetched)
	if _trigger != null:
		NodeUtil.safe_disconnect(_trigger, &"reward_invalidated", _on_reward_invalidated)

func _on_connection_changed(_username: String = "") -> void:
	_update_login_warning()

func _on_rewards_fetched(_rewards: Array) -> void:
	_reload_rewards()

func _on_reward_invalidated(_event: TwitchEvent) -> void:
	reward_option.select(0)
	ModelLoader.save_model()

func _update_login_warning() -> void:
	if login_warning_icon == null:
		return
	if TwitchClient.state == TwitchClient.ConnectionState.CONNECTED:
		login_warning_icon.visible = false
		login_warning_icon.tooltip_text = ""
	else:
		login_warning_icon.visible = true
		login_warning_icon.tooltip_text = tr(&"TWITCH_LOGIN_REQUIRED")

func _reload_rewards() -> void:
	if reward_option == null:
		return
	reward_option.clear()
	reward_option.add_item(tr(&"TWITCH_REWARD_NONE"))
	var selected_id := _trigger.reward_id if _trigger != null else ""
	var selected_name := _trigger.reward_name if _trigger != null else ""
	var selected_index := 0
	var name_index := 0
	for i in range(TwitchClient.channel_rewards.size()):
		var reward: Dictionary = TwitchClient.channel_rewards[i]
		reward_option.add_item(String(reward.get("title", "")))
		if String(reward.get("id", "")) == selected_id and selected_index == 0:
			selected_index = i + 1
		elif String(reward.get("title", "")) == selected_name and name_index == 0:
			name_index = i + 1
	if selected_index == 0 and name_index > 0 and not selected_id.is_empty() and _trigger != null:
		var matched_reward: Dictionary = TwitchClient.channel_rewards[name_index - 1]
		_trigger.reward_id = String(matched_reward.get("id", ""))
		_trigger.reward_name = String(matched_reward.get("title", ""))
		_trigger.refresh_subscription()
		ModelLoader.save_model()
		selected_index = name_index
	if not selected_id.is_empty() and selected_index == 0 and not TwitchClient.channel_rewards.is_empty():
		push_warning(TAG + "trigger reward id '%s' not found in channel rewards; re-select it" % selected_id)
	reward_option.select(selected_index)

func _on_reward_selected(index: int) -> void:
	if _loading or _trigger == null:
		return
	if index <= 0 or index - 1 >= TwitchClient.channel_rewards.size():
		_trigger.reward_id = ""
		_trigger.reward_name = ""
	else:
		var reward: Dictionary = TwitchClient.channel_rewards[index - 1]
		_trigger.reward_id = String(reward.get("id", ""))
		_trigger.reward_name = String(reward.get("title", ""))
	_trigger.refresh_subscription()
	ModelLoader.save_model()

func _on_bits_changed(value: float) -> void:
	if _loading or _trigger == null:
		return
	_trigger.min_bits = int(value)
	ModelLoader.save_model()

func _on_pulse_toggled(pressed: bool) -> void:
	if _loading or _trigger == null:
		return
	_trigger.pulse_mode = pressed
	if not pressed:
		_trigger.cancel_pulse()
	_update_pulse_duration_row_visible()
	ModelLoader.save_model()

func _on_pulse_duration_changed(value: float) -> void:
	if _loading or _trigger == null:
		return
	_trigger.pulse_duration = value
	ModelLoader.save_model()

func _on_locale_change() -> void:
	var event_index := event_option.selected
	_populate_event_options()
	if event_index >= 0:
		event_option.select(event_index)
	_reload_rewards()

func setup(trigger: TwitchEvent) -> void:
	_loading = true
	if _trigger != null:
		NodeUtil.safe_disconnect(_trigger, &"reward_invalidated", _on_reward_invalidated)
	_trigger = trigger
	NodeUtil.connect_once(trigger, &"reward_invalidated", _on_reward_invalidated)
	if event_option.item_count == 0:
		_populate_event_options()
	var event_index := TwitchEvent.event_ids().find(trigger.event_type)
	if event_index >= 0:
		event_option.select(event_index)
	bits_spinbox.value = trigger.min_bits
	pulse_check.set_pressed_no_signal(trigger.pulse_mode)
	pulse_duration_spinbox.set_value_no_signal(trigger.pulse_duration)
	_reload_rewards()
	_update_reward_row_visible()
	_update_bits_row_visible()
	_update_pulse_duration_row_visible()
	_loading = false

func _on_event_selected(index: int) -> void:
	if _loading or _trigger == null:
		return
	_trigger.event_type = TwitchEvent.event_ids()[index]
	_update_reward_row_visible()
	_update_bits_row_visible()
	_trigger.refresh_subscription()
	ModelLoader.save_model()

func _update_reward_row_visible() -> void:
	if reward_row == null:
		return
	reward_row.visible = _trigger != null and _trigger.event_type == &"channel_points"

func _update_bits_row_visible() -> void:
	if bits_row == null:
		return
	bits_row.visible = _trigger != null and _trigger.event_type == &"bits"

func _update_pulse_duration_row_visible() -> void:
	if pulse_duration_row == null:
		return
	pulse_duration_row.visible = _trigger != null and _trigger.pulse_mode
