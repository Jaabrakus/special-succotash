class_name SocomTraversalHandModifier
extends SkeletonModifier3D

## Traversal-only visual hips residual and arm rotations; never moves CharacterBody.
var targets: Array[Vector3] = []
var weight: float = 0.0
var hand_weights: Array[float] = [0.0, 0.0]
var errors_m: Array[float] = []
var reach_diagnostics: Array[Dictionary] = []
var profile: Dictionary = {}
var visual_root_delta := Vector3.ZERO
var requested_phase := 0.0
var evaluated_phase := 0.0
var evaluated_hand_weights: Array[float] = []
var animation_tree: AnimationTree
var body_node: Node3D
var animation_clip: StringName
var animation_duration := 0.0
var animation_start_phase := 0.0
var animation_end_phase := 1.0
var contact_presentation: Dictionary = {}
var root_profile: Dictionary = {}
var entry_weight := 0.0
var wall_clearance_delta := Vector3.ZERO
var evaluated_wall_points: Array[Dictionary] = []
var evaluated_source_hips_rotation := Quaternion.IDENTITY
var exit_pose: Array[Transform3D] = []
var track_exit_pose := false
var exit_active := false
var exit_elapsed := 0.0
var exit_seconds := 0.24
var exit_weight := 0.0
var elbow_profile: Dictionary = {}
var hand_shape_profile: Dictionary = {}
var terminal_support_profile: Dictionary = {}
var terminal_support_delta_m := 0.0
var exit_live_upper_body := false

func track_traversal_exit(slot: String) -> void:
	# Capture even when the source has released both hands (and for vaults,
	# which have no hand-contact solve). Do not carry an old climb into a hang.
	exit_active = false
	exit_weight = 0.0
	track_exit_pose = slot in ["pull_up", "pull_up_free", "low_mantle", "vault"]
	if track_exit_pose:
		active = true
	else:
		exit_pose.clear()

func begin_exit(settings: Dictionary) -> void:
	_clear_contact()
	track_exit_pose = false
	exit_elapsed = 0.0
	var seconds := float(settings.get("seconds", 0.24))
	exit_seconds = clampf(seconds, 0.01, 0.5) if is_finite(seconds) else 0.24
	exit_active = bool(settings.get("enabled", false)) and not exit_pose.is_empty()
	exit_weight = 1.0 if exit_active else 0.0
	active = exit_active
	if not exit_active: exit_pose.clear()

func advance_exit(delta: float) -> void:
	if not exit_active: return
	exit_elapsed = minf(exit_elapsed + maxf(delta, 0.0), exit_seconds)
	exit_weight = 1.0 - smoothstep(0.0, exit_seconds, exit_elapsed)
	if exit_elapsed >= exit_seconds:
		cancel_exit()

func cancel_exit() -> void:
	exit_live_upper_body = false
	exit_active = false
	exit_weight = 0.0
	track_exit_pose = false
	exit_pose.clear()
	_clear_contact()

func _capture_exit_pose(skeleton: Skeleton3D) -> void:
	if not track_exit_pose: return
	exit_pose.resize(skeleton.get_bone_count())
	for bone in exit_pose.size():
		exit_pose[bone] = skeleton.get_bone_pose(bone)

