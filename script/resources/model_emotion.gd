class_name ModelEmotion
extends Resource

const TAG := "[ModelEmotion] "

@export_category("Emotion")
@export var emotion_name: String = ""
@export var trigger: BaseTrigger = null
@export var movement_effect: BaseEffect = null
@export var filter_effect: BaseEffect = null
@export var twitch_event: TwitchEvent = null

func _init(name: String = "", emotion_trigger: BaseTrigger = null) -> void:
	emotion_name = name
	trigger = emotion_trigger

func get_effects() -> Array[BaseEffect]:
	var collected: Array[BaseEffect] = []
	if movement_effect != null:
		collected.append(movement_effect)
	if filter_effect != null:
		collected.append(filter_effect)
	return collected
