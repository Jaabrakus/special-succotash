extends RefCounted

# Stateless inspection/preparation helpers for imported retarget previews.

static func _normalize_mixamo_names(skeleton: Skeleton3D) -> void:
	for index in range(skeleton.get_bone_count()):
		var name_string := String(skeleton.get_bone_name(index)).replace("mixamorig:", "mixamorig_")
		skeleton.set_bone_name(index, name_string)


static func _find_bone_by_suffix(skeleton: Skeleton3D, suffix: String) -> int:
	for index in range(skeleton.get_bone_count()):
		var normalized := String(skeleton.get_bone_name(index)).replace(":", "_")
		var suffix_start := normalized.rfind("_")
		if suffix_start >= 0 and normalized.substr(suffix_start + 1).is_valid_int():
			normalized = normalized.left(suffix_start)
		if normalized.ends_with(suffix):
			return index
	return -1


static func _canonical_bone_name(raw_name: String) -> String:
	var normalized := raw_name.replace(":", "_")
	var suffix_start := normalized.rfind("_")
	if suffix_start >= 0 and normalized.substr(suffix_start + 1).is_valid_int():
		normalized = normalized.left(suffix_start)
	return normalized


static func _disable_animation_players(node: Node) -> void:
	if node is AnimationPlayer:
		(node as AnimationPlayer).process_mode = Node.PROCESS_MODE_DISABLED
	for child in node.get_children():
		_disable_animation_players(child)


static func _set_named_visibility(node: Node, target_name: String, visible: bool) -> void:
	if node.name == target_name and node is Node3D:
		(node as Node3D).visible = visible
	for child in node.get_children():
		_set_named_visibility(child, target_name, visible)


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