func _apply_exit_pose(skeleton: Skeleton3D) -> void:
	if exit_pose.size() != skeleton.get_bone_count():
		cancel_exit()
		return
	for bone in exit_pose.size():
		# Recovery was already blended into the tree before support ended.
		# Keep that live gesture advancing; replaying its captured upper body
		# would freeze the draw while its timer and weapon transfer advance.
		if exit_live_upper_body and _belongs_to_upper_body(skeleton, bone):
			continue
		var destination := skeleton.get_bone_pose(bone)
		var pose := destination.interpolate_with(exit_pose[bone], exit_weight)
		skeleton.set_bone_pose_position(bone, pose.origin)
		skeleton.set_bone_pose_rotation(bone, pose.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(bone, pose.basis.get_scale())

func _belongs_to_upper_body(skeleton: Skeleton3D, bone: int) -> bool:
	while bone >= 0:
		if skeleton.get_bone_name(bone) == "mixamorig_Spine": return true
		bone = skeleton.get_bone_parent(bone)
	return false

func update_contact(presentation: Dictionary, settings: Dictionary, delta: float) -> void:
	var slot := str(presentation.get("slot", ""))
	hand_shape_profile = settings.get("ledge_hand_shape", {})
	terminal_support_profile = settings.get("terminal_support", {})
	elbow_profile = settings.get("hang_elbow_pole", {}) if slot in ["hang", "hang_free", "pull_up", "pull_up_free"] else {}
	var separate_profile := slot in ["low_mantle", "hang_free", "pull_up_free", "narrow_idle", "narrow_left", "narrow_right"]
	profile = settings.get("hand_contact_by_slot", {}).get(slot, {} if separate_profile else settings.get("hand_contact", {}))
	contact_presentation = presentation.duplicate()
	root_profile = settings.get("visual_root_by_slot", {}).get(slot, {} if separate_profile else settings.get("pull_up_visual_root", {}))
	requested_phase = float(presentation.get("phase", 0.0))
	var anchor_value: Variant = presentation.get("anchor")
	var normal_value: Variant = presentation.get("surface_normal")
	if not is_finite(requested_phase) or not bool(profile.get("enabled", false)) or slot not in ["hang", "hang_free", "pull_up", "pull_up_free", "low_mantle", "narrow_idle", "narrow_left", "narrow_right"] or not anchor_value is Vector3 or not normal_value is Vector3:
		_clear_contact()
		return
	if not anchor_value.is_finite() or not normal_value.is_finite() or normal_value.slide(Vector3.UP).length_squared() < 0.01:
		_clear_contact()
		return
	entry_weight = move_toward(entry_weight, 1.0, delta / maxf(float(profile.get("blend_seconds", 0.12)), 0.01))
	_update_hand_weights(slot, requested_phase)
	visual_root_delta = _root_residual(presentation, root_profile)
	active = weight > 0.001 or visual_root_delta.length_squared() > 0.000001 or bool(profile.get("align_only", false))
	if not active: return
	var normal: Vector3 = normal_value.slide(Vector3.UP).normalized()
	var side := normal.cross(Vector3.UP).normalized()
	var anchor: Vector3 = presentation.anchor
	var center := anchor + normal * float(profile.get("wrist_outset_m", 0.04)) + Vector3.UP * float(profile.get("wrist_height_m", 0.02))
	var span := float(profile.get("hand_spacing_m", 0.38)) * 0.5
	targets.assign([center + side * span, center - side * span])

func _clear_contact() -> void:
	weight = 0.0
	entry_weight = 0.0
	hand_weights.assign([0.0, 0.0])
	visual_root_delta = Vector3.ZERO
	active = false
	targets.clear()
	errors_m.clear()
	reach_diagnostics.clear()
	evaluated_hand_weights.clear()
	evaluated_wall_points.clear()
	wall_clearance_delta = Vector3.ZERO
	contact_presentation.clear()

func _update_hand_weights(slot: String, phase: float) -> void:
	if bool(profile.get("align_only", false)):
		hand_weights.assign([0.0, 0.0])
		weight = 0.0
		return
	for index in 2:
		var release: Dictionary = profile.get("left_release" if index == 0 else "right_release", {})
		var wanted := 1.0 if slot in ["hang", "hang_free"] else 1.0 - smoothstep(float(release.get("start_phase", profile.get("release_start_phase", 0.12))), float(release.get("end_phase", profile.get("release_end_phase", 0.35))), phase)
		if profile.has("acquire"):
			var acquire: Dictionary = profile.acquire
			wanted *= smoothstep(float(acquire.get("start_phase", 0.0)), float(acquire.get("end_phase", 0.1)), phase)
		hand_weights[index] = entry_weight * wanted
	weight = maxf(hand_weights[0], hand_weights[1])

func _root_residual(presentation: Dictionary, settings: Dictionary) -> Vector3:
	if str(presentation.get("slot", "")) not in ["hang", "hang_free", "pull_up", "pull_up_free", "low_mantle"] or not bool(settings.get("enabled", false)): return Vector3.ZERO
	if str(settings.get("source", "")) == "" or str(presentation.get("source", "")) != str(settings.source): return Vector3.ZERO
	if str(presentation.get("slot", "")) in ["hang", "hang_free"]:
		return Vector3.UP * clampf(float(settings.get("hang_up_m", 0.0)), 0.0, 0.35) * entry_weight
	for key in ["start_point", "landing_point", "body_point"]:
		var point: Variant = presentation.get(key)
		if not point is Vector3 or not point.is_finite(): return Vector3.ZERO
	var start: Vector3 = presentation.start_point
	var end: Vector3 = presentation.landing_point
	var body: Vector3 = presentation.body_point
	var phase := clampf(float(presentation.get("phase", 0.0)), 0.0, 1.0)
	# Preserve source displacement while the hands support the body. Stretching
	# its forward travel to fit the landing moved shoulders away from the edge.
	# Reconcile the remaining endpoint only after the source releases support.
	var travel := (end - start).slide(Vector3.UP)
	var forward := travel.normalized() * minf(travel.length(), float(settings.get("source_forward_m", travel.length())))
	var rise := minf(end.y - start.y, float(settings.get("source_rise_m", end.y - start.y)))
	var desired := start + forward * _curve(settings.get("forward_progress", []), phase) + Vector3.UP * rise * _curve(settings.get("vertical_progress", []), phase)
	var source_end := start + forward + Vector3.UP * rise
	desired += (end - source_end) * smoothstep(float(settings.get("endpoint_fit_start_phase", 0.8)), 1.0, phase)
	var support_offset: Dictionary = settings.get("support_offset", {})
	var support_fade := 1.0 - smoothstep(float(support_offset.get("fade_start_phase", 0.45)), float(support_offset.get("fade_end_phase", 0.8)), phase)
	desired += (travel.normalized() * float(support_offset.get("forward_m", 0.0)) + Vector3.UP * float(support_offset.get("up_m", 0.0))) * support_fade * entry_weight
	var residual := desired - body
	var horizontal := residual.slide(Vector3.UP).limit_length(float(settings.get("max_horizontal_m", 0.65)))
	residual = horizontal + Vector3.UP * clampf(residual.y, -float(settings.get("max_down_m", 0.8)), float(settings.get("max_up_m", 0.35)))
	return residual * (1.0 - smoothstep(float(settings.get("exit_fade_start_phase", 0.92)), 1.0, phase))

func _curve(points: Array, phase: float) -> float:
	if points.size() < 2: return phase
	for index in range(1, points.size()):
		var left: Array = points[index - 1]
		var right: Array = points[index]
		if phase <= float(right[0]):
			return lerpf(float(left[1]), float(right[1]), clampf((phase - float(left[0])) / maxf(float(right[0]) - float(left[0]), 0.0001), 0.0, 1.0))
	return float(points[-1][1])

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null: return
	if exit_active:
		_apply_exit_pose(skeleton)
		return
	if targets.size() != 2:
		_capture_exit_pose(skeleton)
		return
	errors_m.clear()
	reach_diagnostics.clear()
	evaluated_phase = requested_phase
	# Driver requests the NEXT tree seek. Contact must use the animation/body
	# actually being evaluated now, especially when physics runs twice per draw.
	if is_instance_valid(animation_tree) and animation_duration > 0.0 and animation_clip != &"":
		var route := "modern_state_" if float(animation_tree.get("parameters/route_blend/blend_amount")) > 0.5 else "legacy_"
		var position: Variant = animation_tree.get("parameters/" + route + str(animation_clip) + "/current_position")
		if position is float and is_finite(position):
			evaluated_phase = clampf((position / animation_duration - animation_start_phase) / maxf(animation_end_phase - animation_start_phase, 0.001), 0.0, 1.0)
	_update_hand_weights(str(contact_presentation.get("slot", "")), evaluated_phase)
	var evaluated_presentation := contact_presentation.duplicate()
	evaluated_presentation.phase = evaluated_phase
	if is_instance_valid(body_node): evaluated_presentation.body_point = body_node.global_position
	visual_root_delta = _root_residual(evaluated_presentation, root_profile)
	evaluated_hand_weights.assign(hand_weights)
	_align_braced_pose_to_wall(skeleton, evaluated_presentation)
	if visual_root_delta.length_squared() > 0.000001:
		var hips := skeleton.find_bone("mixamorig_Hips")
		if hips >= 0:
			var pose := skeleton.get_bone_global_pose(hips)
			pose.origin += skeleton.global_basis.inverse() * visual_root_delta
			skeleton.set_bone_global_pose(hips, pose)
			skeleton.force_update_bone_child_transform(hips)
	_apply_wall_clearance(skeleton, evaluated_presentation)
	_align_terminal_support(skeleton, evaluated_presentation)
	if weight <= 0.001:
		_capture_exit_pose(skeleton)
		return
	for index in 2:
		var side := "Left" if index == 0 else "Right"
		var upper := skeleton.find_bone("mixamorig_" + side + "Arm")
		var lower := skeleton.find_bone("mixamorig_" + side + "ForeArm")
		var hand := skeleton.find_bone("mixamorig_" + side + "Hand")
		if mini(upper, mini(lower, hand)) < 0: continue
		var a := skeleton.get_bone_global_pose(upper)
		var b := skeleton.get_bone_global_pose(lower)
		var c := skeleton.get_bone_global_pose(hand)
		var authored_hand_basis := c.basis
		var l1 := a.origin.distance_to(b.origin)
		var l2 := b.origin.distance_to(c.origin)
		var target := c.origin.lerp(skeleton.global_transform.affine_inverse() * targets[index], hand_weights[index])
		reach_diagnostics.append({"side": side, "shoulder": skeleton.global_transform * a.origin, "target": targets[index], "distance": a.origin.distance_to(target), "arm_length": l1+l2})
		var axis := (target - a.origin).normalized()
		var distance := clampf(a.origin.distance_to(target), absf(l1 - l2) + 0.000001, l1 + l2 - 0.000001)
		if l1 < 0.000001 or l2 < 0.000001 or distance < 0.000001: continue
		var along := (l1*l1 - l2*l2 + distance*distance) / (2*distance)
		var height := sqrt(maxf(l1*l1 - along*along, 0.0))
		var bend := (b.origin - a.origin).slide(axis)
		if bend.length_squared() < 0.0000001: bend = axis.cross(Vector3.UP)
		if bend.length_squared() < 0.0000001: bend = axis.cross(Vector3.RIGHT)
		bend = _elbow_bend(skeleton, axis, bend, index)
		var elbow := a.origin + axis*along + bend.normalized()*height
		_rotate(skeleton, upper, b.origin - a.origin, elbow - a.origin)
		b = skeleton.get_bone_global_pose(lower)
		c = skeleton.get_bone_global_pose(hand)
		_rotate(skeleton, lower, c.origin - b.origin, target - b.origin)
		var ledge_shape: bool = bool(hand_shape_profile.get("enabled", false)) and str(contact_presentation.get("slot", "")) in hand_shape_profile.get("slots", [])
		if ledge_shape or bool(root_profile.get("preserve_authored_hand_rotation", false)):
			var hand_pose := skeleton.get_bone_global_pose(hand)
			var wanted := _ledge_hand_basis(skeleton, side) if ledge_shape else authored_hand_basis
			hand_pose.basis = authored_hand_basis.slerp(wanted, hand_weights[index]) if ledge_shape else wanted
			skeleton.set_bone_global_pose(hand, hand_pose)
			skeleton.force_update_bone_child_transform(hand)
			reach_diagnostics[index]["hand_rotation_error_rad"] = hand_pose.basis.get_rotation_quaternion().angle_to(skeleton.get_bone_global_pose(hand).basis.get_rotation_quaternion())
			if ledge_shape:
				_apply_ledge_fingers(skeleton, side, hand_weights[index])
				var middle := skeleton.find_bone("mixamorig_" + side + "HandMiddle1")
				var palm := skeleton.get_bone_rest(middle).basis.z.normalized()
				reach_diagnostics[index]["palm_down_dot"] = (skeleton.global_basis * hand_pose.basis * palm).normalized().dot(Vector3.DOWN)
		var solved := skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin
		reach_diagnostics[index]["elbow_world"] = skeleton.to_global(skeleton.get_bone_global_pose(lower).origin)
		errors_m.append(solved.distance_to(targets[index]))
	_capture_exit_pose(skeleton)

func _ledge_hand_basis(skeleton: Skeleton3D, side: String) -> Basis:
	var middle := skeleton.find_bone("mixamorig_" + side + "HandMiddle1")
	var along := skeleton.get_bone_rest(middle).origin.normalized()
	# The dual-source fingers flex toward their local +Z palm side.
	var normal := skeleton.get_bone_rest(middle).basis.z.slide(along).normalized()
	var local_frame := Basis(along.cross(normal).normalized(), along, normal).orthonormalized()
	var forward: Vector3 = -Vector3(contact_presentation.surface_normal).slide(Vector3.UP).normalized()
	var world_frame := Basis(forward.cross(Vector3.DOWN), forward, Vector3.DOWN)
	return (skeleton.global_basis.orthonormalized().inverse() * world_frame * local_frame.inverse()).orthonormalized()

func _apply_ledge_fingers(skeleton: Skeleton3D, side: String, amount: float) -> void:
	var angles: Array = hand_shape_profile.get("finger_curl_degrees", [0.0, 8.0, 12.0])
	for finger in ["Index", "Middle", "Ring", "Pinky", "Thumb"]:
		for segment in range(1, 4):
			var bone := skeleton.find_bone("mixamorig_%sHand%s%d" % [side, finger, segment])
			if bone < 0: continue
			var degrees := float(hand_shape_profile.get("thumb_curl_degrees", 10.0)) if finger == "Thumb" else float(angles[segment - 1])
			var desired := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, deg_to_rad(degrees))
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(desired, amount))

