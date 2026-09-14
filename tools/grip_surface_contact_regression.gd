extends SceneTree
const Contact := preload("res://scripts/player/operator_grip_surface_contact.gd")
const Profile := preload("res://scripts/player/weapon_grip_surface_profile.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var profile := load("res://config/weapon_grip_surfaces/m4a1.tres") as Profile
	_check(profile != null and profile.is_valid(), "saved profile valid")
	_check(not profile.correction_enabled, "unsafe candidate must remain opt-in")
	var gap := func(curl: float) -> float: return .035 - curl * .1
	var result := Contact.bounded_curl(.72, gap, 12, 7)
	_check(result.status == "contact_limited", "surface limits curve")
	_check(absf(result.curl - .35) < .001 and result.gap_m >= 0, "contact boundary")
	result = Contact.bounded_curl(.72, func(_curl: float) -> float: return .01, 12, 7)
	_check(result.status == "clear" and result.curl == .72, "clear keeps authored curve")
	result = Contact.bounded_curl(.72, func(_curl: float) -> float: return -.01, 12, 7)
	_check(result.status == "embedded_open_pose" and result.curl == .72, "embedded cannot reposition hand")
	result = Contact.bounded_curl(.72, func(curl: float) -> float: return (curl - .2) * (curl - .6), 12, 7)
	_check(result.status == "contact_limited" and absf(result.curl - .2) < .001, "no endpoint-only tunneling")
	result = Contact.bounded_curl(.72, func(_curl: float) -> float: return NAN, 12, 7)
	_check(result.status == "invalid" and result.curl == .72, "bad geometry safe fallback")
	var line := PackedVector3Array([Vector3(.04,-.03,0), Vector3(.04,0,0), Vector3(.04,.03,0), Vector3(.04,.06,0)])
	_check(absf(Contact.polyline_gap(line,.02,.2,.005) - .015) < .000001, "parallel capsule separation")
	line = PackedVector3Array([Vector3(-.03,0,0), Vector3(.03,0,0), Vector3(.05,0,0), Vector3(.08,0,0)])
	_check(absf(Contact.polyline_gap(line,.02,.2,.005) + .025) < .000001, "between-joint collision detected")
	var bad := profile.duplicate(true) as Profile
	bad.local_transform.basis.x *= 2
	_check(not bad.is_valid(), "non-uniform local shape rejected")
	bad = profile.duplicate(true) as Profile
	bad.finger_radius_m = NAN
	_check(not bad.is_valid(), "nonfinite radius rejected")
	for id in ["ak-47", "mark_23", "../../m4a1"]:
		var other := Node3D.new()
		Contact.attach(other, other, {"weapon_id":id, "model_fbx":profile.expected_model})
		_check(other.get_child_count() == 0, "no accidental profile for " + id)
		var skeleton := Skeleton3D.new()
		_check(Contact.limit_curl(skeleton, other, "Index", .72).status == "unconfigured", "no missing metadata error")
		skeleton.free()
		other.free()
	var gun := Node3D.new()
	root.add_child(gun)
	var pivot := Node3D.new()
	pivot.name = "CalibratedWeaponPivot"
	gun.add_child(pivot)
	Contact.attach(pivot, gun, {"weapon_id":"m4a1", "model_fbx":"wrong.scn"})
	_check(pivot.get_child_count() == 0, "different M4 model cannot reuse geometry")
	Contact.attach(pivot, gun, {"weapon_id":"m4a1", "model_fbx":profile.expected_model})
	Contact.attach(pivot, gun, {"weapon_id":"m4a1", "model_fbx":profile.expected_model})
	_check(pivot.get_child_count() == 1, "single attachment owner")
	var area: Area3D = pivot.get_node("GripContactSurface")
	var collider: CollisionShape3D = area.get_node("ForeEnd")
	_check(area.collision_layer == 0 and area.collision_mask == 0 and not area.monitoring and not area.monitorable,
		"no world, hurtbox or shot query participation")
	_check(collider.shape != profile.shape, "instance-private shape")
	# The same local geometry under translated, rotated, scaled parent frames.
	var local_point := Vector3(.04,.01,.02)
	for rotation in [Vector3.ZERO, Vector3(.2,1.3,-.8)]:
		for translation in [Vector3.ZERO, Vector3(500, 2, 500)]:
			for scale_value in [.5,1.,2.]:
				gun.transform = Transform3D(Basis.from_euler(rotation).scaled(Vector3.ONE * scale_value), translation)
				var world := collider.global_transform * local_point
				_check(collider.to_local(world).distance_to(local_point) < .0002, "calibrated local/world parity")
	gun.queue_free()
	await process_frame
	print("GRIP_SURFACE_CONTACT ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " ", failures)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
