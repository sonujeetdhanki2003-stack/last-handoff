shader_type spatial;
// Facility surface: world-space triplanar PBR with procedural wear so every wall,
// floor and ceiling reads as abandoned: dirt that climbs up from the floor, water
// streaks running down walls, blotchy mottling, and optional two-tone paint.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D grime_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec3 tint : source_color = vec3(1.0);
uniform float scale = 0.35;            // texture repeats per metre
uniform float normal_strength = 1.0;
uniform float rough_mul = 1.0;
uniform float rough_add = 0.0;
uniform float metallic = 0.0;
uniform float ao_strength = 0.8;

uniform float floor_y = 0.0;
uniform float dirt_height = 0.7;
uniform float dirt_strength = 0.55;
uniform vec3 dirt_color : source_color = vec3(0.09, 0.075, 0.06);
uniform float streak_strength = 0.35;
uniform float mottle_strength = 0.35;
uniform float wet = 0.0;               // 0..1 darker + glossier patches (floors)

// Two-tone paint (luminance of the albedo recoloured): band_y <= 0 disables.
uniform float band_y = 0.0;
uniform vec3 lower_color : source_color = vec3(0.24, 0.33, 0.29);
uniform vec3 upper_color : source_color = vec3(0.62, 0.6, 0.52);
uniform float paint_mix = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri_w(vec3 n) {
	vec3 b = pow(abs(n), vec3(6.0));
	return b / (b.x + b.y + b.z);
}

void fragment() {
	vec3 b = tri_w(wnrm);
	vec2 ux = vec2(wpos.z, -wpos.y) * scale;
	vec2 uy = wpos.xz * scale;
	vec2 uz = vec2(wpos.x, -wpos.y) * scale;
	vec3 alb = texture(albedo_tex, ux).rgb * b.x + texture(albedo_tex, uy).rgb * b.y + texture(albedo_tex, uz).rgb * b.z;
	float rgh = texture(rough_tex, ux).r * b.x + texture(rough_tex, uy).r * b.y + texture(rough_tex, uz).r * b.z;
	float ao = texture(ao_tex, ux).r * b.x + texture(ao_tex, uy).r * b.y + texture(ao_tex, uz).r * b.z;

	vec3 tx = texture(normal_tex, ux).xyz * 2.0 - 1.0;
	vec3 ty = texture(normal_tex, uy).xyz * 2.0 - 1.0;
	vec3 tz = texture(normal_tex, uz).xyz * 2.0 - 1.0;
	tx.xy *= normal_strength; ty.xy *= normal_strength; tz.xy *= normal_strength;
	tx = vec3(tx.xy + wnrm.zy, abs(tx.z) * wnrm.x);
	ty = vec3(ty.xy + wnrm.xz, abs(ty.z) * wnrm.y);
	tz = vec3(tz.xy + wnrm.xy, abs(tz.z) * wnrm.z);
	vec3 wn = normalize(tx.zyx * b.x + ty.xzy * b.y + tz.xyz * b.z);

	// --- paint
	if (paint_mix > 0.0) {
		float lum = dot(alb, vec3(0.3, 0.55, 0.15));
		vec3 pc = (band_y > 0.0 && wpos.y - floor_y < band_y) ? lower_color : upper_color;
		alb = mix(alb, pc * lum * 2.2, paint_mix);
		if (band_y > 0.0) {
			float line = 1.0 - smoothstep(0.0, 0.035, abs(wpos.y - floor_y - band_y));
			alb = mix(alb, vec3(0.05), line * 0.85 * (1.0 - b.y));
		}
	}
	alb *= tint;

	// --- wear
	float g_big = texture(grime_tex, (wpos.xz + wpos.y * 0.37) * 0.07).r;
	float g_mid = texture(grime_tex, (wpos.xz * 0.9 + vec2(wpos.y * 0.5)) * 0.31).g;
	float side = 1.0 - b.y;
	vec2 su = vec2((wpos.x + wpos.z) * 1.1, wpos.y * 0.06);
	float streak = smoothstep(0.45, 0.85, texture(grime_tex, su).b) * side;
	streak *= smoothstep(-0.2, 0.6, g_big);
	float h = wpos.y - floor_y;
	float dirt = (1.0 - smoothstep(0.0, dirt_height, h + (g_mid - 0.5) * 0.35)) * side;
	float fl = b.y * step(0.0, wnrm.y) * smoothstep(0.35, 0.8, g_big) * 0.8;
	float d = clamp(dirt * dirt_strength + fl * dirt_strength, 0.0, 0.95);
	alb *= mix(1.0, 0.55 + 0.55 * g_mid, mottle_strength);
	alb = mix(alb, dirt_color * (0.7 + 0.6 * g_mid), d);
	alb = mix(alb, alb * vec3(0.55, 0.5, 0.42), streak * streak_strength);
	float w = wet * smoothstep(0.55, 0.75, g_big) * b.y;
	alb *= 1.0 - 0.45 * w;

	ALBEDO = alb;
	ROUGHNESS = clamp(rgh * rough_mul + rough_add + d * 0.15 - w * 0.75, 0.04, 1.0);
	METALLIC = metallic;
	AO = mix(1.0, ao, ao_strength);
	AO_LIGHT_AFFECT = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
