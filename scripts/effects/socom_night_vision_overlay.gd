class_name SocomNightVisionOverlay
extends CanvasLayer

## Stylized blue night vision; local presentation only.
const PROFILE_PATH := "res://config/night_vision.json"

signal nvg_toggled(enabled: bool)

@export var is_nvg_active: bool = false
@export_range(1.0, 10.0, 0.1) var exposure_gain: float = 3.0
@export_range(0.20, 1.0, 0.01) var luminance_gamma: float = 0.65
@export var ambient_lift: float = 0.025
@export var phosphor_tint := Color(0.45, 0.72, 1.0, 1.0)
@export var vignette_darkness := Color(0.01, 0.02, 0.05, 0.22)

var _overlay_rect: ColorRect
var _vignette_texture_rect: TextureRect
var _noise_timer: float = 0.0
var _ir_light: SpotLight3D


func _ready() -> void:
	layer = 8
	_load_profile()
	_build_nvg_nodes()
	set_nvg_enabled(is_nvg_active)


func _exit_tree() -> void:
	if _ir_light != null and is_instance_valid(_ir_light):
		_ir_light.queue_free()
		_ir_light = null


func _load_profile() -> void:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not value is Dictionary:
		return
	exposure_gain = clampf(float(value.get("exposure_gain", exposure_gain)), 1.0, 10.0)
	luminance_gamma = clampf(float(value.get("luminance_gamma", luminance_gamma)), 0.2, 1.0)
	ambient_lift = clampf(float(value.get("ambient_lift", ambient_lift)), 0.0, 0.1)
	vignette_darkness.a = clampf(float(value.get("vignette_alpha", 0.22)), 0.0, 0.5)
	var rgb: Array = value.get("phosphor_rgb", [0.45, 0.72, 1.0])
	if rgb.size() == 3:
		phosphor_tint = Color(clampf(float(rgb[0]), 0, 1), clampf(float(rgb[1]), 0, 1), clampf(float(rgb[2]), 0, 1))


func _build_nvg_nodes() -> void:
	# One screen sample; compress highlights while lifting distinct dark shades.
	_overlay_rect = ColorRect.new()
	_overlay_rect.name = "NVGPhosphorTint"
	_overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_rect.color = Color.WHITE
	var intensifier := Shader.new()
	intensifier.code = """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float exposure_gain = 3.0;
uniform float luminance_gamma = 0.65;
uniform float ambient_lift = 0.025;
uniform vec3 phosphor = vec3(0.45, 0.72, 1.0);

void fragment() {
	vec3 scene = texture(screen_texture, SCREEN_UV).rgb;
	float raw_lum = dot(scene, vec3(0.2126, 0.7152, 0.0722));
	float boosted_lum = exposure_gain * raw_lum / (1.0 + (exposure_gain - 1.0) * raw_lum);
	float intensified = pow(clamp(boosted_lum, 0.0, 1.0), luminance_gamma);
	intensified = ambient_lift + (1.0 - ambient_lift) * intensified;
	vec3 tint = mix(phosphor, vec3(0.82, 0.90, 1.0), smoothstep(0.65, 1.0, intensified));
	vec3 night_image = tint * intensified;
	COLOR = vec4(clamp(night_image, 0.0, 1.0), 1.0);
}
"""
	var intensifier_material := ShaderMaterial.new()
	intensifier_material.shader = intensifier
	intensifier_material.set_shader_parameter("exposure_gain", exposure_gain)
	intensifier_material.set_shader_parameter("luminance_gamma", luminance_gamma)
	intensifier_material.set_shader_parameter("ambient_lift", ambient_lift)
	intensifier_material.set_shader_parameter(
		"phosphor",
		Vector3(phosphor_tint.r, phosphor_tint.g, phosphor_tint.b)
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
				vignette_img.set_pixel(x, y, Color(vignette_darkness.r, vignette_darkness.g, vignette_darkness.b, alpha * vignette_darkness.a))

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
	_update_ir_illuminator(enabled)
	nvg_toggled.emit(enabled)


func _update_ir_illuminator(enabled: bool) -> void:
	if _ir_light == null or not is_instance_valid(_ir_light):
		var vp := get_viewport()
		var camera := vp.get_camera_3d() if vp != null else null
		if camera != null:
			_ir_light = SpotLight3D.new()
			_ir_light.name = "NVG_IR_Illuminator"
			_ir_light.light_color = Color(0.85, 1.0, 0.88)
			_ir_light.light_energy = 2.5
			_ir_light.spot_range = 45.0
			_ir_light.spot_angle = 72.0
			_ir_light.spot_attenuation = 1.1
			_ir_light.shadow_enabled = false
			camera.add_child(_ir_light)
	if _ir_light != null and is_instance_valid(_ir_light):
		_ir_light.visible = enabled
