class_name SocomOperatorWeaponPoseSolver
extends Node3D

## Post-animation, visual-only arm solver. The authoritative reticle and shot
## remain outside this layer; this node only makes the rendered operator reach
## a constrained rifle pose that follows the supplied aim intent.

const ARM_BONES := {
	&"left": [&"mixamorig_LeftArm", &"mixamorig_LeftForeArm", &"mixamorig_LeftHand"],
	&"right": [&"mixamorig_RightArm", &"mixamorig_RightForeArm", &"mixamorig_RightHand"],
}

@export_category("Response")
@export_range(1.0, 30.0, 0.5) var enter_response: float = 18.0
@export_range(1.0, 30.0, 0.5) var exit_response: float = 12.0
@export_range(1.0, 30.0, 0.5) var cover_response: float = 16.0

@export_category("Rifle Pose")
@export_range(0.45, 0.90, 0.01) var trigger_reach_ratio: float = 0.72
@export_range(0.55, 0.96, 0.01) var support_reach_ratio: float = 0.84
@export_range(0.02, 0.30, 0.01) var grip_half_width: float = 0.12
@export_range(0.08, 0.38, 0.01) var support_forward_offset: float = 0.20
@export_range(-0.30, 0.20, 0.01) var grip_height_offset: float = -0.06
@export_range(0.15, 0.70, 0.01) var elbow_flare: float = 0.42
@export_range(-0.30, 0.30, 0.01) var elbow_height: float = -0.08
@export_range(0.10, 0.70, 0.01) var tucked_reach_ratio: float = 0.48
@export_range(1, 4, 1) var solve_iterations: int = 3

@export_category("Anatomical Guardrails")
## These limits form a compact human-motion model. They prevent the solver
## from satisfying the reticle by folding an elbow through the ribcage or by
## hyperextending an arm. The torso/orientation layer remains responsible for
## turning the body when a target exceeds this comfortable envelope.
@export_range(20.0, 80.0, 1.0) var minimum_elbow_angle_deg: float = 42.0
@export_range(105.0, 170.0, 1.0) var maximum_elbow_angle_deg: float = 150.0
@export_range(0.20, 0.70, 0.01) var minimum_forward_reach_ratio: float = 0.38
@export_range(45.0, 120.0, 1.0) var shoulder_yaw_limit_deg: float = 92.0
@export_range(20.0, 85.0, 1.0) var shoulder_pitch_up_limit_deg: float = 68.0
@export_range(20.0, 85.0, 1.0) var shoulder_pitch_down_limit_deg: float = 58.0
@export_range(20.0, 80.0, 1.0) var torso_assist_angle_deg: float = 38.0
@export_range(25.0, 90.0, 1.0) var maximum_wrist_correction_deg: float = 72.0
@export var weapon_forward_local := Vector3.BACK

@export_category("Weapon Socket Contract")
@export var use_weapon_socket_contract: bool = true
@export_range(0.0, 45.0, 1.0) var blocked_low_ready_pitch_deg: float = 24.0
@export_range(0.0, 45.0, 1.0) var blocked_crouch_pitch_deg: float = 20.0
@export_range(0.0, 45.0, 1.0) var blocked_prone_pitch_deg: float = 16.0
@export_range(0.0, 1.0, 0.05) var blocked_pose_threshold: float = 0.55

var skeleton: Skeleton3D
var weapon_node: Node3D
var trigger_socket: Marker3D
var support_socket: Marker3D
var muzzle_socket: Marker3D
var trigger_hand_target: Marker3D
var support_hand_target: Marker3D
var right_elbow_pole: Marker3D
var left_elbow_pole: Marker3D
var aim_target_marker: Marker3D
var bone_indices: Dictionary = {}
var current_weight: float = 0.0
var desired_weight: float = 0.0
var target_reachable: bool = true
var trigger_hand_error_m: float = 0.0
var support_hand_error_m: float = 0.0
var last_aim_direction := Vector3.FORWARD
var last_target_point := Vector3.ZERO
var last_posture: StringName = &"STANDING"
var anatomical_adjustment_m: float = 0.0
var torso_assist_requested: bool = false
var aim_yaw_demand_deg: float = 0.0
var aim_pitch_demand_deg: float = 0.0
var right_elbow_angle_deg: float = 0.0
var left_elbow_angle_deg: float = 0.0
var weapon_aim_error_deg: float = 0.0
var wrist_correction_deg: float = 0.0
var cover_pose_amount: float = 0.0
var cover_pose_name: StringName = &"CLEAR"
var shot_blocked: bool = false
var socket_contract_active: bool = false
var adaptive_support_socket: bool = false


