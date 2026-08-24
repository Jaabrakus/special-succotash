class_name TacticalScreenEffects
extends CanvasLayer

const FoleyEngine := preload("res://scripts/audio/tactical_foley_engine.gd")
const FlashbangScript := preload("res://scripts/tactical/flashbang_grenade.gd")

var camera: Camera3D
var flash_strength := 0.0
var flash_peak_strength := 0.0
var flash_hold_remaining := 0.0
var flash_recovery_elapsed := 0.0
var flash_recovery_progress := 1.0
var flash_duration_weight := 0.0
var smoke_strength := 0.0
var shake_strength := 0.0
var _flash_rect: ColorRect
var _smoke_rect: ColorRect
var _foley: Node
var _presentation_settings: Node
var _effects_bus_original_db := 0.0
var _base_h_offset := 0.0
var _base_v_offset := 0.0


func _ready() -> void:
	add_to_group("tactical_screen_effects")
	layer = 95
	_flash_rect = _make_overlay(Color.WHITE)
	_configure_flash_material()
	_smoke_rect = _make_overlay(Color(0.40, 0.43, 0.40, 1.0))
	_foley = FoleyEngine.new()
	add_child(_foley)
	_presentation_settings = get_node_or_null("/root/PresentationSettings")
	var effects_bus := AudioServer.get_bus_index(&"Effects")
	_effects_bus_original_db = AudioServer.get_bus_volume_db(effects_bus) if effects_bus >= 0 else 0.0


func bind_camera(target: Camera3D) -> void:
	camera = target
	if camera != null:
		_base_h_offset = camera.h_offset
		_base_v_offset = camera.v_offset


func _exit_tree() -> void:
	if _presentation_settings != null:
		_presentation_settings.call("set_effects_duck_db", 0.0)
	else:
		var effects_bus := AudioServer.get_bus_index(&"Effects")
		if effects_bus >= 0:
			AudioServer.set_bus_volume_db(effects_bus, _effects_bus_original_db)
	if camera != null:
		camera.h_offset = _base_h_offset
		camera.v_offset = _base_v_offset


func _process(delta: float) -> void:
	_update_flash_recovery(delta)
	if camera != null:
		var manager := get_node_or_null("/root/TacticalOcclusionManager")
		var target_density := float(manager.call("get_density_at", camera.global_position)) if manager else 0.0
		smoke_strength = move_toward(smoke_strength, target_density, delta * 3.5)
	_update_flash_material()
	_smoke_rect.color.a = smoke_strength * 0.86
	if _presentation_settings != null:
		_presentation_settings.call("set_effects_duck_db", -flash_strength * 12.0)
	else:
		var effects_bus := AudioServer.get_bus_index(&"Effects")
		if effects_bus >= 0:
			AudioServer.set_bus_volume_db(
				effects_bus, _effects_bus_original_db - flash_strength * 12.0
			)
	if camera != null:
		shake_strength = move_toward(shake_strength, 0.0, delta * 2.8)
		var shake_scale := (
			float(_presentation_settings.call("camera_shake_scale"))
			if _presentation_settings != null
			else 1.0
		)
		camera.h_offset = _base_h_offset + randf_range(-0.025, 0.025) * shake_strength * shake_scale
		camera.v_offset = _base_v_offset + randf_range(-0.018, 0.018) * shake_strength * shake_scale


