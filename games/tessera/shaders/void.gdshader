shader_type sky;

// The void the chambers hang in: a cold vertical gradient, a slow band of
// nebula, and a scatter of stars that drift when the world rotates through the
// fourth dimension.

uniform vec3 top_color : source_color = vec3(0.012, 0.014, 0.035);
uniform vec3 horizon_color : source_color = vec3(0.055, 0.075, 0.16);
uniform vec3 bottom_color : source_color = vec3(0.008, 0.010, 0.024);
uniform vec3 nebula_color : source_color = vec3(0.16, 0.10, 0.34);
uniform float star_density = 0.9;
uniform float warp = 0.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// Stars are scattered on cube faces. Spherical coordinates squash the cells
// towards the poles and smear every dot into a streak; a cube face keeps them
// square, and at this size the face seams are invisible.
float stars(vec3 dir, float scale, float thresh) {
	vec3 a = abs(dir);
	vec2 face;
	if (a.x >= a.y && a.x >= a.z) face = dir.yz / a.x;
	else if (a.y >= a.z) face = dir.xz / a.y;
	else face = dir.xy / a.z;
	vec2 g = face * scale;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float best = 0.0;
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			vec2 nb = vec2(float(i), float(j));
			float h = hash13(vec3(cell + nb, 3.7));
			if (h < thresh) continue;
			vec2 pos = nb + vec2(hash13(vec3(cell + nb, 11.3)), hash13(vec3(cell + nb, 5.1)));
			float d = length(f - pos);
			best = max(best, smoothstep(0.20, 0.0, d) * (0.3 + h * 0.7));
		}
	}
	return best;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;

	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.75, h));
	col = mix(col, bottom_color, smoothstep(0.0, -0.55, h));

	// A soft diagonal band, nudged sideways while a rotation is in progress so
	// the backdrop admits that something structural just happened.
	float band = exp(-pow((dir.x * 0.6 + dir.y * 1.4 + warp * 0.6), 2.0) * 2.2);
	col += nebula_color * band * 0.28;

	float s = stars(dir, 22.0, 0.55) + stars(dir, 44.0, 0.78) * 0.45;
	col += vec3(0.72, 0.82, 1.0) * s * star_density;

	COLOR = col;
}