func bind(target_skeleton: Skeleton3D, attached_weapon: Node3D) -> void:
	skeleton = target_skeleton
	weapon_node = attached_weapon
	trigger_socket = _find_weapon_socket("Socket_RightHand")
	support_socket = _find_weapon_socket("Socket_LeftHand")
	muzzle_socket = _find_weapon_socket("Socket_Muzzle")
	socket_contract_active = (
		use_weapon_socket_contract
		and trigger_socket != null
		and support_socket != null
		and muzzle_socket != null
	)
	adaptive_support_socket = (
		support_socket != null
		and not bool(support_socket.get_meta("authored_weapon_socket", false))
	)
	bone_indices.clear()
	if skeleton == null:
		return
	for side: StringName in ARM_BONES:
		var names: Array = ARM_BONES[side]
		for bone_name in names:
			bone_indices[StringName(bone_name)] = skeleton.find_bone(StringName(bone_name))
	_build_targets()


func apply(
	aim_yaw: float,
	aim_pitch: float,
	posture: StringName,
	movement_state: StringName,
	ready_weight: float,
	obstruction_amount: float,
	requested_action: StringName,
	world_aim_target: Vector3,
	body: Node3D,
	delta: float
) -> void:
	if skeleton == null or body == null:
		return
	# The pose is rebuilt from the animation result every frame. Clearing the
	# prior visual override prevents the IK result from feeding back into its
	# own measurements and lets animation remain the source pose.
	skeleton.clear_bones_global_pose_override()
	skeleton.force_update_all_bone_transforms()
	last_posture = posture
	var action_owns_arms := (
		movement_state in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]
		or requested_action in [&"reload", &"prone_reload"]
	)
	desired_weight = (
		0.0
		if action_owns_arms
		else clampf(ready_weight, 0.0, 1.0)
	)
	var response := enter_response if desired_weight > current_weight else exit_response
	current_weight = lerpf(
		current_weight,
		desired_weight,
		1.0 - exp(-response * delta)
	)
	if current_weight <= 0.001:
		return

	var right_shoulder := _bone_world_position(&"mixamorig_RightArm")
	var left_shoulder := _bone_world_position(&"mixamorig_LeftArm")
	var shoulder_center := (right_shoulder + left_shoulder) * 0.5
	var aim_direction := _resolve_aim_direction(
		aim_yaw,
		aim_pitch,
		world_aim_target,
		shoulder_center,
		body
	)
	last_aim_direction = aim_direction
	var body_forward := (-body.global_basis.z).normalized()
	var body_right := body.global_basis.x.normalized()
	var flat_aim := Vector3(aim_direction.x, 0.0, aim_direction.z).normalized()
	if flat_aim.length_squared() > 0.50:
		aim_yaw_demand_deg = rad_to_deg(atan2(flat_aim.dot(body_right), flat_aim.dot(body_forward)))
	aim_pitch_demand_deg = rad_to_deg(asin(clampf(aim_direction.y, -1.0, 1.0)))
	torso_assist_requested = absf(aim_yaw_demand_deg) > torso_assist_angle_deg
	last_target_point = (
		world_aim_target
		if world_aim_target != Vector3.ZERO
		else shoulder_center + aim_direction * 20.0
	)
	var world_up := Vector3.UP
	var aim_right := aim_direction.cross(world_up).normalized()
	if aim_right.length_squared() < 0.50:
		aim_right = body.global_basis.x.normalized()

	var right_reach := _arm_length(&"right")
	var left_reach := _arm_length(&"left")
	var obstruction_target := clampf(obstruction_amount, 0.0, 1.0)
	cover_pose_amount = lerpf(
		cover_pose_amount,
		obstruction_target,
		1.0 - exp(-cover_response * clampf(delta, 0.0, 0.05))
	)
	var tuck := cover_pose_amount
	shot_blocked = cover_pose_amount >= blocked_pose_threshold
	cover_pose_name = (
		(
			&"PRONE_TUCK"
			if posture == &"PRONE"
			else (&"CROUCH_LOW_READY" if posture == &"CROUCHED" else &"LOW_READY")
		)
		if shot_blocked
		else (&"REFRAMING" if cover_pose_amount > 0.02 else &"CLEAR")
	)
	var trigger_ratio := lerpf(trigger_reach_ratio, tucked_reach_ratio, tuck)
	var raw_trigger_position := (
		shoulder_center
		+ aim_direction * right_reach * trigger_ratio
		+ aim_right * grip_half_width
		+ world_up * lerpf(grip_height_offset, 0.10, tuck)
	)
	var raw_support_position := (
		shoulder_center
		+ aim_direction * (
			left_reach * lerpf(support_reach_ratio, tucked_reach_ratio, tuck)
		)
		- aim_right * grip_half_width
		+ world_up * lerpf(grip_height_offset - 0.01, 0.12, tuck)
	)
	# The support hand advances along the foregrip only while both arms can
	# reach it. This keeps the pose useful with different weapon proportions.
	raw_support_position += aim_direction * support_forward_offset * (1.0 - tuck)
	var trigger_position := _fit_human_reach(
		right_shoulder,
		raw_trigger_position,
		aim_direction,
		right_reach
	)
	var support_position := _fit_human_reach(
		left_shoulder,
		raw_support_position,
		aim_direction,
		left_reach
	)
	anatomical_adjustment_m = maxf(
		raw_trigger_position.distance_to(trigger_position),
		raw_support_position.distance_to(support_position)
	)
	target_reachable = (
		raw_trigger_position.distance_to(trigger_position) <= 0.005
		and raw_support_position.distance_to(support_position) <= 0.005
	)

	trigger_hand_target.global_position = trigger_position
	support_hand_target.global_position = support_position
	aim_target_marker.global_position = last_target_point
	var prone_pole_raise := 0.12 if posture == &"PRONE" else 0.0
	right_elbow_pole.global_position = (
		right_shoulder
		+ aim_right * elbow_flare
		+ aim_direction * 0.16
		+ world_up * (elbow_height + prone_pole_raise)
	)
	left_elbow_pole.global_position = (
		left_shoulder
		- aim_right * elbow_flare
		+ aim_direction * 0.16
		+ world_up * (elbow_height + prone_pole_raise)
	)
	for _iteration in range(solve_iterations):
		_solve_arm(&"right", trigger_hand_target, right_elbow_pole)
		_solve_arm(&"left", support_hand_target, left_elbow_pole)
	skeleton.force_update_all_bone_transforms()
	if socket_contract_active:
		_place_socketed_weapon(trigger_position, aim_direction, body_forward)
		if adaptive_support_socket:
			support_socket.global_position = support_position
		trigger_hand_target.global_position = trigger_socket.global_position
		support_hand_target.global_position = support_socket.global_position
		if not adaptive_support_socket:
			_solve_arm(&"left", support_hand_target, left_elbow_pole)
			skeleton.force_update_all_bone_transforms()
		_update_socket_weapon_error()
	else:
		_align_weapon_to_aim(aim_direction)
	_update_errors()


