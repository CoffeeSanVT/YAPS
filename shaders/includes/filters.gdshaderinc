#ifndef FILTERS_INCLUDED
#define FILTERS_INCLUDED

const int FILTER_NONE = 0;
const int FILTER_WARP = 1;
const int FILTER_DARKEN = 2;

vec2 filter_warp(vec2 uv, float amount, float time) {
	uv.x += sin(uv.y * 12.0 + time * 24.0) * amount * 0.03;
	return uv;
}

vec4 filter_darken(vec4 color, float amount) {
	color.rgb *= (1.0 - amount);
	return color;
}

#endif
