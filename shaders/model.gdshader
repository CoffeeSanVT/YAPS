shader_type canvas_item;

#include "uid://btu32ism7xjrr"
#include "uid://bf7rebu06xm4q"
#include "uid://c0uar0jmillqa"

group_uniforms sampler;
uniform sampler2D _CurrentTex : source_color, filter_linear;
uniform sampler2D _NextTex : source_color, filter_linear;

group_uniforms crossfade;
uniform float _Transition : hint_range(0.0, 1.0, 0.1);

group_uniforms filter;
uniform int _Filter : hint_enum("None", "Warp", "Darken") = 0;
uniform float _FilterAmount : hint_range(0.0, 1.0) = 0.0;

group_uniforms antialias;
uniform int _AntiAlias : hint_enum("AA_NONE", "AA_FEATHER", "AA_SUPERSAMPLE", "AA_FXAA", "AA_MSAA_4X", "AA_MSAA_2X") = 0;

group_uniforms outline;
uniform bool _EnableOutline;
uniform vec4 _OutlineColor : source_color = vec4(1.0);
uniform float _OutlineWidth : hint_range(0.0, 16.0) = 5.0;
uniform float _OutlineSoftness : hint_range(0.0, 16.0) = 2.0;
uniform bool _OutlineInside = false;
uniform float _OutlineAlphaThreshold : hint_range(0.01, 1.0) = 0.7;
uniform bool _OutlineHalftone = false;
uniform float _OutlineHalftoneSize : hint_range(2.0, 32.0) = 6.0;
uniform bool _OutlineGradient = false;
uniform vec4 _OutlineGradientColor : source_color = vec4(0.0, 0.5, 1.0, 1.0);

uniform vec4 _CurrentBounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 _NextBounds = vec4(0.0, 0.0, 1.0, 1.0);

vec4 sample_model(vec2 uv) {
	if (_Transition <= 0.0) {
		return _aa_sample(_CurrentTex, uv, _AntiAlias);
	}
	if (_Transition >= 1.0) {
		return _aa_sample(_NextTex, uv, _AntiAlias);
	}
	vec4 current_tex = _aa_sample(_CurrentTex, uv, _AntiAlias);
	vec4 next_tex = _aa_sample(_NextTex, uv, _AntiAlias);
	return mix(current_tex, next_tex, _Transition);
}

vec4 outline_paint(float dist) {
	if (!_OutlineGradient) {
		return _OutlineColor;
	}
	float t = clamp(dist / _OutlineWidth, 0.0, 1.0);
	return vec4(mix(_OutlineColor.rgb, _OutlineGradientColor.rgb, t), _OutlineColor.a);
}

bool outline_scan_reachable(vec2 uv, float width, vec2 texture_pixel_size) {
	vec4 bounds = vec4(min(_CurrentBounds.xy, _NextBounds.xy), max(_CurrentBounds.zw, _NextBounds.zw));
	vec2 margin = (width + 1.0) * texture_pixel_size;
	return all(greaterThanEqual(uv, bounds.xy - margin)) && all(lessThanEqual(uv, bounds.zw + margin));
}

void fragment() {
	vec2 uv = UV;
	if (_Filter == FILTER_WARP) {
		uv = filter_warp(uv, _FilterAmount, TIME);
	}

	vec4 result = sample_model(uv);

	if (_Filter == FILTER_DARKEN) {
		result = filter_darken(result, _FilterAmount);
	}

	if (_EnableOutline && _OutlineWidth > 0.0) {
		bool is_solid = result.a > _OutlineAlphaThreshold;
		float dist = _OutlineWidth + 1.0;
		if (_OutlineInside) {
			if (result.a > 0.05) {
				float solid_dist, empty_dist;
				outline_scan(uv, TEXTURE_PIXEL_SIZE, _OutlineWidth,
						_OutlineAlphaThreshold, _Transition, _CurrentTex, _NextTex,
						solid_dist, empty_dist);
				dist = empty_dist;
			}
		} else if (is_solid) {
			dist = 0.0;
		} else if (outline_scan_reachable(uv, _OutlineWidth, TEXTURE_PIXEL_SIZE)) {
			float solid_dist, empty_dist;
			outline_scan(uv, TEXTURE_PIXEL_SIZE, _OutlineWidth,
					_OutlineAlphaThreshold, _Transition, _CurrentTex, _NextTex,
					solid_dist, empty_dist);
			dist = solid_dist;
		}

		if (dist <= _OutlineWidth) {
			float softness = max(_OutlineSoftness, 0.01);
			float t = clamp((_OutlineWidth - dist) / softness, 0.0, 1.0);
			float coverage = t * t * (3.0 - 2.0 * t);
			vec4 paint = outline_paint(dist);
			if (_OutlineHalftone) {
				coverage *= outline_halftone_mask(FRAGCOORD.xy, coverage, _OutlineHalftoneSize);
			}
			if (_OutlineInside) {
				float presence = clamp(result.a / _OutlineAlphaThreshold, 0.0, 1.0);
				result.rgb = mix(result.rgb, paint.rgb, coverage * paint.a * presence);
			} else {
				float outline_a = coverage * paint.a;
				float out_a = result.a + outline_a * (1.0 - result.a);
				vec3 out_rgb = (result.rgb * result.a + paint.rgb * outline_a * (1.0 - result.a))
						/ max(out_a, 0.0001);
				result = vec4(out_rgb, out_a);
			}
		}
	}

	COLOR = result;
}
