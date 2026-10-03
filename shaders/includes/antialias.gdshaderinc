#ifndef ANTIALIAS_INCLUDED
#define ANTIALIAS_INCLUDED

const int AA_NONE = 0;
const int AA_FEATHER = 1;
const int AA_SUPERSAMPLE = 2;
const int AA_FXAA = 3;
const int AA_MSAA_4X = 4;
const int AA_MSAA_2X = 5;

float _aa_luma(vec4 c) {
	return dot(c.rgb * c.a, vec3(0.299, 0.587, 0.114)) + c.a * 0.5;
}

vec4 _aa_none(sampler2D tex, vec2 uv) {
	return texture(tex, uv);
}

vec4 _aa_feather(sampler2D tex, vec2 uv) {
	vec2 px = 1.0 / vec2(textureSize(tex, 0));
	vec4 center = texture(tex, uv);
	if (center.a <= 0.0 || center.a >= 1.0) {
		return center;
	}
	vec4 left = texture(tex, uv + vec2(-px.x, 0.0));
	vec4 right = texture(tex, uv + vec2(px.x, 0.0));
	vec4 up = texture(tex, uv + vec2(0.0, -px.y));
	vec4 down = texture(tex, uv + vec2(0.0, px.y));
	float spread = max(max(left.a, right.a), max(up.a, down.a))
		- min(min(left.a, right.a), min(up.a, down.a));
	if (spread < 0.05) {
		return center;
	}
	vec4 avg = (left + right + up + down) * 0.25;
	return mix(center, avg, 0.5);
}

vec4 _aa_supersample(sampler2D tex, vec2 uv) {
	vec2 half_px = 0.5 / vec2(textureSize(tex, 0));
	vec4 a = texture(tex, uv + vec2(-half_px.x, -half_px.y));
	vec4 b = texture(tex, uv + vec2(half_px.x, -half_px.y));
	vec4 c = texture(tex, uv + vec2(-half_px.x, half_px.y));
	vec4 d = texture(tex, uv + vec2(half_px.x, half_px.y));
	return (a + b + c + d) * 0.25;
}

vec4 _aa_fxaa(sampler2D tex, vec2 uv) {
	vec2 px = 1.0 / vec2(textureSize(tex, 0));
	vec4 center = texture(tex, uv);
	float lt = _aa_luma(center);
	float lm = _aa_luma(texture(tex, uv + vec2(-px.x, 0.0)));
	float rm = _aa_luma(texture(tex, uv + vec2(px.x, 0.0)));
	float um = _aa_luma(texture(tex, uv + vec2(0.0, -px.y)));
	float dm = _aa_luma(texture(tex, uv + vec2(0.0, px.y)));

	float lmin = min(lt, min(min(lm, rm), min(um, dm)));
	float lmax = max(lt, max(max(lm, rm), max(um, dm)));
	float contrast = lmax - lmin;
	if (contrast < 0.0312) {
		return center;
	}

	float edge_h = abs(rm + lm - 2.0 * lt) * 2.0 + abs(dm + um - 2.0 * lt);
	float edge_v = abs(dm + um - 2.0 * lt) * 2.0 + abs(rm + lm - 2.0 * lt);
	vec2 dir = edge_h > edge_v ? vec2(0.0, px.y) : vec2(px.x, 0.0);

	vec4 e0 = texture(tex, uv + dir * 0.5);
	vec4 e1 = texture(tex, uv - dir * 0.5);
	vec4 avg = (e0 + e1) * 0.5;
	float strength = clamp(contrast / 0.125, 0.0, 1.0) * 0.75;
	return mix(center, avg, strength);
}

vec4 _aa_msaa_2x(sampler2D tex, vec2 uv) {
	vec2 px = 1.0 / vec2(textureSize(tex, 0));
	vec4 a = texture(tex, uv + vec2(-0.25, -0.25) * px);
	vec4 b = texture(tex, uv + vec2(0.25, 0.25) * px);
	return (a + b) * 0.5;
}

vec4 _aa_msaa_4x(sampler2D tex, vec2 uv) {
	vec2 px = 1.0 / vec2(textureSize(tex, 0));
	vec4 a = texture(tex, uv + vec2(-0.125, -0.375) * px);
	vec4 b = texture(tex, uv + vec2(0.375, -0.125) * px);
	vec4 c = texture(tex, uv + vec2(-0.375, 0.125) * px);
	vec4 d = texture(tex, uv + vec2(0.125, 0.375) * px);
	return (a + b + c + d) * 0.25;
}

vec4 _aa_sample(sampler2D tex, vec2 uv, int mode) {
	if (mode == AA_FEATHER) {
		return _aa_feather(tex, uv);
	}
	if (mode == AA_SUPERSAMPLE) {
		return _aa_supersample(tex, uv);
	}
	if (mode == AA_FXAA) {
		return _aa_fxaa(tex, uv);
	}
	if (mode == AA_MSAA_2X) {
		return _aa_msaa_2x(tex, uv);
	}
	if (mode == AA_MSAA_4X) {
		return _aa_msaa_4x(tex, uv);
	}
	return _aa_none(tex, uv);
}

#endif