func _align_terminal_support(skeleton: Skeleton3D, presentation: Dictionary) -> void:
	terminal_support_delta_m = 0.0
	if not bool(terminal_support_profile.get("enabled", false)) or str(presentation.get("slot", "")) not in ["pull_up", "pull_up_free", "low_mantle"]: return
	var amount := smoothstep(float(terminal_support_profile.get("start_phase", .8)), float(terminal_support_profile.get("full_phase", .96)), evaluated_phase)
	if amount <= 0.0 or not presentation.get("landing_point") is Vector3: return
	var current := INF
	var rest := INF
	for name in ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]:
		var bone := skeleton.find_bone("mixamorig_" + name)
		current = minf(current, skeleton.to_global(skeleton.get_bone_global_pose(bone).origin).y)
		rest = minf(rest, (skeleton.global_basis * skeleton.get_bone_global_rest(bone).origin).y)
	var maximum := float(terminal_support_profile.get("maximum_correction_m", .25))
	terminal_support_delta_m = clampf(Vector3(presentation.landing_point).y + rest - current, -maximum, maximum) * amount
	var hips := skeleton.find_bone("mixamorig_Hips")
	var pose := skeleton.get_bone_global_pose(hips)
	pose.origin += skeleton.global_basis.inverse() * Vector3.UP * terminal_support_delta_m
	skeleton.set_bone_global_pose(hips, pose)
	skeleton.force_update_bone_child_transform(hips)