func apply_flash_from_world(
	position: Vector3,
	radius: float,
	source_rid: RID = RID(),
	intensity_multiplier: float = 1.0
) -> void:
	if camera == null:
		return
	var has_los := _has_line_of_sight(
		camera.global_position,
		position,
		source_rid
	)
	var exposure: float = FlashbangScript.calculate_exposure(
		position, camera.global_position, -camera.global_basis.z, has_los, radius
	)
	exposure = clampf(exposure * intensity_multiplier, 0.0, 1.0)
	var duration_weight := smoothstep(0.08, 0.68, exposure)
	if exposure > 0.08:
		# An affected player is actually blinded: the first presentation frame
		# is opaque white. Exposure controls the hold/recovery time, not initial
		# transparency, so a medium-distance flash cannot be seen through.
		flash_duration_weight = maxf(flash_duration_weight, duration_weight)
		var reduced_flashes := (
			bool(_presentation_settings.call("reduced_flashes_enabled"))
			if _presentation_settings != null
			else false
		)
		# Reduced flashes preserve the full impairment timing and audio cue. They
		# replace the opaque white peak with a lower-luminance veil only.
		flash_peak_strength = 0.62 if reduced_flashes else 1.0
		flash_strength = flash_peak_strength
		flash_hold_remaining = maxf(
			flash_hold_remaining,
			lerpf(0.10, 0.78, duration_weight)
		)
		flash_recovery_elapsed = 0.0
		flash_recovery_progress = 0.0
		_update_flash_material()
	if exposure > 0.08:
		_foley.call("play_cue", &"tinnitus", camera.global_position, linear_to_db(exposure), 1.0)


func apply_explosion_shake(position: Vector3, radius: float) -> void:
	if camera != null:
		shake_strength = maxf(shake_strength, clampf(1.0 - camera.global_position.distance_to(position) / radius, 0.0, 1.0))


func _has_line_of_sight(from: Vector3, to: Vector3, source_rid: RID = RID()) -> bool:
	if camera == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclusions: Array[RID] = []
	if source_rid.is_valid():
		exclusions.append(source_rid)
	var camera_rig := camera.get_parent()
	if camera_rig != null and camera_rig.is_in_group("socom_camera_rig"):
		var camera_target: Variant = camera_rig.get("target")
		if camera_target is CollisionObject3D:
			exclusions.append((camera_target as CollisionObject3D).get_rid())
	query.exclude = exclusions
	return camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _make_overlay(base_color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(base_color, 0.0)
	add_child(rect)
	return rect


func _configure_flash_material() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;

uniform float flash_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float recovery : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	centered.x *= 1.25;
	float distance_from_center = length(centered);
	float reveal_radius = mix(-0.22, 0.92, recovery);
	float feather = 0.20;
	float outer_white = smoothstep(
		reveal_radius - feather,
		reveal_radius + feather,
		distance_from_center
	);
	float residual_veil = pow(1.0 - recovery, 2.2) * 0.48;
	float white_mask = max(outer_white, residual_veil);
	COLOR = vec4(vec3(1.0), clamp(flash_alpha * white_mask, 0.0, 1.0));
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	_flash_rect.material = material
	_flash_rect.color = Color.WHITE


func _update_flash_recovery(delta: float) -> void:
	var dt := maxf(delta, 0.0)
	if flash_hold_remaining > 0.0:
		flash_hold_remaining = maxf(flash_hold_remaining - dt, 0.0)
		flash_strength = flash_peak_strength
		flash_recovery_progress = 0.0
		return
	if flash_peak_strength <= 0.001:
		flash_strength = 0.0
		flash_recovery_progress = 1.0
		return
	flash_recovery_elapsed += dt
	var recovery_duration := lerpf(1.20, 3.85, flash_duration_weight)
	flash_recovery_progress = clampf(
		flash_recovery_elapsed / recovery_duration,
		0.0,
		1.0
	)
	var eased_recovery := smoothstep(0.0, 1.0, flash_recovery_progress)
	flash_strength = flash_peak_strength * (1.0 - eased_recovery)
	if flash_recovery_progress >= 1.0:
		flash_peak_strength = 0.0
		flash_strength = 0.0
		flash_duration_weight = 0.0


func _update_flash_material() -> void:
	if _flash_rect == null or not _flash_rect.material is ShaderMaterial:
		return
	var material := _flash_rect.material as ShaderMaterial
	material.set_shader_parameter("flash_alpha", flash_strength)
	material.set_shader_parameter("recovery", flash_recovery_progress)
