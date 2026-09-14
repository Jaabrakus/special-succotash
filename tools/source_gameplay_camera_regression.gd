extends SceneTree

const Policy := preload("res://scripts/camera/source_gameplay_camera.gd")
class LeanTarget extends Node3D:
	var lean := 0.0
	func get_peek_amount() -> float: return lean
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var policy := Policy.new()
	_expect(policy.lens_enabled(), "verified full source camera is saved default")
	policy.settings.enabled = true
	_expect(policy.lens_enabled(), "explicit source lens candidate is valid")
	_expect(bool(policy.settings.get("preferred_position_enabled", false)), "retained independent root activates full preferred position")
	_expect(policy.hybrid_enabled(), "user chose saved hybrid default")
	_expect(policy.framing_weight(0.0) == 0.0, "hybrid preserves exact level framing")
	for sign_value in [-1.0,1.0]:
		var previous := 0.0
		for degrees in 61:
			var weight := policy.framing_weight(deg_to_rad(float(degrees)*sign_value))
			_expect(weight >= previous and weight <= 1.0, "continuous bounded pitch blend")
			previous = weight
	var level := Vector3(.5,2.15,2.8)
	_expect(policy.compose_hybrid(level,Vector3(-3,8,9),Vector3.ZERO,0.0)==level,"level source shot not overwritten by authored framing")
	var composed := policy.compose_hybrid(level,Vector3(-3,8,9),Vector3.ZERO,deg_to_rad(-45))
	_expect(composed.x==level.x and composed.z==level.z,"hybrid cannot recenter lateral lean or alter source boom")
	_expect(absf(composed.y-level.y-1.0)<.000001,"hybrid height correction bound")
	_expect(policy.compose_hybrid(Vector3(0,-.3,2),Vector3(0,-.3,2),Vector3.ZERO,.4).y >= float(policy.settings.hybrid.minimum_relative_height_m)-.000001,"hybrid preferred seed stays above player feet")
	for aspect in [4.0/3.0, 16.0/9.0, 16.0/10.0, 1.0, 9.0/16.0]:
		var vertical := Policy.vertical_fov(70.0, aspect)
		var recovered := rad_to_deg(2.0 * atan(tan(deg_to_rad(vertical) * .5) * aspect))
		_expect(absf(recovered - 70.0) < 0.00001, "horizontal FOV round trip at aspect " + str(aspect))
	# Golden scalar outputs from original FTSCore instructions. See the original
	# 29-case observer for SHA-256 and executed PCs; not screen-derived values.
	for row in [
		[Vector3(0,0,0), 0.0, Vector3(0,10,28), 28.0],
		[Vector3(0,2,0), 0.0, Vector3(0,7.5,28), 28.0],
		[Vector3(0,3,0), 0.0, Vector3(0,9.589761734008789,28), 28.0],
		[Vector3(0,5.6,0), 0.0, Vector3(0,15.600000381469727,28), 28.0],
		[Vector3(0,10,0), 0.0, Vector3(0,20,28), 28.0],
		[Vector3(.3,18,1.2), 0.0, Vector3(.6,28,29.200000762939453), 29.201541900634766],
		[Vector3(0,10,0), -.75, Vector3(-3.75,20,28), 28.062707901000977],
		[Vector3(0,10,0), .75, Vector3(4.199999809265137,20,28), 28.07863998413086]
	]:
		var output := Policy.source_preferred_pose(row[0], 0.0, row[1])
		_expect(Vector3(output.position_source).distance_to(row[2]) < .00001, "original state-2 pivot/back " + str(row[0]))
		_expect(absf(float(output.radius_source) - float(row[3])) < .00001, "original initial radius")
	for row in [[28.0,-.9,15.40000057220459], [28.0,-.5,21.0], [28.0,0.0,28.0], [28.0,.5,21.0], [28.0,.9,15.40000057220459], [30.0,-.25,26.0]]:
		var output := Policy.source_preferred_pose(Vector3(0,10,float(row[0])-28.0), -asin(float(row[1])))
		_expect(absf(float(output.radius_source) - float(row[2])) < .00001, "original pitch collapse")
	for degrees in [-70.0,-30.0,0.0,25.0,60.0]:
		var output := Policy.source_preferred_pose(Vector3(0,10,0), deg_to_rad(degrees))
		var direction: Vector3 = output.normalized_back
		_expect(absf(direction.y + sin(deg_to_rad(degrees))) < .000001, "verified original pitch sign")
		_expect(Vector3(output.position_source).is_finite(), "finite clear-path preferred pose")
	var skeleton := Skeleton3D.new()
	root.add_child(skeleton)
	skeleton.add_bone("mixamorig_Hips")
	_expect(Policy.observe_native_root(skeleton, Transform3D.IDENTITY).is_empty(), "hips are NOT a source root fallback")
	skeleton.add_bone("skel_root")
	skeleton.set_bone_pose_position(1, Vector3(0,10,0))
	var before := skeleton.get_bone_pose(1)
	var observed := Policy.observe_native_root(skeleton, Transform3D(Basis.IDENTITY, Vector3(0,2,0)))
	_expect(Vector3(observed.root_source).is_equal_approx(Vector3(0,12,0)), "explicit native model conversion")
	_expect(skeleton.get_bone_pose(1) == before, "source root observer never writes pose")
	skeleton.free()
	var target := LeanTarget.new()
	root.add_child(target)
	_expect(not policy.lens_active_for(target,0,0),"missing operator channel keeps authored lens and position together")
	var anchor := preload("res://scripts/player/operator_source_camera_anchor.gd").new()
	anchor.name = "SourceCameraAnchor"
	target.add_child(anchor)
	policy.settings.preferred_position_enabled = true
	anchor.root_source = Vector3(41,2638,7233)/256.0
	anchor.coverage = 1.0
	var moving := policy.world_preference(target,0.0,0.0)
	_expect(policy.lens_active_for(target,0,0),"complete source lens and position activated together")
	_expect(Vector3(moving.root_source)==Vector3(0,2638.0/256.0,0),"original ordinary rootXZ zeroing before camera")
	_expect(absf(Vector3(moving.position).z-2.8)<.000001,"run does not double camera boom")
	for degrees in [-55.0,-30.0,0.0,25.0,28.0]:
		var pitched := policy.world_preference(target,0.0,deg_to_rad(degrees))
		_expect(absf(float(pitched.radius_source)-28.0)<.00001,"hybrid removes pitch-driven radius contraction")
	for lean in [-1.0,0.0,1.0]:
		target.lean = lean
		var leaned := policy.world_preference(target,0.0,0.0)
		_expect(absf(Vector3(leaned.position).x - lean*(.5 if lean < 0 else .56))<.000001,"source camera reads existing smoothed lean")
		target.lean = 0.0
	anchor.root_source = Vector3.ZERO
	anchor.coverage = 0.0
	var fallback := policy.world_preference(target,0.0,0.0)
	_expect(fallback.get("anchor_kind")=="source_stance_fallback","unsupported clips expose explicit saved fallback")
	_expect(absf(Vector3(fallback.position).y-2.1484375)<.000001,"fallback uses original stand root, not rejected authored high pivot")
	target.free()
	var good := policy.settings.duplicate(true)
	for invalid_hybrid in [{}, {"framing_start_pitch_degrees":"8"}, {"framing_start_pitch_degrees":20.0,"framing_full_pitch_degrees":5.0,"max_height_correction_m":1.0,"minimum_relative_height_m":.45}]:
		policy.settings.hybrid = invalid_hybrid
		_expect(not policy.lens_enabled(),"invalid hybrid policy rejects paired camera instead of partial application")
	policy.settings = good
	policy.settings.horizontal_fov_degrees = NAN
	_expect(not policy.lens_enabled(), "invalid saved lens fails closed")
	for invalid in ["70", {}, [], true, INF]:
		policy.settings.horizontal_fov_degrees = invalid
		_expect(not policy.lens_enabled(), "non-numeric or non-finite lens rejected")
	policy.settings.horizontal_fov_degrees = 70.0
	policy.settings.enabled = "false"
	_expect(not policy.lens_enabled(), "string boolean rejected")
	policy.settings.enabled = true
	_expect(policy.lens_vertical_degrees(Vector2(INF,800)) == 68.0, "invalid viewport returns authored fallback")
	_expect(Policy.source_preferred_pose(Vector3(NAN,0,0), 0).is_empty(), "nonfinite source root rejected")
	print("SOURCE_GAMEPLAY_CAMERA ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
