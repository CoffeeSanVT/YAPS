class_name ModelStateEntry
extends Resource

@export_category("State Entry")
@export var state_name: String = ""
@export_file("*.png", "*.apng", "*.gif", "*.webp", "*.webm") var asset_path: String = ""
@export var frames: Array[String] = []
@export var frame_rate: float = 8.0
@export var override_frame_rate: bool = false
@export var animation_chance: float = 5.0
@export var override_animation_chance: bool = false
@export var loop_animation: bool = true
@export var override_silence: bool = false

func _init(name: String = "", path: String = "") -> void:
	state_name = name
	asset_path = path

func get_frame_paths() -> Array[String]:
	var paths: Array[String] = [asset_path]
	paths.append_array(frames)
	return paths

func effective_frame_rate(global_rate: float) -> float:
	if override_frame_rate or global_rate <= 0.0:
		return frame_rate
	return global_rate

func effective_animation_chance(global_chance: float) -> float:
	if override_animation_chance or global_chance <= 0.0:
		return animation_chance
	return global_chance
