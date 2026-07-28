shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// Slices you are not standing in, drawn as edges only. Without these the
// fourth dimension is unreadable — you would be guessing at what lies one step
// ana or kata of you. With them the chamber becomes legible: warm outlines are
// ahead of you along the hidden axis, cool ones behind.

uniform float edge_width = 0.055;
uniform vec3 tint : source_color = vec3(0.37, 0.82, 1.0);
uniform float alpha = 0.6;
uniform float intensity = 1.0;
uniform float fog_start = 22.0;
uniform float fog_end = 62.0;

varying vec3 v_local;
varying vec3 v_size;
varying float v_depth;

void vertex() {
	v_local = VERTEX;
	// The instance transform is a pure axis-aligned scale, so its column
	// lengths are exactly the box's world size. Reading it here avoids
	// having to ship a second per-instance buffer.
	v_size = max(vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)), vec3(0.0005));
	v_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec3 d = (vec3(0.5) - abs(v_local)) * v_size;
	float lo = min(d.x, min(d.y, d.z));
	float hi = max(d.x, max(d.y, d.z));
	float mid = d.x + d.y + d.z - lo - hi;
	float edge = 1.0 - smoothstep(0.0, edge_width * 2.2, mid);
	if (edge < 0.004) discard;

	float fog = 1.0 - clamp((v_depth - fog_start) / max(fog_end - fog_start, 0.001), 0.0, 1.0);
	ALBEDO = tint;
	ALPHA = edge * alpha * intensity * fog;
}
