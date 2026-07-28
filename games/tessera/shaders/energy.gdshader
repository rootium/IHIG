shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Shared by every glowing prop: the player's tesseract, the exit ring, key
// sigils and shards. Faceted meshes arrive with per-face vertex colours, so
// the shading here is a hard key light plus a fresnel rim and a travelling
// pulse — enough to make a cut surface look cut.

uniform vec3 tint : source_color = vec3(1.0, 0.85, 0.55);
uniform float glow = 1.35;
uniform float rim = 1.1;
uniform float flow = 1.0;
uniform float flicker = 0.06;
uniform float alpha = 1.0;

varying vec3 v_n;
varying vec3 v_local;
varying vec3 v_view;
varying vec4 v_col;

void vertex() {
	v_local = VERTEX;
	v_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_col = COLOR;
	v_view = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float lam = 0.34 + 0.66 * clamp(dot(v_n, normalize(vec3(0.4, 0.85, 0.35))), 0.0, 1.0);
	float fres = pow(1.0 - clamp(dot(v_n, v_view), 0.0, 1.0), 2.6);

	// A charge running along the piece, plus a faint irregular flicker.
	float travel = 0.5 + 0.5 * sin(v_local.y * 7.0 - TIME * 3.1 * flow);
	float noise = 0.5 + 0.5 * sin(TIME * 21.0 + v_local.x * 13.0);

	vec3 c = tint * v_col.rgb * (lam * glow + travel * 0.35);
	c += tint * fres * rim;
	c *= 1.0 + flicker * (noise - 0.5);

	ALBEDO = c;
	ALPHA = alpha * v_col.a;
}
