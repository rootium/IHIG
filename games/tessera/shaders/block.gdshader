shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// The solids of a chamber. Collision and the 4D slice are box-exact because
// they have to be — that is what keeps the fourth dimension cheap — but none
// of that is a reason for the surface to look like a box. Everything below is
// generated from the fragment's own position inside the chamber: carved panels
// set into each cell, chamfered borders, mineral veining, wear along the
// exposed edges, a lit seam where two cells meet, and a fresnel rim.
//
// No texture is sampled except one small tiling noise field, which is built at
// load time rather than shipped.

uniform sampler2D grain : hint_default_black, filter_linear_mipmap, repeat_enable;

uniform vec3 body_color : source_color = vec3(0.49, 0.55, 0.74);
uniform vec3 edge_color : source_color = vec3(0.38, 0.85, 1.0);
uniform vec3 deep_color : source_color = vec3(0.09, 0.11, 0.20);
uniform float edge_width = 0.04;
uniform float edge_gain = 0.55;
uniform float seam_gain = 0.16;
uniform float panel_inset = 0.11;
uniform float bevel = 0.045;
uniform float vein_gain = 0.22;
uniform float rim_gain = 0.32;
uniform float wear = 0.5;
uniform vec3 fog_color : source_color = vec3(0.024, 0.027, 0.055);
uniform float fog_start = 22.0;
uniform float fog_end = 62.0;
uniform float pulse = 0.0;
uniform float dissolve = 0.0;
// Cutaway: anything standing between the camera and the player is dithered
// away, so an isometric chamber stays playable when you walk behind a wall.
uniform vec3 player_pos = vec3(0.0);
uniform float cut_radius = 0.075;
uniform float cut_feather = 0.075;

varying vec3 v_local;
varying vec3 v_size;
varying vec3 v_wn;
varying vec3 v_wp;
varying vec3 v_view;
varying float v_depth;
varying vec2 v_ndc;
varying vec2 v_pndc;
varying float v_pdepth;

void vertex() {
	v_local = VERTEX;
	// The instance transform is a pure axis-aligned scale, so its column
	// lengths are exactly the box's world size. Reading it here avoids having
	// to ship a second per-instance buffer.
	v_size = max(vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)), vec3(0.0005));
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_view = normalize(CAMERA_POSITION_WORLD - v_wp);
	v_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;

	vec4 fc = PROJECTION_MATRIX * VIEW_MATRIX * vec4(v_wp, 1.0);
	vec4 pc = PROJECTION_MATRIX * VIEW_MATRIX * vec4(player_pos, 1.0);
	v_ndc = fc.xy / max(fc.w, 1e-5);
	v_pndc = pc.xy / max(pc.w, 1e-5);
	v_pdepth = -(VIEW_MATRIX * vec4(player_pos, 1.0)).z;
}

// Two tangent axes of an axis-aligned face, picked from its normal.
void face_basis(vec3 n, out vec3 t, out vec3 b) {
	vec3 a = abs(n);
	if (a.x > 0.5) { t = vec3(0.0, 0.0, 1.0); b = vec3(0.0, 1.0, 0.0); }
	else if (a.y > 0.5) { t = vec3(1.0, 0.0, 0.0); b = vec3(0.0, 0.0, 1.0); }
	else { t = vec3(1.0, 0.0, 0.0); b = vec3(0.0, 1.0, 0.0); }
}

float band(float x, float w) {
	return smoothstep(0.0, w, x);
}

