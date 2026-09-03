class_name SocomOperatorNativeRigAdapter
extends RefCounted

## Translates production Auto-Rig Pro deform names at the asset boundary.
## Gameplay and pose systems continue to consume the canonical operator names.

const ARP_TO_CANONICAL := {
	"root.x": "mixamorig_Hips",
	"spine_01.x": "mixamorig_Spine",
	"spine_02.x": "mixamorig_Spine1",
	"spine_03.x": "mixamorig_Spine2",
	"neck.x": "mixamorig_Neck",
	"head.x": "mixamorig_Head",
	"shoulder.l": "mixamorig_LeftShoulder",
	"arm_stretch.l": "mixamorig_LeftArm",
	"forearm_stretch.l": "mixamorig_LeftForeArm",
	"hand.l": "mixamorig_LeftHand",
	"thigh_stretch.l": "mixamorig_LeftUpLeg",
	"leg_stretch.l": "mixamorig_LeftLeg",
	"foot.l": "mixamorig_LeftFoot",
	"toes_01.l": "mixamorig_LeftToeBase",
	"shoulder.r": "mixamorig_RightShoulder",
	"arm_stretch.r": "mixamorig_RightArm",
	"forearm_stretch.r": "mixamorig_RightForeArm",
	"hand.r": "mixamorig_RightHand",
	"thigh_stretch.r": "mixamorig_RightUpLeg",
	"leg_stretch.r": "mixamorig_RightLeg",
	"foot.r": "mixamorig_RightFoot",
	"toes_01.r": "mixamorig_RightToeBase",
}

const AGLS_TO_CANONICAL := {
	"pelvis": "mixamorig_Hips",
	"spine_01": "mixamorig_Spine",
	"spine_02": "mixamorig_Spine1",
	"spine_03": "mixamorig_Spine2",
	"neck_01": "mixamorig_Neck",
	"head": "mixamorig_Head",
	"clavicle_l": "mixamorig_LeftShoulder",
	"upperarm_l": "mixamorig_LeftArm",
	"lowerarm_l": "mixamorig_LeftForeArm",
	"hand_l": "mixamorig_LeftHand",
	"thigh_l": "mixamorig_LeftUpLeg",
	"calf_l": "mixamorig_LeftLeg",
	"foot_l": "mixamorig_LeftFoot",
	"ball_l": "mixamorig_LeftToeBase",
	"clavicle_r": "mixamorig_RightShoulder",
	"upperarm_r": "mixamorig_RightArm",
	"lowerarm_r": "mixamorig_RightForeArm",
	"hand_r": "mixamorig_RightHand",
	"thigh_r": "mixamorig_RightUpLeg",
	"calf_r": "mixamorig_RightLeg",
	"foot_r": "mixamorig_RightFoot",
	"ball_r": "mixamorig_RightToeBase",
}

const GODOT_IK_TO_CANONICAL := {
	"Hips": "mixamorig_Hips",
	"Spine": "mixamorig_Spine",
	"Chest": "mixamorig_Spine1",
	"UpperChest": "mixamorig_Spine2",
	"Neck": "mixamorig_Neck",
	"Head": "mixamorig_Head",
	"LeftShoulder": "mixamorig_LeftShoulder",
	"LeftUpperArm": "mixamorig_LeftArm",
	"LeftLowerArm": "mixamorig_LeftForeArm",
	"LeftHand": "mixamorig_LeftHand",
	"RightShoulder": "mixamorig_RightShoulder",
	"RightUpperArm": "mixamorig_RightArm",
	"RightLowerArm": "mixamorig_RightForeArm",
	"RightHand": "mixamorig_RightHand",
	"LeftUpperLeg": "mixamorig_LeftUpLeg",
	"LeftLowerLeg": "mixamorig_LeftLeg",
	"LeftFoot": "mixamorig_LeftFoot",
	"LeftToes": "mixamorig_LeftToeBase",
	"RightUpperLeg": "mixamorig_RightUpLeg",
	"RightLowerLeg": "mixamorig_RightLeg",
	"RightFoot": "mixamorig_RightFoot",
	"RightToes": "mixamorig_RightToeBase",
}

const AGLS_FINGER_TO_CANONICAL := {
	"index": "Index", "middle": "Middle", "ring": "Ring",
	"pinky": "Pinky", "thumb": "Thumb",
}


static func is_native_arp_skeleton(skeleton: Skeleton3D) -> bool:
	return (
		skeleton != null
		and skeleton.find_bone("root.x") >= 0
		and skeleton.find_bone("hand.l") >= 0
		and skeleton.find_bone("hand.r") >= 0
	)


static func is_native_agls_skeleton(skeleton: Skeleton3D) -> bool:
	return (
		skeleton != null
		and skeleton.find_bone("pelvis") >= 0
		and skeleton.find_bone("hand_l") >= 0
		and skeleton.find_bone("hand_r") >= 0
		and skeleton.find_bone("ball_l") >= 0
		and skeleton.find_bone("ball_r") >= 0
	)


