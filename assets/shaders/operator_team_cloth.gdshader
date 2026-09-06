shader_type spatial;
render_mode cull_back;
uniform sampler2D source_texture : source_color, filter_nearest, repeat_enable;
uniform vec4 base_tint : source_color = vec4(1.0);
uniform vec4 team_color : source_color = vec4(0.34, 0.62, 0.91, 1.0);
uniform float cloth_brightness = 1.0;
void fragment() {
    vec3 base = texture(source_texture, UV).rgb * base_tint.rgb;
    // Recolor the original blue cloth, not neutral straps, mask or gloves.
    float cloth = smoothstep(0.005, 0.06, base.b - base.r);
    float lightness = max(base.r, max(base.g, base.b));
    ALBEDO = mix(base, team_color.rgb * min(lightness * cloth_brightness, 1.0), cloth);
    ROUGHNESS = 1.0;
}
