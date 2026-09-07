extends "res://tools/rifle_reference_visual_probe.gd"

## Read-only canonical full-right reach envelope. Fixed contact positions are measured,
## never relocated. A completed measurement is not a claim that the pose is valid.
## Run with --weapon=ak-47|m4a1 --output-prefix=/private/tmp/full-right
const Contacts := preload("res://scripts/player/operator_weapon_contact_solver.gd")
var transition_samples: Array[Dictionary] = []

func _run() -> void:
	if weapon_id not in ["ak-47", "m4a1"] or "--automated-test" in OS.get_cmdline_user_args():
		failures.append("Use AK/M4 only, without --automated-test: this probe requires actual movement.")
		_finish()
		return
	scene = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(45)
	player = scene.get_node("Player")
	controller = scene.get_node("WeaponController")
	driver = player.get_node("Mannequin/ProductionAnimation")
	_install_fixture()
	if not bool(controller.call("apply_authorized_weapon_pickup", "res://config/weapons/%s.json" % weapon_id)):
		failures.append("Canonical authorized weapon equip failed")
		_finish()
		return
	await _frames(90)
	player.global_position = Vector3(500.0, 0.02, 500.0)
	player.velocity = Vector3.ZERO
	await _frames(36)
	for stance: int in [0,1]:
		if not bool(player.call("_try_set_posture", stance)):
			failures.append("Canonical posture change refused")
		await _frames(36)
		Input.action_press(&"move_right")
		await _frames(60)
		if _request_shot():
			await _frames(18)
			for frame in 24:
				await _frames(1)
				var row := _reach()
				row["posture"] = stance
				row["horizontal_speed_mps"] = Vector2(player.velocity.x, player.velocity.z).length()
				row["sample_index"] = frame
				samples.append(row)
				if float(row["horizontal_speed_mps"]) < 0.5 or float(row["ready"]) < 0.98:
					failures.append("Sample must be moving in actual ready state")
				_accept_sample(row)
		Input.action_release(&"move_right")
		await _frames(110)
	await _after_measurements()
	_finish()

func _after_measurements() -> void:
	pass

func _accept_sample(_row: Dictionary) -> void:
	pass

