shader_type canvas_item;
render_mode unshaded;


uniform vec4 _OutlineColor : source_color = vec4(1.0);
uniform float _OutlineWidth : hint_range(0.0, 16.0) = 5.0;

uniform vec4 _SpriteBounds = vec4(0.0, 0.0, 1.0, 1.0);

uniform vec2 _OverlaySize = vec2(1.0);
uniform vec2 _SpriteOffset = vec2(0.0);
uniform vec2 _SpriteSize = vec2(1.0);

float rect_mask(vec2 uv) {
	return step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
}

void fragment() {
	vec2 sprite_uv = (UV * _OverlaySize - _SpriteOffset) / _SpriteSize;
	vec4 result = texture(TEXTURE, clamp(sprite_uv, vec2(0.0), vec2(1.0)));
	result.a *= rect_mask(sprite_uv);

	if (_OutlineWidth > 0.0) {
		bool is_solid = result.a > 0.7;
		float solid_dist = 0.0;
		if (!is_solid) {
			solid_dist = _OutlineWidth + 1.0;
			vec2 solid_win = vec2(0.0);

			vec2 bounds_margin = (_OutlineWidth + 1.0) * TEXTURE_PIXEL_SIZE;
			bool scan_reachable = all(greaterThanEqual(sprite_uv, _SpriteBounds.xy - bounds_margin))
					&& all(lessThanEqual(sprite_uv, _SpriteBounds.zw + bounds_margin));

			if (scan_reachable) {
				for (float i = -ceil(_OutlineWidth); i <= ceil(_OutlineWidth); i++) {
					float x = abs(i) > _OutlineWidth ? _OutlineWidth * sign(i) : i;
					float offset = floor(sqrt(pow(_OutlineWidth + 0.5, 2.0) - x * x));

					for (float j = -ceil(offset); j <= ceil(offset); j++) {
						float y = abs(j) > offset ? offset * sign(j) : j;

						float d = length(vec2(x, y));
						if (d >= solid_dist) {
							continue;
						}

						vec2 xy = sprite_uv + TEXTURE_PIXEL_SIZE * vec2(x, y);

						if (xy == clamp(xy, vec2(0.0), vec2(1.0)) && texture(TEXTURE, xy).a > 0.7) {
							solid_dist = d;
							solid_win = vec2(x, y);
						}
					}
				}
			}

			if (solid_win != vec2(0.0)) {
				float base = length(solid_win);
				vec2 dir = solid_win / base;
				float hi = base;
				float a_hi = texture(TEXTURE, sprite_uv + TEXTURE_PIXEL_SIZE * solid_win).a;
				for (float back = 1.0; back <= 3.0; back += 1.0) {
					float lo = max(base - back, 0.0);
					if (lo >= hi) {
						break;
					}
					float a_lo = texture(TEXTURE, sprite_uv + TEXTURE_PIXEL_SIZE * dir * lo).a;
					if ((a_lo < 0.7) != (a_hi < 0.7)) {
						float t = clamp((0.7 - a_lo) / (a_hi - a_lo), 0.0, 1.0);
						solid_dist = lo + t * (hi - lo);
						break;
					}
					hi = lo;
					a_hi = a_lo;
				}
			}
		}

		if (solid_dist <= _OutlineWidth) {
			float t = clamp((_OutlineWidth - solid_dist) * 0.5, 0.0, 1.0);
			float coverage = t * t * (3.0 - 2.0 * t);
			float outline_a = coverage * _OutlineColor.a;
			float out_a = result.a + outline_a * (1.0 - result.a);
			vec3 out_rgb = (result.rgb * result.a + _OutlineColor.rgb * outline_a * (1.0 - result.a))
					/ max(out_a, 0.0001);
			result = vec4(out_rgb, out_a);
		}
	}

	COLOR = result;
}
