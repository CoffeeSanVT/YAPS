class_name TransformOptions
extends RefCounted

const TRANSFORM_ADD := "add"
const TRANSFORM_SUBTRACT := "subtract"
const TRANSFORM_INTERPOLATE := "interpolate"
const TRANSITIONS := {
	"linear": Tween.TRANS_LINEAR, "sine": Tween.TRANS_SINE, "quint": Tween.TRANS_QUINT,
	"quart": Tween.TRANS_QUART, "quad": Tween.TRANS_QUAD, "expo": Tween.TRANS_EXPO,
	"elastic": Tween.TRANS_ELASTIC, "cubic": Tween.TRANS_CUBIC, "circ": Tween.TRANS_CIRC,
	"bounce": Tween.TRANS_BOUNCE, "back": Tween.TRANS_BACK, "spring": Tween.TRANS_SPRING,
}
const EASES := {
	"in": Tween.EASE_IN, "out": Tween.EASE_OUT,
	"in_out": Tween.EASE_IN_OUT, "out_in": Tween.EASE_OUT_IN,
}

static func parse(value: float, parts: PackedStringArray, current: float) -> Dictionary:
	var next := 0
	if next < parts.size():
		match parts[next].strip_edges():
			TRANSFORM_ADD:
				value = current + value
				next += 1
			TRANSFORM_SUBTRACT:
				value = current - value
				next += 1
	if not is_finite(value):
		return {}

	var interpolation: TransformPreset
	if next < parts.size():
		if parts[next].strip_edges() != TRANSFORM_INTERPOLATE:
			return {}
		interpolation = _parse_interpolation(parts.slice(next + 1))
		if interpolation == null:
			return {}
	return {"value": value, "interpolation": interpolation}

static func _parse_interpolation(parts: PackedStringArray) -> TransformPreset:
	if parts.size() > 3:
		return null

	var options := TransformPreset.new()
	var duration := parts[0].strip_edges() if parts.size() > 0 else ""
	var transition := parts[1].strip_edges() if parts.size() > 1 else ""
	var ease_name := parts[2].strip_edges() if parts.size() > 2 else ""
	if not duration.is_empty():
		if not duration.is_valid_float():
			return null
		options.duration = duration.to_float()
		if not is_finite(options.duration) or options.duration < 0.0:
			return null
	if not transition.is_empty():
		if not TRANSITIONS.has(transition):
			return null
		options.trans_type = TRANSITIONS[transition]
	if not ease_name.is_empty():
		if not EASES.has(ease_name):
			return null
		options.ease_type = EASES[ease_name]
	return options
