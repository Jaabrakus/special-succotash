shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled;

// World-meter surface masks. No geometry displacement or collision change.
uniform vec4 yard_bounds = vec4(-17.0, 8.0, 13.0, 24.5);
uniform float strength : hint_range(0.0, 1.0) = 0.45;
varying vec3 world_position;
varying vec3 world_normal;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float grain(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0)), f.x), f.y);
}
float band(float d, float half_width) {
	float aa = max(fwidth(d), 0.006);
	return 1.0 - smoothstep(half_width - aa, half_width + aa, abs(d));
}
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	vec2 p = world_position.xz;
	float edge = min(min(p.x - yard_bounds.x, yard_bounds.z - p.x),
		min(p.y - yard_bounds.y, yard_bounds.w - p.y));
	float region = smoothstep(0.0, 1.8, edge) * step(0.8, world_normal.y);
	float broad = grain(p * 0.38);
	float wear = grain(p * 6.0);
	vec3 surface = mix(vec3(0.17, 0.18, 0.17), vec3(0.38, 0.32, 0.23), broad);
	float turn = sin(p.y * 0.12) * 0.8;
	float tires = 1.0 - smoothstep(0.08, 0.24, min(abs(p.x + 3.8 + turn), abs(p.x + 2.1 + turn)));
	tires *= smoothstep(0.18, 0.7, broad) * (0.65 + 0.35 * wear);
	surface *= 1.0 - tires * 0.48;
	float oil = 1.0 - smoothstep(0.25, 1.7, length((p - vec2(-12.5, 10.0)) * vec2(0.7, 1.0)) + wear * 0.45);
	surface = mix(surface, vec3(0.075, 0.07, 0.055), oil * 0.8);
	float length_mask = step(10.0, p.y) * step(p.y, 22.5);
	float paint = max(band(p.x + 5.3, 0.07), band(p.x - 2.5, 0.07)) * length_mask;
	float hatch_box = step(-11.4, p.x) * step(p.x, -5.8) * step(15.3, p.y) * step(p.y, 16.3);
	float hatch = step(0.52, fract((p.x + p.y) * 1.3)) * hatch_box;
	paint = max(paint, hatch) * smoothstep(0.28, 0.65, wear);
	surface = mix(surface, vec3(0.40, 0.30, 0.12), paint * 0.9);
	ALBEDO = surface;
	ROUGHNESS = 0.95;
	ALPHA = region * strength;
}
