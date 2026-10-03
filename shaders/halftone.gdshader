shader_type canvas_item;

uniform vec4 color_a : source_color = vec4(0.1, 0.1, 0.2, 1.0);
uniform vec4 color_b : source_color = vec4(0.9, 0.3, 0.4, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.5;
uniform float frequency : hint_range(5.0, 100.0) = 30.0;
uniform float edge_softness : hint_range(0.01, 1.0) = 0.3;
uniform bool invert_direction = false;

void fragment() {
	float v_uv = invert_direction ? (1.0 - UV.y) : UV.y;
	float local_progress = smoothstep(v_uv - edge_softness, v_uv + edge_softness, progress * (1.0 + edge_softness * 2.0) - edge_softness);

	vec2 uv_dx = dFdx(UV);
	vec2 uv_dy = dFdy(UV);
	float aspect = length(uv_dy) / length(uv_dx);

	vec2 aspect_uv = UV;
	aspect_uv.x *= aspect;

	vec2 grid_uv = fract(aspect_uv * frequency);
	float dist = distance(grid_uv, vec2(0.5));

	float max_radius = 0.9;
	float current_radius = local_progress * max_radius;

	float delta = fwidth(dist);
	float dot_mask = smoothstep(current_radius + delta, current_radius - delta, dist);
	if (local_progress >= 0.999) {
		dot_mask = 1.0;
	}
	dot_mask *= step(0.001, local_progress);

	COLOR = mix(color_a, color_b, dot_mask);
}