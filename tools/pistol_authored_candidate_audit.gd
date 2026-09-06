extends "res://tools/pistol_fire_recovery_visual_check.gd"

## Compares a Blender-authored candidate on the canonical operator in memory.
## Does not save a profile or promote a source asset into gameplay.

var candidate_scene: Node
var candidate_action: Animation
var candidate_skeleton: Skeleton3D
var candidate_rest_error_deg := 0.0
var baseline_only := false
var distinct_low_ready := false
var distinct_loader: RefCounted
var active_driver: Node


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	baseline_only = "--baseline" in args
	distinct_low_ready = "--distinct-low-ready" in args
	if baseline_only:
		await super._run()
		return
	var candidate_path := ""
	for arg: String in args:
		if arg.begins_with("--candidate="):
			candidate_path = arg.trim_prefix("--candidate=")
	if candidate_path.is_empty():
		push_error("Supply --candidate=/absolute/path/to/candidate.glb")
		quit(1)
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result := document.append_from_file(candidate_path, state)
	if result != OK:
		push_error("Candidate GLB could not load: %s" % error_string(result))
		quit(1)
		return
	candidate_scene = document.generate_scene(state)
	var runtime = load("res://scripts/player/operator_asset_runtime.gd").new()
	candidate_skeleton = runtime.call("_find_skeleton", candidate_scene)
	var source_player: AnimationPlayer = runtime.call("_find_animation_player", candidate_scene)
	if source_player != null:
		for name: StringName in source_player.get_animation_list():
			if "PistolReadySquare_Candidate" in String(name):
				candidate_action = source_player.get_animation(name)
	if candidate_action == null or candidate_skeleton == null:
		push_error("Candidate requires PistolReadySquare_Candidate and a skeleton")
		candidate_scene.free()
		quit(1)
		return
	if distinct_low_ready:
		distinct_loader = load("res://tools/pistol_candidate_loader.gd").new()
		_expect(distinct_loader.load_candidate(candidate_path), "distinct low/aim source loads")
	await super._run()
	candidate_scene.free()
	if distinct_loader != null:
		distinct_loader.dispose()


func _capture_posture(
	scene: Node3D,
	player: CharacterBody3D,
	controller: Node,
	driver: Node,
	review_camera: Camera3D,
	posture_index: int,
	posture_name: StringName,
	expected_state: StringName
) -> void:
	active_driver = driver
	if not scene.has_node("PistolAuditFillLight"):
		var fill := DirectionalLight3D.new()
		fill.name = "PistolAuditFillLight"
		fill.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
		fill.light_energy = 1.6
		fill.shadow_enabled = false
		scene.add_child(fill)
	if baseline_only:
		await super._capture_posture(scene, player, controller, driver, review_camera, posture_index, posture_name, expected_state)
		return
	if distinct_low_ready:
		if posture_index == 0:
			var installation: Dictionary = distinct_loader.install(driver, true)
			_expect(bool(installation.get("ok", false)), "distinct low/aim source keeps native rests")
		await super._capture_posture(scene, player, controller, driver, review_camera, posture_index, posture_name, expected_state)
		return
	var library: AnimationLibrary = driver.get("dynamic_anim_lib")
	var target_skeleton: Skeleton3D = driver.get("skeleton")
	var original := library.get_animation(expected_state)
	var composite := original.duplicate() as Animation
	var replaced := 0
	for source_track in range(candidate_action.get_track_count()):
		if candidate_action.track_get_type(source_track) != Animation.TYPE_ROTATION_3D:
			continue
		var source_name := String(candidate_action.track_get_path(source_track)).get_slice(":", 1)
		var target_name := source_name.replace("mixamorig:", "mixamorig_")
		if not target_name.begins_with("mixamorig_"):
			target_name = "mixamorig_" + target_name
		if not _upper_body(target_name):
			continue
		var target_index := target_skeleton.find_bone(target_name)
		var source_index := candidate_skeleton.find_bone(source_name)
		if source_index < 0:
			source_index = candidate_skeleton.find_bone(target_name)
		if target_index < 0 or source_index < 0:
			continue
		var source_rest := candidate_skeleton.get_bone_rest(source_index).basis.get_rotation_quaternion()
		var target_rest := target_skeleton.get_bone_rest(target_index).basis.get_rotation_quaternion()
		candidate_rest_error_deg = maxf(candidate_rest_error_deg, rad_to_deg(source_rest.angle_to(target_rest)))
		var path := NodePath(".:" + target_name)
		var track := composite.find_track(path, Animation.TYPE_ROTATION_3D)
		if track < 0:
			track = composite.add_track(Animation.TYPE_ROTATION_3D)
			composite.track_set_path(track, path)
		for key in range(composite.track_get_key_count(track) - 1, -1, -1):
			composite.track_remove_key(track, key)
		# Same native rest is required. A mismatched rig must be repaired at the
		# asset boundary, not hidden by a second runtime correction algorithm.
		var rotation := candidate_action.rotation_track_interpolate(source_track, 0.0)
		composite.track_insert_key(track, 0.0, rotation)
		replaced += 1
	print("PISTOL_CANDIDATE_IMPORT posture=%s replaced_tracks=%d max_rest_error_deg=%.5f" % [
		posture_name, replaced, candidate_rest_error_deg,
	])
	if candidate_rest_error_deg > 0.1 or replaced < 8:
		_expect(false, "candidate preserves canonical upper-body rest and bone mapping")
		return
	library.remove_animation(expected_state)
	library.add_animation(expected_state, composite)
	await super._capture_posture(scene, player, controller, driver, review_camera, posture_index, posture_name, expected_state)
	library.remove_animation(expected_state)
	library.add_animation(expected_state, original)