func get_debug_state() -> Dictionary:
	return {
		"active": current_weight > 0.001,
		"weight": current_weight,
		"desired_weight": desired_weight,
		"target_reachable": target_reachable,
		"trigger_hand_error_m": trigger_hand_error_m,
		"support_hand_error_m": support_hand_error_m,
		"aim_direction": last_aim_direction,
		"aim_target": last_target_point,
		"posture": last_posture,
		"anatomical_adjustment_m": anatomical_adjustment_m,
		"torso_assist_requested": torso_assist_requested,
		"aim_yaw_demand_deg": aim_yaw_demand_deg,
		"aim_pitch_demand_deg": aim_pitch_demand_deg,
		"right_elbow_angle_deg": right_elbow_angle_deg,
		"left_elbow_angle_deg": left_elbow_angle_deg,
		"weapon_aim_error_deg": weapon_aim_error_deg,
		"wrist_correction_deg": wrist_correction_deg,
		"socket_contract_active": socket_contract_active,
		"adaptive_support_socket": adaptive_support_socket,
		"cover_pose_amount": cover_pose_amount,
		"cover_pose_name": cover_pose_name,
		"shot_blocked": shot_blocked,
	}


func _find_weapon_socket(socket_name: String) -> Marker3D:
	if weapon_node == null:
		return null
	return weapon_node.find_child(socket_name, true, false) as Marker3D


