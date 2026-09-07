extends "res://tools/firearm_family_transition_regression.gd"

## Physical continuity at the final authored-stock -> hand-follow boundary.
## Canonical input sequence; no weapon, rig, target or readiness override.
const MAX_RELEASE_ANGLE_DELTA_DEG := 5.0
const MAX_RELEASE_ELBOW_STEP_M := 0.015
var previous_release_sample: Dictionary = {}
var release_events: Array[Dictionary] = []


func _runtime_source_signatures() -> Dictionary:
	var result := super._runtime_source_signatures()
	result["support_contact_math"] = FileAccess.get_sha256("res://scripts/player/operator_weapon_contact_solver.gd")
	result["authored_hand_follow"] = FileAccess.get_sha256("res://scripts/player/operator_weapon_authored_pose.gd")
	return result


func _initialize() -> void:
	super._initialize()
	if selected_ids.is_empty():
		selected_ids.assign(["ak-47", "m4a1", "m16a2"])
	for id in selected_ids:
		if id not in ["ak-47", "m4a1", "m16a2"]:
			_fail_once("Release proof is limited to the three reviewed rifles")


func _check_stance(stance: int) -> void:
	previous_release_sample = {}
	for action: StringName in InputMap.get_actions():
		if not InputMap.action_get_events(action).is_empty():
			_fail_once("Physical binding leaked into the isolated release proof: " + String(action))
	var weapon: Node3D = driver.weapon_node
	if capture and (weapon == null or not weapon.is_visible_in_tree()):
		_fail_once("Native release review requires the naturally visible equipped rifle")
	await super._check_stance(stance)


func _capture_state(label: String) -> void:
	# This focused proof reviews the exact handoff pair; the parent matrix
	# remains available for all idle/action/carry views without this filter.
	if label.ends_with("_D_stop_recovery_frame_97") or label.ends_with("_D_stop_recovery_frame_98"):
		await super._capture_state(label)


func _measure_physical_pose() -> Dictionary:
	var result := super._measure_physical_pose()
	var pose: Node3D = driver.get("weapon_pose_solver")
	var skeleton: Skeleton3D = pose.skeleton
	var hand_index := skeleton.find_bone("mixamorig_LeftHand")
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(hand_index)
	var current := {
		"weapon":weapon_id, "posture":player.posture,
		"frame":Engine.get_physics_frames(), "ready":float(driver.get("weapon_ready_weight")),
		"stock_active":bool(pose.authored_shoulder_stock_active),
		"wrist_basis":hand.basis.orthonormalized(),
		"elbow_deg":_physical_elbow_angle(&"Left"),
		"elbow_local":pose._bone_world_position(&"mixamorig_LeftForeArm") - player.global_position,
		"palm_error_m":float(result.get("support_contact_m", INF)),
	}
	if not previous_release_sample.is_empty() and bool(previous_release_sample.stock_active) and not bool(current.stock_active) and float(current.ready) <= 0.001:
		var wrist_before: Basis = previous_release_sample.wrist_basis
		var wrist_after: Basis = current.wrist_basis
		var wrist_delta := rad_to_deg(wrist_before.get_rotation_quaternion().angle_to(wrist_after.get_rotation_quaternion()))
		var elbow_delta := absf(float(current.elbow_deg) - float(previous_release_sample.elbow_deg))
		var old_elbow: Vector3 = previous_release_sample.elbow_local
		var new_elbow: Vector3 = current.elbow_local
		var elbow_step := old_elbow.distance_to(new_elbow)
		var event := {"weapon":weapon_id,"posture":player.posture,"frame":current.frame,
			"ready_before":previous_release_sample.ready,"ready_after":current.ready,
			"wrist_delta_deg":wrist_delta,"elbow_angle_delta_deg":elbow_delta,
			"elbow_step_m":elbow_step,"support_contact_m":current.palm_error_m}
		release_events.append(event)
		if wrist_delta > MAX_RELEASE_ANGLE_DELTA_DEG:
			_fail_once("%s posture%s release wrist jump %.3f deg" % [weapon_id, player.posture, wrist_delta])
		if elbow_delta > MAX_RELEASE_ANGLE_DELTA_DEG or elbow_step > MAX_RELEASE_ELBOW_STEP_M:
			_fail_once("%s posture%s release elbow jump %.3f deg / %.3f mm" % [weapon_id, player.posture, elbow_delta, elbow_step * 1000.0])
	previous_release_sample = current
	return result


func _finish() -> void:
	if not list_only and release_events.size() != selected_ids.size() * 2:
		_fail_once("Each rifle posture must cross the real readiness-zero owner boundary")
	var file := FileAccess.open(output_prefix + "-release.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"events":release_events,"failures":failures,"pass":failures.is_empty()}, "\t"))
	print("RIFLE_SUPPORT_RELEASE ", "PASS" if failures.is_empty() else "FAIL", " ", release_events)
	super._finish()