func _upper_body(name: String) -> bool:
	return not (
		name.ends_with("Hips") or "Leg" in name or "Foot" in name
		or "Toe" in name or name.ends_with("Root")
	)


func _capture(path: String) -> bool:
	var prefix := "socom-pistol-audit-baseline" if baseline_only else "socom-pistol-authored-candidate"
	if distinct_low_ready and ("-before.png" in path or "-after.png" in path):
		var skel: Skeleton3D = active_driver.get("skeleton")
		var solver: Node = active_driver.get("weapon_pose_solver")
		var left := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("mixamorig_LeftArm")).origin
		var right := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("mixamorig_RightArm")).origin
		var trigger: Marker3D = solver.get("trigger_socket")
		var barrel: Marker3D = solver.get("barrel_base_socket")
		var muzzle: Marker3D = solver.get("muzzle_socket")
		var bore := barrel.global_position.direction_to(muzzle.global_position)
		var from_chest := trigger.global_position - (left + right) * 0.5
		var lateral := from_chest.dot((right - left).normalized())
		var root_lateral := from_chest.dot(skel.global_basis.x.normalized())
		var pitch := rad_to_deg(asin(clampf(bore.y, -1.0, 1.0)))
		var support: Marker3D = solver.get("support_socket")
		var palm := skel.global_transform * (skel.get_bone_global_pose(skel.find_bone("mixamorig_LeftHand")) * Vector3(solver.get("left_palm_anchor_local")))
		var support_error := palm.distance_to(support.global_position)
		print("PISTOL_LOW_READY_METRIC path=%s chest_lateral_m=%.4f root_lateral_m=%.4f pitch_deg=%.2f support_m=%.4f" % [path, lateral, root_lateral, pitch, support_error])
		_expect(absf(lateral) <= 0.08, "low-ready is centered at the chest, not beside the left shoulder")
		_expect(pitch <= 5.0 and pitch >= -60.0, "low-ready muzzle points forward/down, not above the head")
		_expect(support_error <= 0.01, "low-ready support palm stays in contact")
	return await super._capture(path.replace("socom-mark23-fire-recovery", prefix))


func _aim_review_camera(camera: Camera3D, driver: Node, player: CharacterBody3D) -> void:
	var target := player.global_position + Vector3.UP * 1.15
	var skel := driver.get("skeleton") as Skeleton3D
	if skel != null:
		var chest := skel.find_bone("mixamorig_Spine2")
		if chest >= 0:
			target = skel.global_transform * skel.get_bone_global_pose(chest).origin
	camera.global_position = target + Vector3(2.65, 0.26, -1.65)
	camera.look_at(target, Vector3.UP)


func _measure_pistol_geometry(driver: Node, aim_target: Vector3) -> Dictionary:
	var measured := super._measure_pistol_geometry(driver, aim_target)
	if baseline_only:
		return measured
	var solver: Node = driver.get("weapon_pose_solver")
	var skel: Skeleton3D = driver.get("skeleton")
	var weapon: Node3D = solver.get("weapon_node")
	var diagnostics: Dictionary = driver.call("get_animation_debug_state")
	var pose: Dictionary = diagnostics.get("weapon_pose", {})
	_expect(float(pose.get("trigger_hand_error_m", INF)) <= 0.01
		and float(pose.get("support_hand_error_m", INF)) <= 0.01,
		"candidate keeps both physical contacts within one centimeter")
	_expect(weapon.global_basis.get_scale().distance_to(Vector3.ONE) <= 0.01,
		"candidate preserves authored world weapon scale")
	for side in ["right", "left"]:
		var elbow := float(pose.get(side + "_elbow_angle_deg", -1.0))
		_expect(elbow >= 38.0 and elbow <= 155.0,
			"candidate %s elbow remains within 38–155 degrees" % side)
	print("PISTOL_CANDIDATE_SHAPE ", JSON.stringify({
		"posture": String(solver.get("last_posture")),
		"right_elbow_deg": pose.get("right_elbow_angle_deg", -1.0),
		"left_elbow_deg": pose.get("left_elbow_angle_deg", -1.0),
		"centerline_shift_m": pose.get("pistol_trigger_centerline_shift_m", -1.0),
		"world_weapon_scale": str(weapon.global_basis.get_scale()),
	}))
	var presentation = solver.get("weapon_presentation_owner")
	var original := weapon.global_transform
	var palm: Transform3D = solver.call("_right_hand_grip_world_transform")
	solver.call("_weapon_transform_on_trigger_hand", palm, true)
	var muzzle: Marker3D = solver.get("muzzle_socket")
	var barrel: Marker3D = solver.get("barrel_base_socket")
	var bore := barrel.global_position.direction_to(muzzle.global_position)
	var up: Vector3 = solver.call("_weapon_optic_up_world", barrel.global_position, bore)
	var correction: Quaternion = solver.call("_aim_frame_alignment_delta", bore,
		muzzle.global_position.direction_to(aim_target), up, skel.global_basis.y.normalized())
	var hand := skel.find_bone("mixamorig_RightHand")
	var forearm := skel.get_bone_parent(hand)
	var parent_basis := (skel.global_transform * skel.get_bone_global_pose(forearm)).basis.orthonormalized()
	var desired_local := (parent_basis.inverse() * Basis(correction) * palm.basis).get_rotation_quaternion().normalized()
	print("PISTOL_CANDIDATE_WRIST_CALIBRATION ", JSON.stringify({
		"posture": String(solver.get("last_posture")),
		"right_hand_local_xyzw": [desired_local.x, desired_local.y, desired_local.z, desired_local.w],
		"correction_deg": rad_to_deg(correction.get_angle()),
	}))
	presentation.call("set_world_basis", original.basis)
	presentation.call("translate_world", original.origin - weapon.global_position)
	return measured
