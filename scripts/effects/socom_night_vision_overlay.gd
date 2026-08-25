class_name SocomNightVisionOverlay
extends CanvasLayer

## Authentic SOCOM 2 Night Vision Goggles (NVG) Visual System
## Ported from reCOM (zSeal/zseal.h m_nvg_enabled, m_lensfx_enable)

signal nvg_toggled(enabled: bool)

@export var is_nvg_active: bool = false
@export_range(1.0, 6.0, 0.1) var exposure_gain: float = 3.2
@export_range(0.35, 1.0, 0.01) var luminance_gamma: float = 0.62
@export var phosphor_green := Color(0.14, 1.0, 0.22, 1.0)
@export var vignette_darkness := Color(0.02, 0.05, 0.02, 0.96)

var _overlay_rect: ColorRect
var _vignette_texture_rect: TextureRect
var _noise_timer: float = 0.0


func _ready() -> void:
	layer = 8
	_build_nvg_nodes()
	set_nvg_enabled(is_nvg_active)


func _build_nvg_nodes() -> void:
	# 1. Sample and amplify the rendered scene.  A translucent green rectangle
	# only tinted (and actually darkened) night maps; it never behaved like an
	# image intensifier.  This presentation shader raises shadow luminance while
	# preserving scene detail and has no gameplay/visibility authority.
	_overlay_rect = ColorRect.new()
	_overlay_rect.name = "NVGPhosphorTint"
	_overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_rect.color = Color.WHITE
	var intensifier := Shader.new()
	intensifier.code = """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float exposure_gain = 3.2;
uniform float luminance_gamma = 0.62;
uniform vec3 phosphor = vec3(0.14, 1.0, 0.22);

void fragment() {
	vec3 scene = texture(screen_texture, SCREEN_UV).rgb;
	float luminance = dot(scene, vec3(0.2126, 0.7152, 0.0722));
	float intensified = pow(clamp(luminance * exposure_gain, 0.0, 1.0), luminance_gamma);
	float highlight = smoothstep(0.70, 1.0, intensified);
	vec3 night_image = phosphor * intensified;
	night_image += vec3(highlight * 0.08);
	COLOR = vec4(night_image, 1.0);
}
"""
	var intensifier_material := ShaderMaterial.new()
	intensifier_material.shader = intensifier
	intensifier_material.set_shader_parameter("exposure_gain", exposure_gain)
	intensifier_material.set_shader_parameter("luminance_gamma", luminance_gamma)
	intensifier_material.set_shader_parameter(
		"phosphor",
		Vector3(phosphor_green.r, phosphor_green.g, phosphor_green.b)
	)
	_overlay_rect.material = intensifier_material
	_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay_rect)

	# 2. Circular NVG Iris Vignette Mask
	var vignette_img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var center := Vector2(128, 128)
	var radius := 120.0
	for y in range(256):
		for x in range(256):
			var dist: float = Vector2(x, y).distance_to(center)
			if dist < radius * 0.75:
				vignette_img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				var alpha: float = clampf((dist - (radius * 0.75)) / (radius * 0.25), 0.0, 1.0)
				vignette_img.set_pixel(x, y, Color(0.01, 0.04, 0.01, alpha * 0.92))

	var v_tex := ImageTexture.create_from_image(vignette_img)
	_vignette_texture_rect = TextureRect.new()
	_vignette_texture_rect.name = "NVGIrisMask"
	_vignette_texture_rect.texture = v_tex
	_vignette_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette_texture_rect)


func toggle_nvg() -> void:
	set_nvg_enabled(not is_nvg_active)


func set_nvg_enabled(enabled: bool) -> void:
	is_nvg_active = enabled
	visible = enabled
	nvg_toggled.emit(enabled)