func _elbow_bend(skeleton: Skeleton3D, axis: Vector3, authored: Vector3, index: int) -> Vector3:
	if not bool(elbow_profile.get("enabled", false)): return authored
	var normal: Vector3 = contact_presentation.get("surface_normal", Vector3.ZERO)
	normal = normal.slide(Vector3.UP).normalized()
	if normal.length_squared() < 0.5: return authored
	var side := normal.cross(Vector3.UP) * (1.0 if index == 0 else -1.0)
	var pole_world := side * float(elbow_profile.get("outward", 1.0)) + normal * float(elbow_profile.get("away_from_wall", 0.45)) - Vector3.UP * float(elbow_profile.get("down", 0.3))
	var pole := (skeleton.global_basis.inverse() * pole_world).slide(axis)
	if not pole.is_finite() or pole.length_squared() < 0.0000001: return authored
	var amount := clampf(float(elbow_profile.get("weight", 0.85)), 0.0, 1.0) * hand_weights[index]
	var bend := authored.normalized().lerp(pole.normalized(), amount)
	return bend if bend.length_squared() > 0.0000001 else pole

func _align_braced_pose_to_wall(skeleton: Skeleton3D, presentation: Dictionary) -> void:
	if not bool(root_profile.get("face_wall", false)) or not is_instance_valid(body_node) or str(presentation.get("source", "")) != str(root_profile.get("source", "")): return
	var normal: Vector3 = presentation.surface_normal.slide(Vector3.UP).normalized()
	var yaw := atan2(normal.x, normal.z) - body_node.global_rotation.y
	var rotation := skeleton.global_basis.inverse() * Basis(Vector3.UP, yaw) * skeleton.global_basis
	var hips := skeleton.find_bone("mixamorig_Hips")
	if hips < 0: return
	# Read before modification: Godot restores source bone poses outside the
	# modifier evaluation, so post-frame reads cannot undo the rendered yaw.
	evaluated_source_hips_rotation = skeleton.get_bone_pose_rotation(hips)
	var pose := skeleton.get_bone_global_pose(hips)
	pose.basis = rotation * pose.basis
	pose.origin = rotation * pose.origin
	skeleton.set_bone_global_pose(hips, pose)
	skeleton.force_update_bone_child_transform(hips)

