shader_type sky;

uniform vec3 sky_top_color : source_color = vec3(0.015, 0.31, 0.62);
uniform vec3 sky_horizon_color : source_color = vec3(0.43, 0.75, 0.88);
uniform vec3 ground_color : source_color = vec3(0.18, 0.28, 0.24);

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
	float result = 0.0;
	float weight = 0.58;
	for (int octave = 0; octave < 4; octave++) {
		result += value_noise(p) * weight;
		p = p * 2.07 + vec2(13.7, 7.9);
		weight *= 0.47;
	}
	return result;
}

float longitude_distance(float value, float center) {
	float direct = abs(value - center);
	return min(direct, 1.0 - direct);
}

float cloud_lobe(vec2 point, vec2 center, vec2 radius) {
	vec2 delta = vec2(longitude_distance(point.x, center.x), point.y - center.y);
	return 1.0 - smoothstep(0.78, 1.05, length(delta / radius));
}

void sky() {
	vec3 direction = normalize(EYEDIR);
	float elevation = clamp(direction.y, -1.0, 1.0);
	float longitude = atan(direction.z, direction.x) / TAU;
	vec3 sky_color = mix(
		sky_horizon_color,
		sky_top_color,
		smoothstep(-0.02, 0.72, elevation)
	);

	// A small number of large lobes produces the monumental hand-painted cloud
	// silhouette. Noise only breaks its edge; it does not replace the shape.
	vec2 sphere_point = vec2(longitude, elevation);
	float tower = 0.0;
	tower = max(tower, cloud_lobe(sphere_point, vec2(0.03, 0.25), vec2(0.095, 0.23)));
	tower = max(tower, cloud_lobe(sphere_point, vec2(0.00, 0.48), vec2(0.075, 0.24)));
	tower = max(tower, cloud_lobe(sphere_point, vec2(-0.055, 0.35), vec2(0.070, 0.18)));
	tower = max(tower, cloud_lobe(sphere_point, vec2(0.070, 0.38), vec2(0.068, 0.17)));
	tower = max(tower, cloud_lobe(sphere_point, vec2(0.13, 0.20), vec2(0.10, 0.13)));
	float cloud_bank = smoothstep(0.31, 0.58, painted_noise(vec2(longitude * 7.0, elevation * 5.0) + vec2(4.2, 1.7)));
	cloud_bank *= smoothstep(0.015, 0.11, elevation) * (1.0 - smoothstep(0.23, 0.34, elevation));
	float edge_noise = painted_noise(vec2(longitude * 18.0, elevation * 13.0) + vec2(9.4, 3.1));
	float cloud_mask = clamp(max(tower + (edge_noise - 0.55) * 0.24, cloud_bank * 0.82), 0.0, 1.0);
	cloud_mask *= smoothstep(0.0, 0.045, elevation);

	float cloud_light = clamp(0.42 + elevation * 0.60 + (edge_noise - 0.5) * 0.28, 0.0, 1.0);
	vec3 cloud_shadow = vec3(0.34, 0.54, 0.68);
	vec3 cloud_mid = vec3(0.78, 0.88, 0.91);
	vec3 cloud_highlight = vec3(1.0, 0.98, 0.88);
	vec3 cloud_color = mix(cloud_shadow, cloud_mid, smoothstep(0.28, 0.64, cloud_light));
	cloud_color = mix(cloud_color, cloud_highlight, smoothstep(0.66, 0.94, cloud_light));
	sky_color = mix(sky_color, cloud_color, cloud_mask);

	if (LIGHT0_ENABLED) {
		float sun_alignment = dot(direction, normalize(LIGHT0_DIRECTION));
		float sun_disk = smoothstep(0.9995, 0.99992, sun_alignment);
		float sun_glow = pow(max(sun_alignment, 0.0), 72.0);
		sky_color += LIGHT0_COLOR * LIGHT0_ENERGY * (sun_glow * 0.08 + sun_disk * 0.56);
	}

	if (elevation < 0.0) {
		float ground_mix = smoothstep(-0.20, -0.01, elevation);
		sky_color = mix(ground_color * 0.54, sky_horizon_color * 0.60, ground_mix);
	}
	COLOR = sky_color;
}
