shader_type spatial;
// Additive fresnel rim drawn as a second pass over the explorer's materials, so
// the character keeps a faint cool outline in total darkness.
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 rim_color : source_color = vec3(0.62, 0.66, 0.72);
uniform float strength = 0.55;
uniform float power = 3.0;

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), power);
	ALBEDO = rim_color * f * strength;
}
