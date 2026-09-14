class_name SourceGameplayCamera
extends RefCounted

## No node, input, bone or transform writes. The existing camera owns the result.
const PATH := "res://config/camera_source_match.json"
const Channels := preload("res://scripts/player/operator_source_camera_channels.gd")
var settings: Dictionary = {}
var anchor: Node
var observed_target: Node

func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary and valid_settings(parsed):
		settings = parsed

static func valid_settings(data: Dictionary) -> bool:
	var version: Variant = data.get("schema_version")
	if not (version is int or version is float) or version != 1:
		return false
	for key in ["enabled", "lens_enabled", "preferred_position_enabled"]:
		if not data.get(key) is bool: return false
	if data.get("framing_mode", "source") not in ["source", "hybrid"]: return false
	if data.get("framing_mode", "source") == "hybrid":
		var hybrid: Variant = data.get("hybrid")
		if not hybrid is Dictionary: return false
		if not hybrid.get("preserve_orbit_radius") is bool: return false
		for key in ["horizontal_fov_degrees", "framing_start_pitch_degrees", "framing_full_pitch_degrees", "max_height_correction_m", "minimum_relative_height_m"]:
			var value: Variant = hybrid.get(key)
			if not (value is int or value is float) or not is_finite(float(value)): return false
		if hybrid.framing_start_pitch_degrees < 0.0 or hybrid.framing_full_pitch_degrees <= hybrid.framing_start_pitch_degrees or hybrid.framing_full_pitch_degrees > 90.0: return false
		if hybrid.horizontal_fov_degrees < 60.0 or hybrid.horizontal_fov_degrees > 100.0: return false
		if hybrid.max_height_correction_m < 0.0 or hybrid.max_height_correction_m > 2.0 or hybrid.minimum_relative_height_m < 0.0 or hybrid.minimum_relative_height_m > 1.0: return false
	var horizontal: Variant = data.get("horizontal_fov_degrees")
	var scale: Variant = data.get("world_meters_per_unit")
	if not (horizontal is int or horizontal is float) or not (scale is int or scale is float):
		return false
	return is_finite(float(horizontal)) and float(horizontal) > 1.0 and float(horizontal) < 179.0 and is_finite(float(scale)) and float(scale) > 0.0

func lens_enabled() -> bool:
	return valid_settings(settings) and settings.enabled and settings.lens_enabled

func hybrid_enabled() -> bool:
	return lens_enabled() and settings.get("framing_mode", "source") == "hybrid"

func framing_weight(pitch: float) -> float:
	if not hybrid_enabled() or not is_finite(pitch): return 0.0
	return smoothstep(float(settings.hybrid.framing_start_pitch_degrees), float(settings.hybrid.framing_full_pitch_degrees), absf(rad_to_deg(pitch)))

func active_horizontal_fov() -> float:
	return float(settings.hybrid.horizontal_fov_degrees) if hybrid_enabled() else float(settings.get("horizontal_fov_degrees",70.0))

func compose_hybrid(source_position: Vector3, framed_position: Vector3, player_position: Vector3, pitch: float) -> Vector3:
	if not hybrid_enabled(): return source_position
	var result := source_position
	# Keep source lateral lean and boom: open framing adjusts height only.
	var limit := float(settings.hybrid.max_height_correction_m)
	result.y += clampf(framed_position.y-source_position.y, -limit, limit) * framing_weight(pitch)
	result.y = maxf(result.y, player_position.y + float(settings.hybrid.minimum_relative_height_m))
	return result # A preference, still subject to every existing collision pass.

func lens_active_for(target: Node3D, yaw: float, pitch: float) -> bool:
	# A valid policy is not sufficient: a non-operator/spectator target may lack
	# its retained channel. Keep both halves authored if source position fails.
	return lens_enabled() and not world_preference(target, yaw, pitch).is_empty()

