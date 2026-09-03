class_name SocomAnimationRetargetService
extends RefCounted

## Converts authored clips and imported FBX takes for a live preview skeleton.
## Playback and UI state intentionally stay outside this service.

const NATIVE_RIG_ADAPTER := preload(
	"res://scripts/player/operator_native_rig_adapter.gd"
)


func bake_rest_aware_animation(
	source: Animation,
	source_skeleton: Skeleton3D,
	target_skeleton: Skeleton3D,
	skeleton_path: NodePath,
	target_bone_map: Dictionary,
	fps: float = 30.0
) -> Animation:
	return _bake_rest_aware_animation(
		source,
		source_skeleton,
		target_skeleton,
		skeleton_path,
		target_bone_map,
		fps
	)


func load_authored(
	entry: Dictionary,
	dynamic_library: AnimationLibrary,
	target_player: AnimationPlayer,
	target_skeleton: Skeleton3D,
	use_bone_map: bool,
	target_bone_map: Dictionary,
	should_loop: bool,
	root_sanitizer: Variant
) -> bool:
	var animation_key := StringName(entry.get("key", ""))
	if animation_key == &"":
		return false
	if dynamic_library.has_animation(animation_key):
		return true
	var source := load(str(entry.get("path", ""))) as Animation
	if source == null:
		return false
	var authored := source.duplicate(true) as Animation
	var skeleton_path := NodePath("GeneralSkeleton")
	if target_player != null and target_skeleton != null:
		var animation_root := target_player.get_node(target_player.root_node)
		skeleton_path = animation_root.get_path_to(target_skeleton)
	_retarget_tracks(
		authored,
		target_skeleton,
		skeleton_path,
		use_bone_map,
		target_bone_map
	)
	root_sanitizer.sanitize(authored, should_loop)
	dynamic_library.add_animation(animation_key, authored)
	return true


func load_fbx(
	entry: Dictionary,
	dynamic_library: AnimationLibrary,
	target_player: AnimationPlayer,
	target_skeleton: Skeleton3D,
	use_bone_map: bool,
	target_bone_map: Dictionary,
	should_loop: bool,
	root_sanitizer: Variant,
	rest_aware: bool = false
) -> bool:
	var animation_key := StringName(entry.get("key", ""))
	if animation_key == &"":
		return false
	if dynamic_library.has_animation(animation_key):
		return true
	var packed := load(str(entry.get("path", ""))) as PackedScene
	if packed == null:
		return false
	var temporary_instance := packed.instantiate()
	var source_player := _find_animation_player(temporary_instance)
	if source_player == null or source_player.get_animation_list().is_empty():
		temporary_instance.queue_free()
		return false
	var source_name := _select_source_animation_name(source_player)
	if source_name == &"":
		temporary_instance.queue_free()
		return false
	var source := source_player.get_animation(source_name)
	if source == null:
		temporary_instance.queue_free()
		return false

	var source_skeleton := _find_skeleton(temporary_instance)
	var skeleton_path := NodePath("GeneralSkeleton")
	if target_skeleton != null:
		var animation_root := target_player.get_node(target_player.root_node)
		skeleton_path = animation_root.get_path_to(target_skeleton)
	var retargeted := (
		_bake_rest_aware_animation(
			source,
			source_skeleton,
			target_skeleton,
			skeleton_path,
			target_bone_map
		)
		if rest_aware and use_bone_map and source_skeleton != null
		else source.duplicate() as Animation
	)
	if not rest_aware:
		_retarget_tracks(
			retargeted,
			target_skeleton,
			skeleton_path,
			use_bone_map,
			target_bone_map
		)
	var target_up_axis := Vector3.UP
	if rest_aware and use_bone_map and target_skeleton != null:
		target_up_axis = _anatomical_rest_frame(target_skeleton, {
			"hips": str(target_bone_map.get("mixamorig_Hips", "")),
			"head": str(target_bone_map.get("mixamorig_Head", "")),
			"left_hand": str(target_bone_map.get("mixamorig_LeftHand", "")),
			"right_hand": str(target_bone_map.get("mixamorig_RightHand", "")),
		}).y.normalized()
	root_sanitizer.sanitize(retargeted, should_loop, 1.0, target_up_axis)
	dynamic_library.add_animation(animation_key, retargeted)
	temporary_instance.queue_free()
	return true


func _retarget_tracks(
	animation: Animation,
	skeleton: Skeleton3D,
	skeleton_path: NodePath,
	use_bone_map: bool,
	target_bone_map: Dictionary
) -> void:
	var track_index := animation.get_track_count() - 1
	while track_index >= 0:
		var old_path := str(animation.track_get_path(track_index))
		var raw_bone := old_path.split(":")[-1]
		var normalized_mixamo := raw_bone.replace("mixamorig:", "mixamorig_")
		if not normalized_mixamo.begins_with("mixamorig_"):
			normalized_mixamo = "mixamorig_" + normalized_mixamo
		var target_bone := _resolve_target_bone(
			skeleton,
			raw_bone,
			normalized_mixamo,
			use_bone_map,
			target_bone_map
		)
		if target_bone.is_empty():
			animation.remove_track(track_index)
			track_index -= 1
			continue
		animation.track_set_path(track_index, NodePath(str(skeleton_path) + ":" + target_bone))
		if (
			("Hips" in raw_bone or "Spinelower" in target_bone or "root" in raw_bone.to_lower())
			and animation.track_get_type(track_index) == Animation.TYPE_POSITION_3D
		):
			_normalize_root_position_track(animation, track_index, skeleton, target_bone)
		track_index -= 1