func _place_socketed_weapon(
	trigger_goal: Vector3,
	aim_direction: Vector3,
	body_forward: Vector3
) -> void:
	if weapon_node == null or trigger_socket == null:
		return
	var blocked_pitch_deg := blocked_low_ready_pitch_deg
	if last_posture == &"CROUCHED":
		blocked_pitch_deg = blocked_crouch_pitch_deg
	elif last_posture == &"PRONE":
		blocked_pitch_deg = blocked_prone_pitch_deg
	var low_ready_direction := (
		body_forward.rotated(
			body_forward.cross(Vector3.UP).normalized(),
			-deg_to_rad(blocked_pitch_deg)
		)
	).normalized()
	if low_ready_direction.length_squared() < 0.50:
		low_ready_direction = aim_direction
	var render_direction := aim_direction.slerp(low_ready_direction, cover_pose_amount)
	var stable_up := Vector3.UP
	if absf(render_direction.dot(stable_up)) > 0.96:
		stable_up = Vector3.FORWARD
	var world_scale := weapon_node.global_basis.get_scale()
	weapon_node.global_basis = Basis.looking_at(
		render_direction.normalized(),
		stable_up,
		false
	).scaled(world_scale)
	weapon_node.global_position += trigger_goal - trigger_socket.global_position


func _update_socket_weapon_error() -> void:
	if muzzle_socket == null or trigger_socket == null:
		return
	var barrel_direction := (muzzle_socket.global_position - trigger_socket.global_position).normalized()
	if barrel_direction.length_squared() < 0.50:
		return
	weapon_aim_error_deg = rad_to_deg(barrel_direction.angle_to(last_aim_direction))
	wrist_correction_deg = 0.0


func _build_targets() -> void:
	trigger_hand_target = _marker("TriggerHandIKTarget")
	support_hand_target = _marker("SupportHandIKTarget")
	right_elbow_pole = _marker("RightElbowPole")
	left_elbow_pole = _marker("LeftElbowPole")
	aim_target_marker = _marker("WeaponAimTarget")


func _marker(node_name: String) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = node_name
	add_child(marker)
	return marker


func _resolve_aim_direction(
	aim_yaw: float,
	aim_pitch: float,
	world_target: Vector3,
	origin: Vector3,
	body: Node3D
) -> Vector3:
	if world_target != Vector3.ZERO and origin.distance_to(world_target) > 0.10:
		return (world_target - origin).normalized()
	var yaw_basis := Basis(Vector3.UP, body.global_rotation.y + aim_yaw)
	var yaw_forward := yaw_basis * Vector3.FORWARD
	var right := yaw_basis * Vector3.RIGHT
	return (Basis(right, aim_pitch) * yaw_forward).normalized()


func _arm_length(side: StringName) -> float:
	var names: Array = ARM_BONES[side]
	var root := _bone_world_position(StringName(names[0]))
	var middle := _bone_world_position(StringName(names[1]))
	var hand := _bone_world_position(StringName(names[2]))
	return maxf(root.distance_to(middle) + middle.distance_to(hand), 0.15)