func world_preference(target: Node3D, yaw: float, pitch: float) -> Dictionary:
	if not lens_enabled() or not bool(settings.preferred_position_enabled) or not is_instance_valid(target) or not target.is_inside_tree():
		return {}
	if observed_target != target or not is_instance_valid(anchor):
		observed_target = target
		anchor = target.find_child("SourceCameraAnchor", true, false)
	if not is_instance_valid(anchor):
		return {}
	# Ordinary ZSeal update57b1d0/57b1e0 zeros sampled rootX/Z before the
	# camera observes its node. Raw locomotion travel is NOT a camera offset.
	var raw_root: Vector3 = anchor.root_source
	var coverage := clampf(float(anchor.coverage), 0.0, 1.0)
	var anchor_kind := "animated_source"
	if coverage < .999:
		# AGLS/unknown clips do not contain a SOCOM root. Keep a complete lens+
		# position pair by using the explicit saved source stance fallback. Never
		# combine the narrow source lens with the rejected authored high camera.
		var stance := String(target.call("get_posture_name")).to_lower() if target.has_method("get_posture_name") else "standing"
		var names: Dictionary = settings.get("fallback_source_stance_clips", {})
		var name := String(names.get(stance, names.get("standing", "")))
		if not Channels.data().has(name): return {}
		var row: Dictionary = Channels.data()[name]
		var fallback := Vector3(row.positions_raw[0][0],row.positions_raw[0][1],row.positions_raw[0][2]) / 256.0
		# Missing tracks carry zero with coverage0. AnimationTree already weighted
		# present channels, so add only the unavailable fraction's stance root.
		raw_root += fallback * (1.0 - coverage)
		anchor_kind = "source_stance_fallback" if coverage < .001 else "source_with_stance_fallback"
	var root_source := Vector3(0.0, raw_root.y, 0.0)
	var lean := clampf(float(target.call("get_peek_amount")), -1.0, 1.0) if target.has_method("get_peek_amount") else 0.0
	var source := source_preferred_pose(root_source, pitch, lean)
	if source.is_empty(): return {}
	if hybrid_enabled() and settings.hybrid.preserve_orbit_radius:
		# Deliberate hybrid design: orbit the source pivot without the source's
		# pitch-driven28->14 radius contraction. Actual collision still retracts.
		source.position_source = Vector3(source.pivot_source) + Vector3(source.normalized_back) * Vector3(source.back_source).length()
	var units := float(settings.world_meters_per_unit)
	var basis := Basis(Vector3.UP, yaw)
	return {
		"position":target.global_position + basis * Vector3(source.position_source) * units,
		"far_target":target.global_position + basis * Vector3(source.far_target_source) * units,
		"root_source":root_source,
		"raw_root_source":raw_root,
		"anchor_kind":anchor_kind,
		"lean":lean,
		"radius_source":Vector3(source.position_source).distance_to(Vector3(source.pivot_source)),
	}

func lens_vertical_degrees(viewport_size: Vector2, fallback_vertical: float = 68.0) -> float:
	if not lens_enabled() or not viewport_size.is_finite() or viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return fallback_vertical
	return vertical_fov(active_horizontal_fov(), maxf(viewport_size.x, 1.0) / maxf(viewport_size.y, 1.0))

static func observe_native_root(skeleton: Skeleton3D, skeleton_to_source: Transform3D) -> Dictionary:
	# Observer seam for a future retained source channel. The caller must supply
	# its proven model-space conversion. Never fall back to hips or HeadMarker:
	# source skel_root and its child hips have independent animation channels.
	if skeleton == null:
		return {}
	var index := skeleton.find_bone("skel_root")
	if index < 0:
		return {}
	var value := skeleton_to_source * skeleton.get_bone_global_pose(index).origin
	return {"root_source": value} if value.is_finite() else {}

static func vertical_fov(horizontal_degrees: float, aspect: float) -> float:
	# Camera3D.KEEP_HEIGHT and the existing reticle/projector both use vertical FOV.
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal_degrees) * 0.5) / maxf(aspect, 0.001)))

static func source_preferred_pose(root_source: Vector3, pitch_radians: float, lean: float = 0.0) -> Dictionary:
	if not root_source.is_finite() or not is_finite(pitch_radians) or not is_finite(lean):
		return {}
	# FTSCore 29aa08..29ab78. Preserve operation order and source constants.
	# Godot scalar/Basis arithmetic is checked to tolerance, not claimed bitwise
	# identical to the original R5900 FPU/VU quaternion implementation.
	var t := 1.0 if root_source.y >= 5.599999904632568 else clampf((root_source.y - 2.1691548824310303) * 0.291473388671875, 0.0, 1.0)
	var bonus := 10.0 if root_source.y == 0.0 else 5.5 + 4.5 * t
	var x := root_source.x + lean * (2.5 if lean < 0.0 else 2.799999952316284)
	var pivot := Vector3(x, root_source.y + bonus, 0.0)
	var back := Vector3(x, 0.0, root_source.z + 28.0)
	var radius := back.length()
	if radius < 0.000001:
		return {}
	# Original X quaternion: +pitch rotates the back vector down (view aims up).
	var direction := (Basis(Vector3.RIGHT, pitch_radians) * back).normalized()
	# Clear ordinary branch only: special pose/collision branches remain unported.
	pivot.z = direction.y * (-3.0 if direction.y < 0.0 else -8.0)
	radius = radius + absf(direction.y) * (14.0 - radius)
	var position := pivot + direction * radius
	# Original 297410 uses Qpitch*(0,0,-1000) + pivot for its far look target.
	var far_target := pivot + Basis(Vector3.RIGHT, pitch_radians) * Vector3(0.0, 0.0, -1000.0)
	return {"position_source": position, "pivot_source": pivot, "far_target_source": far_target, "radius_source": radius, "height_bonus_source": bonus, "back_source": back, "normalized_back": direction}