func _resolve_target_bone(
	skeleton: Skeleton3D,
	raw_bone: String,
	normalized_mixamo: String,
	use_bone_map: bool,
	target_bone_map: Dictionary
) -> String:
	if skeleton == null:
		return ""
	if use_bone_map and target_bone_map.has(normalized_mixamo):
		return str(target_bone_map[normalized_mixamo])
	if skeleton.find_bone(raw_bone) != -1:
		return raw_bone
	if skeleton.find_bone(normalized_mixamo) != -1:
		return normalized_mixamo
	var colon_name := normalized_mixamo.replace("mixamorig_", "mixamorig:")
	if skeleton.find_bone(colon_name) != -1:
		return colon_name
	var lower_raw := raw_bone.to_lower().replace("mixamorig_", "").replace("mixamorig:", "")
	for bone_index in range(skeleton.get_bone_count()):
		var bone_name := skeleton.get_bone_name(bone_index)
		if bone_name.to_lower() == lower_raw or bone_name.to_lower().begins_with(lower_raw):
			return bone_name
	return ""


func _bake_rest_aware_animation(
	source: Animation,
	source_skeleton: Skeleton3D,
	target_skeleton: Skeleton3D,
	skeleton_path: NodePath,
	target_bone_map: Dictionary,
	fps: float = 30.0
) -> Animation:
	var baked := Animation.new()
	baked.length = source.length
	baked.loop_mode = source.loop_mode
	if source_skeleton == null or target_skeleton == null:
		return baked

	var source_channels := _source_channels(source, source_skeleton)
	var pairs := _mapped_bone_pairs(source_skeleton, target_skeleton, target_bone_map)
	if pairs.is_empty():
		return baked
	var source_frame := _anatomical_rest_frame(source_skeleton, {
		"hips": "mixamorig_Hips",
		"head": "mixamorig_Head",
		"left_hand": "mixamorig_LeftHand",
		"right_hand": "mixamorig_RightHand",
	})
	var target_frame := _anatomical_rest_frame(target_skeleton, {
		"hips": str(target_bone_map.get("mixamorig_Hips", "")),
		"head": str(target_bone_map.get("mixamorig_Head", "")),
		"left_hand": str(target_bone_map.get("mixamorig_LeftHand", "")),
		"right_hand": str(target_bone_map.get("mixamorig_RightHand", "")),
	})
	var coordinate_change := target_frame * source_frame.inverse()
	var scale_ratio := _mapped_height_ratio(
		source_skeleton,
		target_skeleton,
		target_bone_map
	)
	var output_tracks := _create_output_tracks(baked, pairs, skeleton_path)
	var frame_count := maxi(1, ceili(source.length * fps))
	for frame_index in range(frame_count + 1):
		var sample_time := minf(float(frame_index) / fps, source.length)
		var source_globals := _sample_source_global_transforms(
			source,
			source_skeleton,
			source_channels,
			sample_time
		)
		_bake_target_sample(
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


func _source_channels(animation: Animation, source_skeleton: Skeleton3D) -> Dictionary:
	var channels: Dictionary = {}
	for track_index in animation.get_track_count():
		var raw_bone := str(animation.track_get_path(track_index)).split(":")[-1]
		var bone_index := _find_source_bone(source_skeleton, raw_bone)
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


func _mapped_bone_pairs(
	source_skeleton: Skeleton3D,
	target_skeleton: Skeleton3D,
	target_bone_map: Dictionary
) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	for target_index in target_skeleton.get_bone_count():
		var target_name := String(target_skeleton.get_bone_name(target_index))
		var source_name := ""
		for mapped_source in target_bone_map.keys():
			if String(target_bone_map[mapped_source]) == target_name:
				source_name = String(mapped_source)
				break
		if source_name.is_empty():
			continue
		var source_index := _find_source_bone(source_skeleton, source_name)
		if source_index >= 0:
			pairs.append({
				"source": source_index,
				"target": target_index,
				"source_name": source_name,
				"target_name": target_name,
			})
	return pairs


func _create_output_tracks(
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
			NodePath(str(skeleton_path) + ":" + target_name)
		)
		animation.track_set_interpolation_type(rotation_track, Animation.INTERPOLATION_LINEAR)
		tracks[target_index] = {"rotation": rotation_track}
		if String(pair["source_name"]) == "mixamorig_Hips":
			var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
			animation.track_set_path(
				position_track,
				NodePath(str(skeleton_path) + ":" + target_name)
			)
			animation.track_set_interpolation_type(position_track, Animation.INTERPOLATION_LINEAR)
			(tracks[target_index] as Dictionary)["position"] = position_track
	return tracks


func _sample_source_global_transforms(
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
			local_transform.basis = Basis(
				animation.rotation_track_interpolate(int(channel["rotation"]), time)
			)
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


func _bake_target_sample(
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
		var source_rest := source_skeleton.get_bone_global_rest(source_index)
		var source_pose: Transform3D = source_globals.get(
			source_index,
			source_rest
		)
		var target_rest := target_skeleton.get_bone_global_rest(target_index)
		var source_delta := source_pose.basis * source_rest.basis.inverse()
		var target_delta := (
			coordinate_change
			* source_delta
			* coordinate_change.inverse()
		).orthonormalized()
		var desired_basis := (target_delta * target_rest.basis).orthonormalized()
		var parent_index := target_skeleton.get_bone_parent(target_index)
		var parent_global := _animated_parent_transform(
			target_skeleton,
			parent_index,
			mapped_target_globals
		)
		var rest_local := target_skeleton.get_bone_rest(target_index)
		var base_global := parent_global * rest_local
		# Skeleton animation tracks store the authored local bone transform, not
		# a delta from rest. Emit the target's local rest orientation plus the
		# transferred motion. Writing identity here collapses a Bip01 hierarchy.
		var local_basis := (
			parent_global.basis.inverse() * desired_basis
		).orthonormalized()
		var local_position := rest_local.origin
		if String(pair["source_name"]) == "mixamorig_Hips":
			var source_motion := source_pose.origin - source_rest.origin
			var desired_origin := (
				target_rest.origin
				+ coordinate_change * source_motion * scale_ratio
			)
			local_position = parent_global.affine_inverse() * desired_origin
		var final_global := Transform3D(
			desired_basis,
			parent_global * local_position
		)
		mapped_target_globals[target_index] = final_global
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


func _animated_parent_transform(
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


func _anatomical_rest_frame(skeleton: Skeleton3D, names: Dictionary) -> Basis:
	var hips := _global_rest_origin(skeleton, String(names.get("hips", "")))
	var head := _global_rest_origin(skeleton, String(names.get("head", "")))
	var left_hand := _global_rest_origin(skeleton, String(names.get("left_hand", "")))
	var right_hand := _global_rest_origin(skeleton, String(names.get("right_hand", "")))
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


func _mapped_height_ratio(
	source_skeleton: Skeleton3D,
	target_skeleton: Skeleton3D,
	target_bone_map: Dictionary
) -> float:
	var source_height := _global_rest_origin(
		source_skeleton,
		"mixamorig_Head"
	).distance_to(_global_rest_origin(source_skeleton, "mixamorig_Hips"))
	var target_height := _global_rest_origin(
		target_skeleton,
		String(target_bone_map.get("mixamorig_Head", ""))
	).distance_to(_global_rest_origin(
		target_skeleton,
		String(target_bone_map.get("mixamorig_Hips", ""))
	))
	return target_height / source_height if source_height > 0.000001 else 1.0


func _global_rest_origin(skeleton: Skeleton3D, normalized_bone: String) -> Vector3:
	var index := _find_source_bone(skeleton, normalized_bone)
	return skeleton.get_bone_global_rest(index).origin if index >= 0 else Vector3.ZERO


func _find_source_bone(skeleton: Skeleton3D, bone_name: String) -> int:
	if skeleton == null or bone_name.is_empty():
		return -1
	var candidates := NATIVE_RIG_ADAPTER.source_bone_candidates(bone_name)
	for candidate in candidates:
		var index := skeleton.find_bone(candidate)
		if index >= 0:
			return index
	return -1


func _normalize_root_position_track(
	animation: Animation,
	track_index: int,
	skeleton: Skeleton3D,
	target_bone: String
) -> void:
	var bone_index := skeleton.find_bone(target_bone) if skeleton != null else -1
	var rest_y := skeleton.get_bone_rest(bone_index).origin.y if bone_index != -1 else 0.92
	var base_y := 0.0
	if animation.track_get_key_count(track_index) > 0:
		base_y = (animation.track_get_key_value(track_index, 0) as Vector3).y
	var scale_factor := rest_y / base_y if not is_zero_approx(base_y) else 1.0
	for key_index in range(animation.track_get_key_count(track_index)):
		var position := animation.track_get_key_value(track_index, key_index) as Vector3
		position.x = 0.0
		position.z = 0.0
		position.y *= scale_factor
		animation.track_set_key_value(track_index, key_index, position)


func _select_source_animation_name(player: AnimationPlayer) -> StringName:
	var names := player.get_animation_list()
	if names.has(&"mixamo_com"):
		return &"mixamo_com"
	for animation_name in names:
		if animation_name != &"RESET":
			return animation_name
	return &""


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