func _fit_human_reach(
	origin: Vector3,
	target: Vector3,
	aim_direction: Vector3,
	reach: float
) -> Vector3:
	var fitted := target
	# A wall tuck shortens the rifle pose, but a trained operator does not pull
	# either hand behind the shoulder plane. Preserve enough forward reach for
	# the elbows to remain outside the torso.
	var forward_reach := (fitted - origin).dot(aim_direction)
	var minimum_forward := reach * minimum_forward_reach_ratio
	if forward_reach < minimum_forward:
		fitted += aim_direction * (minimum_forward - forward_reach)

	var delta := fitted - origin
	if delta.length_squared() < 0.000001:
		delta = aim_direction * minimum_forward
	var direction := delta.normalized()
	var upper := reach * 0.5
	var lower := reach - upper
	var minimum_distance := _distance_for_elbow_angle(
		upper,
		lower,
		deg_to_rad(minimum_elbow_angle_deg)
	)
	var maximum_distance := minf(
		_distance_for_elbow_angle(
			upper,
			lower,
			deg_to_rad(maximum_elbow_angle_deg)
		),
		reach * 0.965
	)
	return origin + direction * clampf(delta.length(), minimum_distance, maximum_distance)


func _distance_for_elbow_angle(upper: float, lower: float, angle: float) -> float:
	return sqrt(maxf(
		upper * upper
		+ lower * lower
		- 2.0 * upper * lower * cos(angle),
		0.0001
	))


func _solve_arm(side: StringName, target_node: Node3D, pole_node: Node3D) -> void:
	var names: Array = ARM_BONES[side]
	var root_index := int(bone_indices.get(StringName(names[0]), -1))
	var middle_index := int(bone_indices.get(StringName(names[1]), -1))
	var end_index := int(bone_indices.get(StringName(names[2]), -1))
	if root_index < 0 or middle_index < 0 or end_index < 0:
		return
	skeleton.force_update_all_bone_transforms()
	var root_pose := skeleton.get_bone_global_pose(root_index)
	var middle_pose := skeleton.get_bone_global_pose(middle_index)
	var end_pose := skeleton.get_bone_global_pose(end_index)
	var root_position := root_pose.origin
	var middle_position := middle_pose.origin
	var end_position := end_pose.origin
	var upper_length := maxf(root_position.distance_to(middle_position), 0.001)
	var lower_length := maxf(middle_position.distance_to(end_position), 0.001)
	var inverse_skeleton := skeleton.global_transform.affine_inverse()
	var target_position: Vector3 = inverse_skeleton * target_node.global_position
	var pole_position: Vector3 = inverse_skeleton * pole_node.global_position
	var root_to_target := target_position - root_position
	var local_reach := upper_length + lower_length
	var target_distance := clampf(
		root_to_target.length(),
		absf(upper_length - lower_length) + local_reach * 0.02,
		local_reach * 0.965
	)
	if root_to_target.length_squared() < 0.000001:
		return
	var target_direction := root_to_target.normalized()
	target_position = root_position + target_direction * target_distance
	var plane_normal := target_direction.cross(pole_position - root_position).normalized()
	if plane_normal.length_squared() < 0.25:
		plane_normal = target_direction.cross(middle_position - root_position).normalized()
	if plane_normal.length_squared() < 0.25:
		plane_normal = target_direction.cross(Vector3.UP).normalized()
	var bend_direction := plane_normal.cross(target_direction).normalized()
	if (middle_position - root_position).dot(bend_direction) < 0.0:
		bend_direction = -bend_direction
	var along := clampf(
		(
			upper_length * upper_length
			+ target_distance * target_distance
			- lower_length * lower_length
		) / maxf(2.0 * target_distance, 0.001),
		0.0,
		upper_length
	)
	var away := sqrt(maxf(upper_length * upper_length - along * along, 0.0))
	var desired_middle := (
		root_position
		+ target_direction * along
		+ bend_direction * away
	)
	var current_upper_direction := (middle_position - root_position).normalized()
	var desired_upper_direction := (desired_middle - root_position).normalized()
	var root_delta := Quaternion(current_upper_direction, desired_upper_direction)
	root_pose.basis = _blend_rotated_basis(root_pose.basis, root_delta, current_weight)
	skeleton.set_bone_global_pose_override(root_index, root_pose, 1.0, true)
	skeleton.force_update_all_bone_transforms()

	middle_pose = skeleton.get_bone_global_pose(middle_index)
	end_pose = skeleton.get_bone_global_pose(end_index)
	middle_position = middle_pose.origin
	end_position = end_pose.origin
	var current_lower_direction := (end_position - middle_position).normalized()
	var desired_lower_direction := (target_position - middle_position).normalized()
	if current_lower_direction.length_squared() > 0.50 and desired_lower_direction.length_squared() > 0.50:
		var middle_delta := Quaternion(current_lower_direction, desired_lower_direction)
		middle_pose.basis = _blend_rotated_basis(
			middle_pose.basis,
			middle_delta,
			current_weight
		)
		skeleton.set_bone_global_pose_override(middle_index, middle_pose, 1.0, true)
		skeleton.force_update_all_bone_transforms()


