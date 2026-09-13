shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float strength : hint_range(0.0, 0.12) = 0.0;

void fragment() {
    vec2 pixel = floor(FRAGCOORD.xy / 1.5);
    float frame = floor(TIME * 24.0);
    float noise = fract(sin(dot(pixel, vec2(12.9898, 78.233)) + frame * 11.73) * 43758.5453) - 0.5;
    vec3 scene = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
    COLOR = vec4(clamp(scene + noise * strength, vec3(0.0), vec3(1.0)), 1.0);
}
