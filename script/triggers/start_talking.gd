class_name StartTalking
extends BaseTrigger

func _init() -> void:
	trigger_name = &"start_talking"

func activate() -> void:
	NodeUtil.connect_once(SignalBus, &"mic_input_exceed_threshold", _on_mic)

func deactivate() -> void:
	NodeUtil.safe_disconnect(SignalBus, &"mic_input_exceed_threshold", _on_mic)

func _on_mic(talking:bool) -> void:
	set_enabled(talking)
