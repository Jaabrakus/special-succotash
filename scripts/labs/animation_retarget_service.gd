class_name SocomAnimationRetargetService
extends RefCounted

## Converts authored clips and imported FBX takes for a live preview skeleton.
## Playback and UI state intentionally stay outside this service.


func load_authored(
	entry: Dictionary,
	dynamic_library: AnimationLibrary,
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
	root_sanitizer.sanitize(authored, should_loop)
	dynamic_library.add_animation(animation_key, authored)
	return true


func load_fbx(
	entry: Dictionary,
	dynamic_library: AnimationLibrary,
	target_player: AnimationPlayer,
	target_skeleton: Skeleton3D,
	use_ps1_bone_map: bool,
	ps1_bone_map: Dictionary,
	should_loop: bool,
	root_sanitizer: Variant
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

	var retargeted := source.duplicate() as Animation
	var skeleton_path := NodePath("GeneralSkeleton")
	if target_skeleton != null:
		var animation_root := target_player.get_node(target_player.root_node)
		skeleton_path = animation_root.get_path_to(target_skeleton)
	_retarget_tracks(retargeted, target_skeleton, skeleton_path, use_ps1_bone_map, ps1_bone_map)
	root_sanitizer.sanitize(retargeted, should_loop)
	dynamic_library.add_animation(animation_key, retargeted)
	temporary_instance.queue_free()
	return true


func _retarget_tracks(
	animation: Animation,
	skeleton: Skeleton3D,
	skeleton_path: NodePath,
	use_ps1_bone_map: bool,
	ps1_bone_map: Dictionary
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
			use_ps1_bone_map,
			ps1_bone_map
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
	use_ps1_bone_map: bool,
	ps1_bone_map: Dictionary
) -> String:
	if skeleton == null:
		return ""
	if use_ps1_bone_map and ps1_bone_map.has(normalized_mixamo):
		return str(ps1_bone_map[normalized_mixamo])
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
