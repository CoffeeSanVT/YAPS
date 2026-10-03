#ifndef OUTLINE_INCLUDED
#define OUTLINE_INCLUDED

void outline_scan(vec2 uv, vec2 texture_pixel_size, float width, float solid_cutoff, float blend,
		sampler2D cur_tex, sampler2D next_tex, out float solid_dist, out float empty_dist) {
	solid_dist = width + 1.0;
	empty_dist = width + 1.0;

	for (float i = -ceil(width); i <= ceil(width); i++) {
		float x = abs(i) > width ? width * sign(i) : i;
		float offset = floor(sqrt(pow(width + 0.5, 2.0) - x * x));

		for (float j = -ceil(offset); j <= ceil(offset); j++) {
			float y = abs(j) > offset ? offset * sign(j) : j;

			float d = length(vec2(x, y));
			if (d >= solid_dist && d >= empty_dist) {
				continue;
			}

			vec2 xy = uv + texture_pixel_size * vec2(x, y);

			float a = 0.0;
			bool oob = xy != clamp(xy, vec2(0.0), vec2(1.0));
			if (!oob) {
				if (blend <= 0.0) {
					a = texture(cur_tex, xy).a;
				} else if (blend >= 1.0) {
					a = texture(next_tex, xy).a;
				} else {
					a = mix(texture(cur_tex, xy).a, texture(next_tex, xy).a, blend);
				}
			}

			if (!oob && a >= solid_cutoff) {
				solid_dist = min(solid_dist, d);
			} else {
				empty_dist = min(empty_dist, d);
			}
		}
	}
}

float outline_halftone_mask(vec2 frag_coord, float coverage, float dot_size) {
	vec2 cell = fract(frag_coord / dot_size) - 0.5;
	float dist = length(cell) * 2.0;
	float radius = coverage * 0.9;
	float delta = fwidth(dist);
	return smoothstep(radius + delta, radius - delta, dist);
}

#endif
