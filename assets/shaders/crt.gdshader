shader_type spatial;
// Old CRT showing noise and a half-legible status screen with a rolling bar.
render_mode unshaded, cull_back;

uniform float energy = 1.4;
uniform vec3 tint : source_color = vec3(0.45, 1.0, 0.65);
uniform sampler2D content : source_color, hint_default_black;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	vec2 c = uv - 0.5;
	float vig = 1.0 - dot(c, c) * 1.6;
	float t = TIME;
	float jitter = (hash(vec2(floor(t * 18.0), floor(uv.y * 40.0))) - 0.5) * 0.012;
	vec3 img = texture(content, vec2(uv.x + jitter, uv.y)).rgb;
	float n = hash(uv * vec2(320.0, 240.0) + floor(t * 30.0));
	float scan = 0.75 + 0.25 * sin(uv.y * 480.0);
	float roll = smoothstep(0.0, 0.08, fract(uv.y - t * 0.17)) * (1.0 - smoothstep(0.08, 0.18, fract(uv.y - t * 0.17)));
	vec3 col = tint * (img * 1.2 + n * 0.22 + roll * 0.25) * scan * vig;
	ALBEDO = col * energy;
}