static func normalize_skeleton(skeleton: Skeleton3D, model_root: Node = null) -> bool:
	var mapping: Dictionary = {}
	if is_native_agls_skeleton(skeleton):
		mapping = _agls_mapping()
		skeleton.set_meta("socom_source_rig", "agls_native_69")
	elif is_native_arp_skeleton(skeleton):
		mapping = ARP_TO_CANONICAL
		skeleton.set_meta("socom_source_rig", "operator_autorigpro")
	else:
		return false
	if model_root != null:
		_remap_skin_bind_names(model_root, mapping)
	for source_name in mapping:
		var bone_index := skeleton.find_bone(source_name)
		if bone_index < 0:
			continue
		var target_name := String(mapping[source_name])
		if skeleton.find_bone(target_name) >= 0:
			push_error("Native operator rig contains duplicate canonical bone %s" % target_name)
			return false
		skeleton.set_bone_name(bone_index, target_name)
	return true


static func _remap_skin_bind_names(node: Node, mapping: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.skin != null:
			var remapped := mesh_instance.skin.duplicate() as Skin
			for bind_index in remapped.get_bind_count():
				var source_name := String(remapped.get_bind_name(bind_index))
				if mapping.has(source_name):
					remapped.set_bind_name(
						bind_index,
						StringName(mapping[source_name])
					)
			mesh_instance.skin = remapped
	for child in node.get_children():
		_remap_skin_bind_names(child, mapping)


static func canonical_bone_name(source_name: String) -> String:
	if GODOT_IK_TO_CANONICAL.has(source_name):
		return String(GODOT_IK_TO_CANONICAL[source_name])
	var agls := _agls_mapping()
	if agls.has(source_name):
		return String(agls[source_name])
	return String(ARP_TO_CANONICAL.get(source_name, source_name))


static func source_bone_candidates(canonical_name: String) -> PackedStringArray:
	var candidates := PackedStringArray([
		canonical_name,
		canonical_name.replace("mixamorig_", "mixamorig:"),
		canonical_name.replace("mixamorig:", "mixamorig_"),
	])
	for mapping in [GODOT_IK_TO_CANONICAL, ARP_TO_CANONICAL, _agls_mapping()]:
		for source_name in mapping:
			if String(mapping[source_name]) == canonical_name and source_name not in candidates:
				candidates.append(String(source_name))
	return candidates


static func _agls_mapping() -> Dictionary:
	var mapping := AGLS_TO_CANONICAL.duplicate()
	for side in ["l", "r"]:
		var canonical_side := "Left" if side == "l" else "Right"
		for source_finger in AGLS_FINGER_TO_CANONICAL:
			var canonical_finger := String(AGLS_FINGER_TO_CANONICAL[source_finger])
			for segment in range(1, 4):
				mapping["%s_%02d_%s" % [source_finger, segment, side]] = (
					"mixamorig_%sHand%s%d" % [canonical_side, canonical_finger, segment]
				)
	return mapping


static func adapt_animation(
	source: Animation,
	skeleton: Skeleton3D,
	skeleton_path: NodePath
) -> Animation:
	if source == null or skeleton == null:
		return null
	var adapted := source.duplicate() as Animation
	for track_index in range(adapted.get_track_count() - 1, -1, -1):
		var source_path := String(adapted.track_get_path(track_index))
		if ":" not in source_path:
			adapted.remove_track(track_index)
			continue
		var source_bone := source_path.rsplit(":", false, 1)[-1]
		var target_bone := canonical_bone_name(source_bone)
		if skeleton.find_bone(target_bone) < 0:
			adapted.remove_track(track_index)
			continue
		adapted.track_set_path(
			track_index,
			NodePath("%s:%s" % [String(skeleton_path), target_bone])
		)
	return adapted


static func adapt_animation_rest_aware(
	source: Animation,
	source_skeleton: Skeleton3D,
	target_skeleton: Skeleton3D,
	skeleton_path: NodePath,
	fps: float = 30.0
) -> Animation:
	# AGLS and Mixamo use different local bone bases. Renaming an AGLS arm track
	# onto a Mixamo bone preserves the keys but twists the rendered shoulder and
	# wrist. Transfer each sampled global rest delta instead, then express it in
	# the canonical target's local rest basis.
	var baked := Animation.new()
	if source == null:
		return baked
	baked.length = source.length
	baked.loop_mode = source.loop_mode
	baked.step = source.step
	if source_skeleton == null or target_skeleton == null:
		return baked

	var pairs := _rest_aware_bone_pairs(source_skeleton, target_skeleton)
	if pairs.is_empty():
		return baked
	var source_channels := _source_animation_channels(source, source_skeleton)
	var output_tracks := _create_rest_aware_tracks(baked, pairs, skeleton_path)
	var source_frame := _anatomical_rest_frame(source_skeleton)
	var target_frame := _anatomical_rest_frame(target_skeleton)
	var coordinate_change := target_frame * source_frame.inverse()
	var scale_ratio := _skeleton_height_ratio(source_skeleton, target_skeleton)
	var safe_fps := maxf(fps, 1.0)
	var frame_count := maxi(1, ceili(source.length * safe_fps))
	for frame_index in range(frame_count + 1):
		var sample_time := minf(float(frame_index) / safe_fps, source.length)
		var source_globals := _sample_source_global_transforms(
			source,
			source_skeleton,
			source_channels,
			sample_time
		)
		_insert_rest_aware_sample(
			baked,
			sample_time,
			source_skeleton,
			target_skeleton,
			pairs,
			output_tracks,
			coordinate_change,
			scale_ratio,
			source_globals
		)
	return baked


static func _rest_aware_bone_pairs(
	source_skeleton: Skeleton3D,
	target_skeleton: Skeleton3D
) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	for target_index in target_skeleton.get_bone_count():
		var target_name := String(target_skeleton.get_bone_name(target_index))
		var source_index := _find_compatible_bone(source_skeleton, target_name)
		if source_index < 0:
			continue
		pairs.append({
			"source": source_index,
			"target": target_index,
			"source_name": String(source_skeleton.get_bone_name(source_index)),
			"target_name": target_name,
		})
	return pairs


static func _source_animation_channels(
	animation: Animation,
	source_skeleton: Skeleton3D
) -> Dictionary:
	var channels: Dictionary = {}
	for track_index in animation.get_track_count():
		var raw_bone := String(animation.track_get_path(track_index)).split(":")[-1]
		var bone_index := source_skeleton.find_bone(raw_bone)
		if bone_index < 0:
			continue
		if not channels.has(bone_index):
			channels[bone_index] = {}
		var channel: Dictionary = channels[bone_index]
		match animation.track_get_type(track_index):
			Animation.TYPE_POSITION_3D:
				channel["position"] = track_index
			Animation.TYPE_ROTATION_3D:
				channel["rotation"] = track_index
			Animation.TYPE_SCALE_3D:
				channel["scale"] = track_index
	return channels


static func _create_rest_aware_tracks(
	animation: Animation,
	pairs: Array[Dictionary],
	skeleton_path: NodePath
) -> Dictionary:
	var tracks: Dictionary = {}
	for pair in pairs:
		var target_index := int(pair["target"])
		var target_name := String(pair["target_name"])
		var rotation_track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(
			rotation_track,
			NodePath("%s:%s" % [String(skeleton_path), target_name])
		)
		animation.track_set_interpolation_type(
			rotation_track,
			Animation.INTERPOLATION_LINEAR
		)
		tracks[target_index] = {"rotation": rotation_track}
		if target_name == "mixamorig_Hips":
			var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
			animation.track_set_path(
				position_track,
				NodePath("%s:%s" % [String(skeleton_path), target_name])
			)
			animation.track_set_interpolation_type(
				position_track,
				Animation.INTERPOLATION_LINEAR
			)
			(tracks[target_index] as Dictionary)["position"] = position_track
	return tracks


static func _sample_source_global_transforms(
	animation: Animation,
	source_skeleton: Skeleton3D,
	channels: Dictionary,
	time: float
) -> Dictionary:
	var globals: Dictionary = {}
	for bone_index in source_skeleton.get_bone_count():
		var local_transform := source_skeleton.get_bone_rest(bone_index)
		var channel: Dictionary = channels.get(bone_index, {})
		if channel.has("position"):
			local_transform.origin = animation.position_track_interpolate(
				int(channel["position"]),
				time
			)
		if channel.has("rotation"):
			local_transform.basis = Basis(animation.rotation_track_interpolate(
				int(channel["rotation"]),
				time
			))
		if channel.has("scale"):
			local_transform.basis = local_transform.basis.scaled(
				animation.scale_track_interpolate(int(channel["scale"]), time)
			)
		var parent_index := source_skeleton.get_bone_parent(bone_index)
		globals[bone_index] = (
			(globals[parent_index] as Transform3D) * local_transform
			if parent_index >= 0 and globals.has(parent_index)
			else local_transform
		)
	return globals


static func _insert_rest_aware_sample(
	animation: Animation,
	time: float,
	source_skeleton: Skeleton3D,
	target_skeleton: Skeleton3D,
	pairs: Array[Dictionary],
	output_tracks: Dictionary,
	coordinate_change: Basis,
	scale_ratio: float,
	source_globals: Dictionary
) -> void:
	var mapped_target_globals: Dictionary = {}
	for pair in pairs:
		var source_index := int(pair["source"])
		var target_index := int(pair["target"])
		var target_name := String(pair["target_name"])
		var source_rest := source_skeleton.get_bone_global_rest(source_index)
		var source_pose: Transform3D = source_globals.get(source_index, source_rest)
		var target_rest := target_skeleton.get_bone_global_rest(target_index)
		var source_delta := source_pose.basis * source_rest.basis.inverse()
		var target_delta := (
			coordinate_change * source_delta * coordinate_change.inverse()
		).orthonormalized()
		var desired_basis := (target_delta * target_rest.basis).orthonormalized()
		var parent_index := target_skeleton.get_bone_parent(target_index)
		var parent_global := _animated_target_parent(
			target_skeleton,
			parent_index,
			mapped_target_globals
		)
		var rest_local := target_skeleton.get_bone_rest(target_index)
		var local_basis := (
			parent_global.basis.inverse() * desired_basis
		).orthonormalized()
		var local_position := rest_local.origin
		if target_name == "mixamorig_Hips":
			var source_motion := source_pose.origin - source_rest.origin
			var desired_origin := (
				target_rest.origin + coordinate_change * source_motion * scale_ratio
			)
			local_position = parent_global.affine_inverse() * desired_origin
		mapped_target_globals[target_index] = Transform3D(
			desired_basis,
			parent_global * local_position
		)
		var tracks: Dictionary = output_tracks[target_index]
		animation.rotation_track_insert_key(
			int(tracks["rotation"]),
			time,
			local_basis.get_rotation_quaternion().normalized()
		)
		if tracks.has("position"):
			animation.position_track_insert_key(
				int(tracks["position"]),
				time,
				local_position
			)


static func _animated_target_parent(
	target_skeleton: Skeleton3D,
	parent_index: int,
	mapped_target_globals: Dictionary
) -> Transform3D:
	if parent_index < 0:
		return Transform3D.IDENTITY
	if mapped_target_globals.has(parent_index):
		return mapped_target_globals[parent_index] as Transform3D
	var rest_chain: Array[Transform3D] = []
	var cursor := parent_index
	while cursor >= 0 and not mapped_target_globals.has(cursor):
		rest_chain.push_front(target_skeleton.get_bone_rest(cursor))
		cursor = target_skeleton.get_bone_parent(cursor)
	var result := (
		mapped_target_globals[cursor] as Transform3D
		if cursor >= 0 and mapped_target_globals.has(cursor)
		else Transform3D.IDENTITY
	)
	for local_rest in rest_chain:
		result *= local_rest
	return result


static func _anatomical_rest_frame(skeleton: Skeleton3D) -> Basis:
	var hips := _compatible_global_rest_origin(skeleton, "mixamorig_Hips")
	var head := _compatible_global_rest_origin(skeleton, "mixamorig_Head")
	var left_hand := _compatible_global_rest_origin(skeleton, "mixamorig_LeftHand")
	var right_hand := _compatible_global_rest_origin(skeleton, "mixamorig_RightHand")
	var right_axis := (right_hand - left_hand).normalized()
	var up_axis := (head - hips).normalized()
	if right_axis.length_squared() < 0.5:
		right_axis = Vector3.RIGHT
	if up_axis.length_squared() < 0.5:
		up_axis = Vector3.UP
	var forward_axis := right_axis.cross(up_axis).normalized()
	if forward_axis.length_squared() < 0.5:
		forward_axis = Vector3.FORWARD
	right_axis = up_axis.cross(forward_axis).normalized()
	return Basis(right_axis, up_axis, forward_axis).orthonormalized()


static func _skeleton_height_ratio(
	source_skeleton: Skeleton3D,
	target_skeleton: Skeleton3D
) -> float:
	var source_height := _compatible_global_rest_origin(
		source_skeleton,
		"mixamorig_Head"
	).distance_to(_compatible_global_rest_origin(source_skeleton, "mixamorig_Hips"))
	var target_height := _compatible_global_rest_origin(
		target_skeleton,
		"mixamorig_Head"
	).distance_to(_compatible_global_rest_origin(target_skeleton, "mixamorig_Hips"))
	return target_height / source_height if source_height > 0.000001 else 1.0


static func _compatible_global_rest_origin(
	skeleton: Skeleton3D,
	canonical_name: String
) -> Vector3:
	var bone_index := _find_compatible_bone(skeleton, canonical_name)
	return (
		skeleton.get_bone_global_rest(bone_index).origin
		if bone_index >= 0
		else Vector3.ZERO
	)


static func _find_compatible_bone(
	skeleton: Skeleton3D,
	canonical_name: String
) -> int:
	if skeleton == null:
		return -1
	for candidate in source_bone_candidates(canonical_name):
		var bone_index := skeleton.find_bone(candidate)
		if bone_index >= 0:
			return bone_index
	return -1
