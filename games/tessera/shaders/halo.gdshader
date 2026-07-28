shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, depth_test_disabled;

// A soft additive shell around the player. The tesseract is mostly thin edges,
// and against a chamber wall of the same brightness it stops being the thing
// your eye goes to. This puts a glow behind it that nothing occludes, so the
// player is always findable — which matters most in exactly the moment it is
// hardest, halfway through a rotation with the whole room sweeping past.
//
// Culling front faces and reading the inverted fresnel makes the shell densest
// at its centre and fade to nothing at its silhouette, so it reads as light
// rather than as a bubble.

uniform vec3 tint : source_color = vec3(1.0, 0.79, 0.47);
uniform float strength = 0.5;
uniform float falloff = 2.2;

varying vec3 v_n;
varying vec3 v_view;

void vertex() {
	v_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_view = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float centre = pow(clamp(dot(-v_n, v_view), 0.0, 1.0), falloff);
	float pulse = 0.86 + 0.14 * sin(TIME * 2.3);
	ALBEDO = tint;
	ALPHA = centre * strength * pulse;
}
