extends SceneTree
const Wrist := preload("res://scripts/player/operator_support_wrist.gd")
func _initialize() -> void:
	for rotation in [Vector3.ZERO, Vector3(0.3,-0.8,1.2)]:
		var world := Basis.from_euler(rotation)
		for degrees in [0.0, 30.0, 90.0, 150.0, 180.0]:
			var source := world * Basis(Vector3.RIGHT, deg_to_rad(degrees))
			var result := Wrist.constrain_basis(source, Vector3.UP, world * Vector3.UP, deg_to_rad(55))
			assert(rad_to_deg((result * Vector3.UP).angle_to(world * Vector3.UP)) < 55.01)
			assert(is_equal_approx(result.determinant(), 1.0))
			if degrees < 55: assert(result.is_equal_approx(source))
	assert(Wrist.constrain_basis(Basis.IDENTITY, Vector3.ZERO, Vector3.UP, 1.0) == Basis.IDENTITY)
	assert(Wrist.constrain_basis(Basis.IDENTITY, Vector3.UP, Vector3.ZERO, 1.0) == Basis.IDENTITY)
	assert(Wrist.constrain_basis(Basis.IDENTITY, Vector3.UP, Vector3.UP, NAN) == Basis.IDENTITY)
	var cases := 0
	for rotation in [Vector3.ZERO, Vector3(.7, -.3, 1.1), Vector3(-1.4, 2.0, .4)]:
		for translation in [Vector3.ZERO, Vector3(120, -30, 80)]:
			for scale_value in [.1, 1.0, 3.0]:
				var basis := Basis.from_euler(rotation)
				var transform := Transform3D(basis.scaled(Vector3.ONE * scale_value), translation)
				var result := Wrist.physical_up_from_points(transform * Vector3.ZERO,
					transform * Vector3(0,.1,.2), transform * Vector3(0,.1,.8))
				assert(result.distance_to(basis.y) < .0003, "physical frame invariant to parent world transform")
				cases += 1
	assert(Wrist.physical_up_from_points(Vector3.ZERO, Vector3.UP, Vector3.UP) == Vector3.ZERO)
	assert(Wrist.physical_up_from_points(Vector3.ZERO, Vector3.UP, Vector3.UP * 2.0) == Vector3.ZERO)
	for bad in [Vector3(NAN,0,0), Vector3(0,INF,0)]:
		assert(Wrist.physical_up_from_points(bad, Vector3.UP, Vector3.UP + Vector3.FORWARD) == Vector3.ZERO)
		assert(Wrist.physical_up_from_points(Vector3.ZERO, bad, Vector3.FORWARD) == Vector3.ZERO)
		assert(Wrist.physical_up_from_points(Vector3.ZERO, Vector3.UP, bad) == Vector3.ZERO)
	assert(Wrist.physical_weapon_up(null, null, null) == Vector3.ZERO)
	var valid_catalog := 0
	var rejected_catalog := 0
	for filename in DirAccess.get_files_at("res://config/weapons"):
		if not filename.ends_with(".json"): continue
		var weapon: Dictionary = preload("res://scripts/weapons/weapon_rig_contract.gd").load_config("res://config/weapons/" + filename)
		if String(weapon.get("handling_profile", {}).get("family", "")) != "TWO_HAND_RIFLE": continue
		var sockets: Dictionary = weapon.get("weapon_sockets", {})
		var up := Wrist.physical_up_from_points(_point(sockets.get("right_hand_grip_target")),
			_point(sockets.get("barrel_base_socket")), _point(sockets.get("muzzle_socket")))
		if up == Vector3.ZERO: rejected_catalog += 1
		else:
			assert(up.is_finite() and absf(up.length() - 1.0) < .00001)
			valid_catalog += 1
	assert(valid_catalog >= 2, "canonical rifle socket frames covered")
	print("SUPPORT_WRIST_FRAME cases=", cases, " valid_rifle_profiles=", valid_catalog, " safe_skips=", rejected_catalog)
	print("SUPPORT_WRIST_GEOMETRY PASS")
	quit()

func _point(raw: Variant) -> Vector3:
	if not raw is Dictionary: return Vector3(NAN, NAN, NAN)
	for key in ["x", "y", "z"]:
		if not (raw.get(key) is float or raw.get(key) is int): return Vector3(NAN, NAN, NAN)
	return Vector3(raw.x, raw.y, raw.z)
