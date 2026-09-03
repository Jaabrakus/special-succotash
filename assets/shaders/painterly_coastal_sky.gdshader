shader_type sky;

uniform vec3 sky_top_color : source_color = vec3(0.18, 0.44, 0.62);
uniform vec3 sky_horizon_color : source_color = vec3(0.90, 0.76, 0.61);
uniform vec3 ground_color : source_color = vec3(0.44, 0.40, 0.33);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

float painted_noise(vec2 p) {
	float value = 0.0;
	float weight = 0.56;
	for (int octave = 0; octave < 4; octave++) {
		value += value_noise(p) * weight;
		p = p * 2.03 + vec2(17.3, 9.2);
		weight *= 0.48;
	}
	return value;
}

void sky() {
	vec3 direction = normalize(EYEDIR);
	float elevation = clamp(direction.y, -1.0, 1.0);
	float upper_mix = smoothstep(-0.03, 0.78, elevation);
	vec3 sky_color = mix(sky_horizon_color, sky_top_color, upper_mix);

	float longitude = atan(direction.z, direction.x) / TAU;
	vec2 cloud_uv = vec2(longitude * 3.4, elevation * 3.1);
	float broad_cloud = painted_noise(cloud_uv * vec2(1.15, 0.72) + vec2(2.4, 8.1));
	float cloud_detail = painted_noise(cloud_uv * vec2(2.3, 1.45) + vec2(11.7, 3.6));
	float cloud_field = broad_cloud * 0.72 + cloud_detail * 0.28;
	float horizon_gate = smoothstep(0.01, 0.16, elevation) * (1.0 - smoothstep(0.78, 0.98, elevation));
	float cloud_mask = smoothstep(0.50, 0.68, cloud_field) * horizon_gate;
	float cloud_light = smoothstep(0.42, 0.80, broad_cloud + elevation * 0.18);
	vec3 cloud_shadow = mix(vec3(0.34, 0.42, 0.50), sky_horizon_color * 0.72, 0.34);
	vec3 cloud_highlight = vec3(1.0, 0.93, 0.79);
	vec3 clouds = mix(cloud_shadow, cloud_highlight, cloud_light);
	sky_color = mix(sky_color, clouds, cloud_mask * 0.88);

	if (LIGHT0_ENABLED) {
		float sun_alignment = dot(direction, normalize(LIGHT0_DIRECTION));
		float sun_disk = smoothstep(0.99945, 0.99990, sun_alignment);
		float sun_glow = pow(max(sun_alignment, 0.0), 64.0);
		sky_color += LIGHT0_COLOR * LIGHT0_ENERGY * (sun_glow * 0.11 + sun_disk * 0.68);
	}

	if (elevation < 0.0) {
		float ground_mix = smoothstep(-0.18, -0.01, elevation);
		sky_color = mix(ground_color * 0.52, sky_horizon_color * 0.70, ground_mix);
	}
	COLOR = sky_color;
}