func _blend_rotated_basis(source: Basis, delta: Quaternion, weight: float) -> Basis:
	var source_rotation := source.get_rotation_quaternion().normalized()
	var solved_rotation := (delta * source_rotation).normalized()
	var blended := source_rotation.slerp(solved_rotation, clampf(weight, 0.0, 1.0))
	return Basis(blended).scaled(source.get_scale())


func _align_weapon_to_aim(aim_direction: Vector3) -> void:
	if weapon_node == null:
		weapon_aim_error_deg = 0.0
		wrist_correction_deg = 0.0
		return
	var hand_index := int(bone_indices.get(&"mixamorig_RightHand", -1))
	if hand_index < 0:
		return
	skeleton.force_update_all_bone_transforms()
	var hand_pose := skeleton.get_bone_global_pose(hand_index)
	# BoneAttachment3D follows the hand pose. Computing the barrel direction
	# from that invariant local relationship avoids a one-frame attachment lag.
	var weapon_forward_in_hand := (
		weapon_node.basis * weapon_forward_local
	).normalized()
	var current_local := (hand_pose.basis * weapon_forward_in_hand).normalized()
	var inverse_skeleton_basis := skeleton.global_basis.inverse()
	var aim_local := (inverse_skeleton_basis * aim_direction).normalized()
	if current_local.length_squared() < 0.50 or aim_local.length_squared() < 0.50:
		return
	var required_angle := current_local.angle_to(aim_local)
	wrist_correction_deg = rad_to_deg(required_angle)
	# The shoulder and elbow solve position first; the wrist then aligns the
	# attached rifle. Clamp only the visual wrist contribution. Any residual is
	# reported as torso-assist demand instead of allowing an impossible joint.
	var applied_angle := minf(required_angle, deg_to_rad(maximum_wrist_correction_deg))
	var correction_weight := (
		0.0 if required_angle <= 0.00001 else applied_angle / required_angle
	)
	var full_delta := Quaternion(current_local, aim_local)
	var delta := Quaternion.IDENTITY.slerp(full_delta, correction_weight)
	hand_pose.basis = _blend_rotated_basis(hand_pose.basis, delta, current_weight)
	skeleton.set_bone_global_pose_override(hand_index, hand_pose, 1.0, true)
	skeleton.force_update_all_bone_transforms()
	var solved_local := (hand_pose.basis * weapon_forward_in_hand).normalized()
	weapon_aim_error_deg = rad_to_deg(solved_local.angle_to(aim_local))
	if weapon_aim_error_deg > 1.0:
		torso_assist_requested = true


func _bone_world_position(bone_name: StringName) -> Vector3:
	var index := int(bone_indices.get(bone_name, -1))
	if index < 0:
		return skeleton.global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin


func _update_errors() -> void:
	trigger_hand_error_m = _bone_world_position(&"mixamorig_RightHand").distance_to(
		trigger_hand_target.global_position
	)
	support_hand_error_m = _bone_world_position(&"mixamorig_LeftHand").distance_to(
		support_hand_target.global_position
	)
	right_elbow_angle_deg = _current_elbow_angle(&"right")
	left_elbow_angle_deg = _current_elbow_angle(&"left")


func _current_elbow_angle(side: StringName) -> float:
	var names: Array = ARM_BONES[side]
	var shoulder := _bone_world_position(StringName(names[0]))
	var elbow := _bone_world_position(StringName(names[1]))
	var hand := _bone_world_position(StringName(names[2]))
	var upper := (shoulder - elbow).normalized()
	var lower := (hand - elbow).normalized()
	if upper.length_squared() < 0.50 or lower.length_squared() < 0.50:
		return 0.0
	return rad_to_deg(acos(clampf(upper.dot(lower), -1.0, 1.0)))
