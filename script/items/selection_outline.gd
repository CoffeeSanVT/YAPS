class_name SelectionOutline
extends TextureRect

const ITEM_OUTLINE_SHADER := "uid://dakssg25vivi1"
const OUTLINE_MARGIN := 64.0
const OUTLINE_COLOR := Color("#ff425a")
const OUTLINE_WIDTH := 8.0
const FADE_TIME := 0.25

var _tween: Tween

static func create(target: TextureRect, sprite_bounds: Rect2) -> SelectionOutline:
	var overlay := SelectionOutline.new()
	overlay.texture = target.texture
	overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	overlay.stretch_mode = TextureRect.STRETCH_SCALE
	overlay.mouse_filter = MOUSE_FILTER_IGNORE
	overlay.show_behind_parent = true
	overlay.size = target.size + Vector2(OUTLINE_MARGIN, OUTLINE_MARGIN) * 2.0
	overlay.position = -Vector2(OUTLINE_MARGIN, OUTLINE_MARGIN)
	var material_override := ShaderMaterial.new()
	material_override.shader = load(ITEM_OUTLINE_SHADER)
	material_override.set_shader_parameter(&"_OutlineColor", OUTLINE_COLOR)
	material_override.set_shader_parameter(&"_OutlineWidth", 0.0)
	material_override.set_shader_parameter(&"_SpriteBounds", TextureCache.bounds_to_vec4(sprite_bounds))
	material_override.set_shader_parameter(&"_OverlaySize", overlay.size)
	material_override.set_shader_parameter(&"_SpriteOffset", Vector2(OUTLINE_MARGIN, OUTLINE_MARGIN))
	material_override.set_shader_parameter(&"_SpriteSize", target.size)
	overlay.material = material_override
	target.add_child(overlay)
	return overlay

func current_width() -> float:
	var value: Variant = (material as ShaderMaterial).get_shader_parameter(&"_OutlineWidth")
	return float(value) if value != null else 0.0

func set_width(value: float) -> void:
	(material as ShaderMaterial).set_shader_parameter(&"_OutlineWidth", value)

func set_sprite_bounds(bounds: Rect2) -> void:
	(material as ShaderMaterial).set_shader_parameter(&"_SpriteBounds", TextureCache.bounds_to_vec4(bounds))

func sync_texture(tex: Texture2D) -> void:
	if texture != tex:
		texture = tex

func tween_width(to: float, on_finished: Callable = Callable()) -> void:
	_tween = NodeUtil.stop_tween(_tween)
	_tween = create_tween()
	_tween.tween_method(set_width, current_width(), to, FADE_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if on_finished.is_valid():
		_tween.tween_callback(on_finished)

func cancel_tween() -> void:
	_tween = NodeUtil.stop_tween(_tween)
