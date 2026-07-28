shader_type canvas_item;

// The void the chambers hang in.
//
// This is drawn in screen space rather than as a sky, because the game's
// camera is orthographic: every ray through an orthographic frustum is
// parallel, so a sky shader has no meaningful eye direction to work with and
// smears its stars into radial streaks. Panning two parallax layers against
// the camera's own rotation gives the depth a skybox would have, and costs one
// full-screen quad.

uniform vec3 top_color : source_color = vec3(0.020, 0.024, 0.058);
uniform vec3 mid_color : source_color = vec3(0.055, 0.066, 0.145);
uniform vec3 bottom_color : source_color = vec3(0.008, 0.010, 0.026);
uniform vec3 nebula_color : source_color = vec3(0.20, 0.13, 0.42);
uniform vec2 pan = vec2(0.0);
uniform float aspect = 1.7777;
uniform float warp = 0.0;
uniform float brightness = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

// One layer of stars: a point per cell, with a soft round falloff.
float star_layer(vec2 uv, float scale, float thresh, float size) {
	vec2 g = uv * scale;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float acc = 0.0;
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			vec2 nb = vec2(float(i), float(j));
			float h = hash21(cell + nb);
			if (h < thresh) continue;
			vec2 at = nb + vec2(hash21(cell + nb + 17.0), hash21(cell + nb + 41.0));
			float d = length(f - at);
			float mag = (h - thresh) / max(1.0 - thresh, 1e-4);
			acc += smoothstep(size * (0.45 + 0.55 * mag), 0.0, d) * (0.25 + 0.75 * mag);
		}
	}
	return acc;
}

void fragment() {
	vec2 uv = vec2((UV.x - 0.5) * aspect, UV.y - 0.5);

	// vertical gradient, brightest a little above the middle
	float v = UV.y;
	vec3 col = mix(mid_color, top_color, smoothstep(0.42, 0.0, v));
	col = mix(col, bottom_color, smoothstep(0.52, 1.0, v));

	// a slow nebula, nudged sideways while a rotation is in progress so the
	// backdrop admits that something structural just happened
	vec2 nb = uv - vec2(-0.24 + warp * 0.16, -0.10);
	float cloud = exp(-dot(nb, nb) * 3.1);
	cloud += 0.55 * exp(-dot(uv - vec2(0.33, 0.20), uv - vec2(0.33, 0.20)) * 7.0);
	col += nebula_color * cloud * 0.30;

	// two parallax layers, the far one barely moving
	float s = star_layer(uv + pan * 0.35, 9.0, 0.72, 0.055) * 0.85;
	s += star_layer(uv + pan * 0.80, 21.0, 0.86, 0.035) * 0.55;
	s += star_layer(uv + pan * 1.30, 44.0, 0.93, 0.022) * 0.35;
	col += vec3(0.78, 0.86, 1.0) * s;

	// vignette, so the chamber always sits in the brightest part of the frame
	col *= 1.0 - 0.55 * smoothstep(0.35, 0.95, length(uv));

	COLOR = vec4(col * brightness, 1.0);
}
