extends RefCounted

## Shared authored bloom envelope. No input, RNG, camera or damage ownership.
const Geometry := preload("res://scripts/ui/custom_reticle_geometry.gd")
const PATH := "res://config/reticle_presentation.json"
static var settings: Dictionary = {}

static func load_settings() -> Dictionary:
	if settings.is_empty():
		settings = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return settings

static func gap_for(profile: Dictionary, normalized: float) -> float:
	return lerpf(float(profile.get("base_gap_px", 10.0)),
		float(profile.get("max_gap_px", 46.0)), clampf(normalized, 0.0, 1.0))

static func advance_gap(gap: float, target: float, profile: Dictionary, delta: float) -> float:
	return lerpf(gap, target, 1.0 - exp(-maxf(0.0, float(profile.get("response_speed", 24.0))) * maxf(delta, 0.0)))

static func radius_px(profile: Dictionary, gap: float) -> float:
	var data := load_settings()
	var custom: Dictionary = data.get("custom", {})
	var family := String(custom.get("categories", {}).get(profile.get("weapon_category", ""), ""))
	var style: Dictionary = custom.get("families", {}).get(family, {})
	var padding := float(profile.get("reference_arc_padding_px", 5.0))
	if bool(custom.get("enabled", false)) and not style.is_empty():
		var strokes := Geometry.build(String(style.get("shape", "")), gap + padding, style)
		var outline_width := clampf(float(style.get("stroke_px", 2.2)), 1.0, 5.0) + clampf(float(custom.get("outline_extra_px", 2.0)), 0.0, 5.0)
		return inner_radius(strokes, outline_width)
	# Source cardinal marks and legacy ticks start at this gap. A conservative
	# fallback also fits inside the larger source shotgun quarter-circle marks.
	return maxf(0.0, gap + padding - 2.0)

static func inner_radius(strokes: Array[PackedVector2Array], outline_width: float) -> float:
	var radius := INF
	for stroke in strokes:
		for index in range(1, stroke.size()):
			var a := stroke[index - 1]
			var step := stroke[index] - a
			var t := clampf(-a.dot(step) / maxf(step.length_squared(), 0.000001), 0.0, 1.0)
			radius = minf(radius, (a + step * t).length())
	return maxf(0.0, radius - outline_width * 0.5) if is_finite(radius) else 0.0

static func tangent_limit(profile: Dictionary, gap: float) -> float:
	var calibration: Dictionary = load_settings().get("shot_envelope", {})
	var focal := float(calibration.get("reference_height_px", 1080.0)) * 0.5 / tan(deg_to_rad(float(calibration.get("reference_vertical_fov_deg", 68.0))) * 0.5)
	return radius_px(profile, gap) / maxf(focal, 1.0)

static func projected_radius(camera: Camera3D, muzzle: Vector3, target: Vector3, tangent: float) -> float:
	# Conservative analytic projection of the entire disk at the aim depth,
	# not a few edge samples that could miss its widest point. Third-person
	# parallax at nearer occluders is deliberately not treated as spread.
	var inverse := camera.get_camera_transform().affine_inverse()
	var center := inverse * target
	var distance := muzzle.distance_to(target)
	if distance < 0.00001 or tangent <= 0.0:
		return 0.0
	var forward := muzzle.direction_to(target)
	var basis := Basis.looking_at(forward, Vector3.UP if absf(forward.y) < 0.999 else Vector3.RIGHT)
	var u := inverse.basis * basis.x
	var v := inverse.basis * basis.y
	var depth := -center.z
	var world_radius := distance * tangent
	var minimum_depth := depth - world_radius * Vector2(u.z, v.z).length()
	if minimum_depth <= camera.near:
		return INF
	var center_xy := Vector2(center.x, center.y) / depth
	var a := Vector2(u.x, u.y) + center_xy * u.z
	var b := Vector2(v.x, v.y) + center_xy * v.z
	var aa := a.length_squared()
	var bb := b.length_squared()
	var ab := a.dot(b)
	var norm := sqrt(0.5 * (aa + bb + sqrt((aa - bb) * (aa - bb) + 4.0 * ab * ab)))
	var viewport := camera.get_viewport().get_visible_rect().size
	var axis_size := viewport.y if camera.keep_aspect == Camera3D.KEEP_HEIGHT else viewport.x
	var focal := axis_size * 0.5 / tan(deg_to_rad(camera.fov) * 0.5)
	return focal * world_radius * norm / minimum_depth
