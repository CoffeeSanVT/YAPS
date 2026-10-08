class_name TwitchEvent
extends BaseTrigger

const TAG := "[TwitchEvent] "

signal reward_invalidated(trigger: TwitchEvent)

const EVENT_TYPES: Dictionary = {
	&"follow": "channel.follow",
	&"subscribe": "channel.subscribe",
	&"gift_sub": "channel.subscription.gift",
	&"raid": "channel.raid",
	&"bits": "channel.cheer",
	&"channel_points": "channel.channel_points_custom_reward_redemption.add",
}

static var _event_ids: Array[StringName] = []

static func event_ids() -> Array[StringName]:
	if _event_ids.is_empty():
		for id: StringName in EVENT_TYPES:
			_event_ids.append(id)
	return _event_ids.duplicate()

@export_category("Twitch Event")
@export var event_type: StringName = &"follow"
@export var reward_id: String = ""
@export var reward_name: String = ""
@export var min_bits: int = 0
@export_group("Pulse")
@export var pulse_mode: bool = false
@export var pulse_duration: float = 3.0

var _active: bool = false
var _pulse_end_msec: int = 0
var _last_subscribed_type: StringName = &""
var _last_subscribed_reward: String = ""

func _init() -> void:
	trigger_name = &"twitch_event"
	ui_prefab = preload("uid://d1q6ma2vw4h6n")

func activate() -> void:
	if _active:
		refresh_subscription()
		return
	_active = true
	_last_subscribed_type = event_type
	_last_subscribed_reward = _current_reward()
	_sync_subscription()
	NodeUtil.connect_once(SignalBus, &"twitch_event_received", _on_twitch_event)
	NodeUtil.connect_once(SignalBus, &"twitch_reward_revoked", _on_reward_revoked)
	NodeUtil.connect_once(SignalBus, &"twitch_connected", _on_twitch_connected)

func deactivate() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"twitch_event_received", _on_twitch_event)
	NodeUtil.safe_disconnect(SignalBus, &"twitch_reward_revoked", _on_reward_revoked)
	NodeUtil.safe_disconnect(SignalBus, &"twitch_connected", _on_twitch_connected)
	_release_subscription()
	_active = false

func refresh_subscription() -> void:
	if not _active:
		activate()
		return
	if event_type == _last_subscribed_type and _current_reward() == _last_subscribed_reward:
		return
	_release_subscription()
	_last_subscribed_type = event_type
	_last_subscribed_reward = _current_reward()
	_sync_subscription()

func _sync_subscription() -> void:
	if _last_subscribed_type == &"channel_points" and _last_subscribed_reward.is_empty():
		return
	TwitchClient.subscribe_event(_last_subscribed_type, _last_subscribed_reward)

func _release_subscription() -> void:
	if _last_subscribed_type.is_empty():
		return
	TwitchClient.unsubscribe_event(_last_subscribed_type, _last_subscribed_reward)
	_last_subscribed_type = &""
	_last_subscribed_reward = ""

func _current_reward() -> String:
	return reward_id if event_type == &"channel_points" else ""

func _on_twitch_event(type: StringName, data: Dictionary, sub_reward_id: String) -> void:
	if type != event_type:
		return
	if event_type == &"channel_points":
		if reward_id.is_empty():
			return
		var event_reward: Dictionary = data.get("reward", {})
		var event_reward_id := String(event_reward.get("id", ""))
		var event_reward_name := String(event_reward.get("title", ""))
		if event_reward_id != reward_id:
			if not event_reward_id.is_empty() and not event_reward_name.is_empty() and event_reward_name == reward_name:
				reward_id = event_reward_id
				refresh_subscription()
			else:
				push_warning(TAG + "event ignored: reward mismatch (trigger reward: %s, event reward: %s)" % [_reward_label(reward_id, reward_name), _reward_label(event_reward_id, event_reward_name)])
				if not sub_reward_id.is_empty() and sub_reward_id == reward_id:
					reward_id = ""
					reward_name = ""
					refresh_subscription()
					reward_invalidated.emit(self)
				return
	if event_type == &"bits" and min_bits > 0:
		if int(data.get("bits", 0)) < min_bits:
			return
	if pulse_mode:
		_trigger_pulse()
		return
	set_enabled(not enabled)

func _on_twitch_connected(_username: String) -> void:
	if not _active:
		return
	_release_subscription()
	_last_subscribed_type = event_type
	_last_subscribed_reward = _current_reward()
	_sync_subscription()

func _on_reward_revoked(sub_reward_id: String) -> void:
	if event_type != &"channel_points" or reward_id.is_empty() or sub_reward_id != reward_id:
		return
	push_warning(TAG + "reward revoked by Twitch (reward: %s); re-select it" % _reward_label(reward_id, reward_name))
	reward_id = ""
	reward_name = ""
	refresh_subscription()
	reward_invalidated.emit(self)

func tick(_delta: float, _current_state: ModelStateEntry) -> void:
	if not pulse_mode or not enabled:
		return
	if Time.get_ticks_msec() < _pulse_end_msec:
		return
	_pulse_end_msec = 0
	set_enabled(false)

func _trigger_pulse() -> void:
	_pulse_end_msec = int(Time.get_ticks_msec()) + int(maxf(pulse_duration, 0.05) * 1000.0)
	set_enabled(true)

func cancel_pulse() -> void:
	_pulse_end_msec = 0
	if enabled:
		set_enabled(false)

static func localize_event_type(id: StringName) -> String:
	var key := "TWITCH_EVENT_" + String(id).to_upper()
	var translated := String(TranslationServer.translate(key))
	if translated.is_empty() or translated == key:
		return String(id).capitalize()
	return translated

static func _reward_label(id: String, title: String) -> String:
	return "%s (%s)" % [id, title] if not title.is_empty() else id