void fragment() {
	// Position within the box, in world units, and in chamber cell units.
	vec3 p = v_local * v_size;
	vec3 cellpos = v_wp;

	vec3 tan_u, tan_v;
	face_basis(v_wn, tan_u, tan_v);
	vec2 uv = vec2(dot(cellpos, tan_u), dot(cellpos, tan_v));

	// --- carved panel, one per cell of the face -----------------------------
	vec2 f = fract(uv) - 0.5;
	vec2 dist_edge = vec2(0.5) - abs(f);              // 0 at the cell border
	float m = min(dist_edge.x, dist_edge.y);
	float panel = band(m - panel_inset, bevel);        // 1 inside the recess
	float chamfer = band(m, panel_inset * 0.55) * (1.0 - panel);
	float seam = 1.0 - band(m, 0.035);

	// --- box edges ----------------------------------------------------------
	vec3 d = (vec3(0.5) - abs(v_local)) * v_size;
	float lo = min(d.x, min(d.y, d.z));
	float hi = max(d.x, max(d.y, d.z));
	float mid = d.x + d.y + d.z - lo - hi;
	float edge = 1.0 - smoothstep(0.0, edge_width * 2.0, mid);

	// --- material -----------------------------------------------------------
	float g0 = texture(grain, uv * 0.37).r;
	float g1 = texture(grain, uv * 1.9 + vec2(0.31, 0.77)).g;
	float g2 = texture(grain, uv * 7.3).b;

	// Mineral veining: thin bright threads where the noise field crosses a level.
	float vein = 1.0 - smoothstep(0.0, 0.045, abs(g0 - 0.5));

	// Fake surface relief. The recessed panel sits lower, the chamfer catches
	// the key light, and the micro-noise roughens the whole thing.
	vec3 relief = v_wn;
	relief += tan_u * ((g1 - 0.5) * 0.35 + (f.x > 0.0 ? -chamfer : chamfer) * 0.9);
	relief += tan_v * ((g2 - 0.5) * 0.25 + (f.y > 0.0 ? -chamfer : chamfer) * 0.9);
	relief = normalize(relief);

	vec3 key_dir = normalize(vec3(0.42, 0.86, 0.28));
	vec3 fill_dir = normalize(vec3(-0.55, 0.25, -0.7));
	float lam = 0.52
		+ 0.62 * clamp(dot(relief, key_dir), 0.0, 1.0)
		+ 0.30 * clamp(dot(relief, fill_dir), 0.0, 1.0);
	lam *= mix(1.0, 0.58, clamp(-v_wn.y, 0.0, 1.0));   // undersides fall away
	lam *= mix(0.82, 1.0, panel * 0.35 + 0.65);        // the recess is in shade

	vec3 base = mix(deep_color, body_color, 0.80 + 0.20 * g1);
	base *= lam;
	base = mix(base, base * 1.35 + edge_color * 0.03, chamfer);       // lit bevel
	base += edge_color * vein * vein_gain * (0.35 + 0.65 * panel);    // veining
	base *= mix(1.0, 0.80 + 0.20 * g2, wear);                        // wear

	// Glowing seams between cells, and along the box's own edges.
	float glow = seam * seam_gain + edge * edge_gain;
	glow *= 0.85 + 0.15 * sin(TIME * 1.7 + (v_wp.x + v_wp.y + v_wp.z) * 0.6);
	base += edge_color * glow;
	base += edge_color * pulse * (0.25 + 0.75 * seam);

	// Rim light picks the silhouette out of the void.
	float fres = pow(1.0 - clamp(dot(relief, v_view), 0.0, 1.0), 3.0);
	base += edge_color * fres * rim_gain;

	float fog = clamp((v_depth - fog_start) / max(fog_end - fog_start, 0.001), 0.0, 1.0);
	ALBEDO = mix(base, fog_color, fog * 0.92);

	// Screen-space cutaway. A stable per-pixel hash makes the dissolve read as
	// a grain of the wall coming apart rather than as a hole cut in it.
	float cut = 0.0;
	if (v_depth < v_pdepth - 0.35) {
		vec2 sd = (v_ndc - v_pndc) * vec2(VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0), 1.0);
		cut = 1.0 - smoothstep(cut_radius, cut_radius + cut_feather, length(sd));
		cut *= clamp((v_pdepth - v_depth) * 0.7, 0.0, 1.0);
	}
	if (cut > 0.04) {
		// An ordered dither reads as a screen being cut away. White noise reads
		// as the wall being damaged.
		ivec2 px = ivec2(FRAGCOORD.xy) % 4;
		const int BAYER[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
		float t = float(BAYER[px.y * 4 + px.x]) / 16.0;
		ALBEDO = mix(ALBEDO, edge_color * 0.6, cut * 0.35);
		if (t < cut * 0.97) discard;
	}

	if (dissolve > 0.0) {
		float r = fract(sin(dot(floor(p * 3.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		if (r < dissolve) discard;
	}
}