func _apply_wall_clearance(skeleton: Skeleton3D, presentation: Dictionary) -> void:
	wall_clearance_delta = Vector3.ZERO
	evaluated_wall_points.clear()
	var settings: Dictionary = root_profile.get("wall_clearance", {})
	if not bool(settings.get("enabled", false)) or str(presentation.get("source", "")) != str(root_profile.get("source", "")): return
	var anchor: Vector3 = presentation.anchor
	var normal: Vector3 = presentation.surface_normal.slide(Vector3.UP).normalized()
	var required := 0.0
	var bones: Array[int] = []
	for name in ["LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]:
		var index := skeleton.find_bone("mixamorig_" + name)
		if index < 0: continue
		bones.append(index)
		var point := skeleton.to_global(skeleton.get_bone_global_pose(index).origin)
		# Release continuously as each foot clears the top. A hard below/above
		# switch would snap the visual hips when the last foot crosses the lip.
		var clearance_weight := 1.0 - smoothstep(anchor.y - float(settings.get("top_margin_m", 0.04)), anchor.y + float(settings.get("release_above_top_m", 0.25)), point.y)
		required = maxf(required, (float(settings.get("outset_m", 0.06)) - (point-anchor).dot(normal)) * clearance_weight)
	wall_clearance_delta = normal * minf(required, float(settings.get("maximum_offset_m", 0.5)))
	var hips := skeleton.find_bone("mixamorig_Hips")
	if hips >= 0 and wall_clearance_delta.length_squared() > 0.000001:
		var pose := skeleton.get_bone_global_pose(hips)
		pose.origin += skeleton.global_basis.inverse() * wall_clearance_delta
		skeleton.set_bone_global_pose(hips, pose)
		skeleton.force_update_bone_child_transform(hips)
	for index in bones:
		var point := skeleton.to_global(skeleton.get_bone_global_pose(index).origin)
		evaluated_wall_points.append({"bone":skeleton.get_bone_name(index), "point":point, "outside_m":(point-anchor).dot(normal), "below_top":point.y < anchor.y-float(settings.get("top_margin_m", 0.04))})

func _rotate(skeleton: Skeleton3D, bone: int, before: Vector3, after: Vector3) -> void:
	if before.length_squared() < 0.0000001 or after.length_squared() < 0.0000001: return
	var pose := skeleton.get_bone_global_pose(bone)
	pose.basis = Basis(Quaternion(before.normalized(), after.normalized())) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)
	skeleton.force_update_bone_child_transform(bone)
