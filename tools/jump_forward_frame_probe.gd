extends "res://tools/jump_forward_legs_visual_probe.gd"

## Diagnostic translation in JUMP_FORWARD_LEGS_TRANSLATION.md. Evaluate source
## FK in arrays only; never write the live rig. Existing jump input/playhead.


func _jump_sample(label: String, height: float) -> void:
	await super._jump_sample(label, height)
	var skeleton: Skeleton3D = driver.get("skeleton")
	var graph = driver.get("locomotion_graph")
	var animation: Animation = driver.get("animation_player").get_animation(graph.jump_lower_body_clip)
	var time := float(graph.animation_tree.get("parameters/jump_lower_body_animation/current_position"))
	var live: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		live.append(skeleton.get_bone_global_pose(index))
	var source := _source_globals(skeleton, animation, time)
	var live_row := _frame_metrics(skeleton, live)
	var source_row := _frame_metrics(skeleton, source)
	var hips := skeleton.find_bone("mixamorig_Hips")
	var hips_error := rad_to_deg(live[hips].basis.orthonormalized().get_rotation_quaternion().normalized().angle_to(source[hips].basis.orthonormalized().get_rotation_quaternion().normalized()))
	var leg_error := 0.0
	for bone: StringName in graph.JUMP_LEG_BONES:
		var index := skeleton.find_bone(bone)
		leg_error = maxf(leg_error, rad_to_deg(live[index].basis.orthonormalized().get_rotation_quaternion().normalized().angle_to(source[index].basis.orthonormalized().get_rotation_quaternion().normalized())))
	samples.back()["jump_frame"] = {"source_time": time, "live": live_row, "source": source_row, "hips_rotation_difference_deg": hips_error, "maximum_leg_rotation_difference_deg": leg_error}
	# Takeoff/landing intentionally cross-fade. Compare the fully evaluated
	# airborne interval, not next-frame blend intent at either transition edge.
	if time >= 0.12 and time <= 0.45 and float(graph.jump_lower_body_weight) >= 0.99 and player.velocity.y != 0.0:
		if leg_error > 0.1:
			failures.append(label + " final thigh-to-toe rotations do not match forward source")
	print("JUMP_FORWARD_FRAME ", label, " ", JSON.stringify(samples.back().jump_frame))


func _source_globals(skeleton: Skeleton3D, animation: Animation, time: float) -> Array[Transform3D]:
	var local: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		local.append(skeleton.get_bone_rest(index))
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		var index := skeleton.find_bone(path.get_subname(path.get_subname_count() - 1))
		if index < 0:
			continue
		match animation.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				local[index].basis = Basis(animation.rotation_track_interpolate(track, time))
			Animation.TYPE_POSITION_3D:
				local[index].origin = animation.position_track_interpolate(track, time)
	var global: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(index)
		global.append(global[parent] * local[index] if parent >= 0 else local[index])
	return global


func _frame_metrics(skeleton: Skeleton3D, transforms: Array[Transform3D]) -> Dictionary:
	var hips := skeleton.find_bone("mixamorig_Hips")
	var left := skeleton.find_bone("mixamorig_LeftUpLeg")
	var right := skeleton.find_bone("mixamorig_RightUpLeg")
	var bar := transforms[right].origin - transforms[left].origin
	var row := {"hip_bar_heading_deg": _heading(bar), "hip_rotation": str(transforms[hips].basis.get_euler())}
	for side: String in ["Left", "Right"]:
		var thigh := skeleton.find_bone("mixamorig_%sUpLeg" % side)
		var knee := skeleton.find_bone("mixamorig_%sLeg" % side)
		var foot := skeleton.find_bone("mixamorig_%sFoot" % side)
		var toe := skeleton.find_bone("mixamorig_%sToeBase" % side)
		row[side.to_lower() + "_knee_heading_deg"] = _heading(transforms[knee].origin - transforms[thigh].origin)
		row[side.to_lower() + "_toe_heading_deg"] = _heading(transforms[toe].origin - transforms[foot].origin)
	return row


func _heading(direction: Vector3) -> float:
	return rad_to_deg(atan2(direction.x, direction.z))
