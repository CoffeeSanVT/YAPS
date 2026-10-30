class_name ItemTransformPreset
extends TransformPreset

@export_category("Expression")
@export var expression_name: String = ""

func _init(p_name: String = "", pos: Vector2 = Vector2.ZERO, sc: float = 0.0, rot: float = 0.0, expression: String = "") -> void:
	super(p_name, pos, sc, rot)
	expression_name = expression