func _finish() -> void:
	Input.action_release(&"move_right")
	Input.action_release(&"move_left")
	var report := {
		"canonical_scene": "res://main.tscn", "weapon": weapon_id,
		"measurement_complete": failures.is_empty() and samples.size() == 48,
		"samples": samples, "transition_samples": transition_samples, "failures": failures,
		"note": "Measurement completeness is not physical acceptance. Radius bounds are necessary, not sufficient. No pose, grip, socket or profile overrides are used."
	}
	DirAccess.make_dir_recursive_absolute(output_prefix.get_base_dir())
	var file := FileAccess.open(output_prefix + ".json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	else:
		failures.append("Cannot write measurement report")
	print("FULL_D_REACH_AUDIT ", weapon_id, " samples=", samples.size(), " failures=", failures, " report=", output_prefix + ".json")
	if scene:
		scene.queue_free()
	quit(0 if failures.is_empty() and samples.size() == 48 else 1)

func _reach() -> Dictionary:
	var pose = driver.get("weapon_pose_solver")
	var skeleton: Skeleton3D = pose.skeleton
	var result: Dictionary = {"ready":driver.get("weapon_ready_weight"), "physical": _measure_physical_pose(), "stock_release_m":pose.authored_stock_release_applied_m, "right_stock_turn_weight": pose.authored_stock_right_turn_weight}
	var pocket_delta: Vector3 = pose.stock_socket.global_position - pose.stock_constraint.pocket_marker.global_position
	var reticle_target: Vector3 = driver.get("visual_aim_target")
	var aim_direction: Vector3 = pose.muzzle_socket.global_position.direction_to(reticle_target)
	var aim_right := aim_direction.cross(Vector3.UP).normalized()
	result["stock_offset_aim_forward_m"] = pocket_delta.dot(aim_direction)
	result["stock_offset_aim_right_m"] = pocket_delta.dot(aim_right)
	result["stock_offset_up_m"] = pocket_delta.y
	result["stock_release_frame"] = String(pose.strafe_right_stock_release_frame)
	var chest: Vector3 = pose._bone_world_position(&"mixamorig_Spine2")
	var shoulder_axis: Vector3 = pose._bone_world_position(&"mixamorig_RightArm") - pose._bone_world_position(&"mixamorig_LeftArm")
	var chest_forward := shoulder_axis.cross(Vector3.UP).normalized()
	# Anatomical left/right axes can be reversed by the imported basis. Choose
	# the front hemisphere from the declared right-facing body/aim contract;
	# the plane itself is measured from the live physical shoulder endpoints.
	var expected_front := Vector3(aim_direction.x, 0.0, aim_direction.z).normalized().rotated(Vector3.UP, -PI * 0.5 * maxf(pose.authored_stock_right_turn_weight, 0.0))
	if chest_forward.dot(expected_front) < 0.0:
		chest_forward = -chest_forward
	result["chest_forward_heading_error_deg"] = rad_to_deg(chest_forward.angle_to(expected_front))
	result["chest_plane_contact_clearance_m"] = {
		"stock": (pose.stock_socket.global_position - chest).dot(chest_forward),
		"trigger": (pose.trigger_socket.global_position - chest).dot(chest_forward),
		"support": (pose.support_socket.global_position - chest).dot(chest_forward),
		"muzzle": (pose.muzzle_socket.global_position - chest).dot(chest_forward),
	}
	result["chest_plane_mesh_clearance_m"] = _mesh_front_clearance(pose.weapon_node, chest, chest_forward)
	var debug: Dictionary = driver.get("posture_layer").get_debug_state()
	result["torso_target_deg"] = debug.get("directional_shoulder_target_deg", -999)
	result["torso_target_error_deg"] = debug.get("directional_shoulder_error_deg", -999)
	for side: String in ["Left", "Right"]:
		var shoulder: Vector3 = pose._bone_world_position(StringName("mixamorig_"+side+"Arm"))
		var elbow: Vector3 = pose._bone_world_position(StringName("mixamorig_"+side+"ForeArm"))
		var wrist: Vector3 = pose._bone_world_position(StringName("mixamorig_"+side+"Hand"))
		var palm_anchor: Vector3 = pose.left_palm_anchor_local if side == "Left" else pose.right_palm_anchor_local
		var target: Marker3D = pose.support_hand_target if side == "Left" else pose.trigger_hand_target
		var a := shoulder.distance_to(elbow)
		var b := elbow.distance_to(wrist)
		var radius_min := sqrt(a*a+b*b-2.0*a*b*cos(deg_to_rad(pose.minimum_elbow_angle_deg)))
		var wrist_target := Contacts.wrist_target_for_contact(skeleton,target.global_transform,palm_anchor)
		var target_radius := shoulder.distance_to(wrist_target.origin)
		var contact_radius := shoulder.distance_to(target.global_position)
		var palm_radius := Contacts.scaled_palm_anchor(skeleton,palm_anchor).length()
		var current_angle := rad_to_deg((shoulder-elbow).angle_to(wrist-elbow))
		var target_angle := rad_to_deg(acos(clampf((a*a+b*b-target_radius*target_radius)/(2.0*a*b),-1,1)))
		var row := {"upper_m":a,"forearm_m":b,"target_radius_m":target_radius,"current_radius_m":shoulder.distance_to(wrist),"radius_min42_m":radius_min,"target_elbow_deg":target_angle,"current_elbow_deg":current_angle,"palm_center_radius_m":contact_radius,"wrist_palm_radius_m":palm_radius,"any_wrist_orientation_max_radius_m":contact_radius+palm_radius,"any_orientation_can_reach42":contact_radius+palm_radius>=radius_min,"wrist_residual_m":wrist.distance_to(wrist_target.origin)}
		var target_delta := wrist_target.origin - shoulder
		row["wrist_target_aim_frame_m"] = [target_delta.dot(aim_right), target_delta.y, target_delta.dot(aim_direction)]
		var horizontal_sq := target_delta.x * target_delta.x + target_delta.z * target_delta.z
		row["minimum_extra_pocket_down_m"] = maxf(target_delta.y + sqrt(maxf(radius_min * radius_min - horizontal_sq, 0.0)), 0.0)
		var orientation_alternatives: Array[Dictionary] = []
		for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			for degrees in [-30.0, -15.0, 15.0, 30.0]:
				var alternative := Transform3D((target.global_basis.orthonormalized() * Basis(axis, deg_to_rad(degrees))).orthonormalized(), target.global_position)
				var alternative_wrist := Contacts.wrist_target_for_contact(skeleton, alternative, palm_anchor)
				var radius := shoulder.distance_to(alternative_wrist.origin)
				orientation_alternatives.append({"axis": [axis.x, axis.y, axis.z], "degrees": degrees, "radius_m": radius, "meets_minimum": radius >= radius_min})
		row["read_only_wrist_basis_alternatives"] = orientation_alternatives
		var target_forward := (wrist_target.origin - shoulder).dot(chest_forward)
		var perpendicular_sq := maxf(target_radius * target_radius - target_forward * target_forward, 0.0)
		var radius_max := sqrt(a*a+b*b-2.0*a*b*cos(deg_to_rad(pose.maximum_elbow_angle_deg)))
		row["wrist_target_chest_forward_projection_m"] = target_forward
		# Necessary radial estimate for a pure chest-normal translation. Bore
		# parallax and wrist orientation must be remeasured in a live candidate.
		row["chest_release_required_for_min_angle_m"] = maxf(pose.authored_stock_release_applied_m - target_forward + sqrt(maxf(radius_min*radius_min - perpendicular_sq, 0.0)), 0.0)
		row["chest_release_max_for_max_angle_m"] = maxf(pose.authored_stock_release_applied_m - target_forward + sqrt(maxf(radius_max*radius_max - perpendicular_sq, 0.0)), 0.0)
		if side == "Left":
			var saved: Dictionary = pose.weapon_node.get_meta("support_hand_pose",{})
			var angles := Vector3(float(saved.get("palm_pitch_deg",0)),float(saved.get("palm_yaw_deg",0)),float(saved.get("palm_roll_deg",0)))*PI/180.0
			var canonical := Transform3D((pose.support_socket.global_basis.orthonormalized()*Basis.from_euler(angles,EULER_ORDER_YXZ)).orthonormalized(),pose.support_socket.global_position)
			var canonical_wrist := Contacts.wrist_target_for_contact(skeleton,canonical,palm_anchor)
			row["canonical_orientation_radius_m"] = shoulder.distance_to(canonical_wrist.origin)
			row["canonical_orientation_meets42"] = shoulder.distance_to(canonical_wrist.origin)>=radius_min
		row["minimum_root_shift_any_orientation_m"] = maxf(radius_min - contact_radius - palm_radius, 0.0)
		row["minimum_root_shift_authored_orientation_m"] = maxf(radius_min - target_radius, 0.0)
		if side == "Left":
			row["minimum_root_shift_canonical_orientation_m"] = maxf(radius_min - float(row["canonical_orientation_radius_m"]), 0.0)
		result[side] = row
	return result


func _mesh_front_clearance(weapon: Node3D, chest: Vector3, chest_forward: Vector3) -> float:
	var minimum := INF
	for node in weapon.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var bounds := mesh.get_aabb()
		for corner in 8:
			var point := mesh.global_transform * bounds.get_endpoint(corner)
			minimum = minf(minimum, (point - chest).dot(chest_forward))
	return minimum
