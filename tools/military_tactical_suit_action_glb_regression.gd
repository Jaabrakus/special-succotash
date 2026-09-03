extends SceneTree

const SUIT_SCENE := "res://assets/characters/military_tactical_suit/military_tactical_suit_run_sprint.glb"
const EXPECTED_ACTIONS := ["RunForward", "SprintForward"]

var failures: Array[String] = []


func _init() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(ProjectSettings.globalize_path(SUIT_SCENE), state)
	_expect(error == OK, "Godot parses the animated tactical-suit GLB")
	if error != OK:
		_finish()
		return
	var instance := document.generate_scene(state)
	_expect(instance != null, "Godot generates a scene from the animated tactical-suit GLB")
	if instance == null:
		_finish()
		return
	root.add_child(instance)
	var skeleton := _find_first(instance, "Skeleton3D") as Skeleton3D
	var player := _find_first(instance, "AnimationPlayer") as AnimationPlayer
	_expect(skeleton != null, "animated tactical suit contains a Skeleton3D")
	_expect(player != null, "animated tactical suit contains an AnimationPlayer")
	if skeleton != null:
		_expect(skeleton.get_bone_count() == 69, "clean tactical-suit rig keeps 69 bones")
	if player != null and skeleton != null:
		var available := player.get_animation_list()
		for expected in EXPECTED_ACTIONS:
			var resolved := _resolve_action(available, expected)
			_expect(not resolved.is_empty(), "%s is present in the imported animation library" % expected)
			if not resolved.is_empty():
				_verify_motion(player, skeleton, resolved)
	_finish()


func _verify_motion(player: AnimationPlayer, skeleton: Skeleton3D, action_name: String) -> void:
	var animation := player.get_animation(action_name)
	_expect(animation != null and animation.length > 0.1, "%s has a non-zero cycle" % action_name)
	if animation == null:
		return
	var hips := _find_compatible_bone(skeleton, "mixamorig:Hips_01")
	var right_foot := _find_compatible_bone(skeleton, "mixamorig:RightFoot_059")
	_expect(hips >= 0 and right_foot >= 0, "%s resolves hips and right foot" % action_name)
	if hips < 0 or right_foot < 0:
		return
	var right_foot_moves := false
	for track_index in animation.get_track_count():
		if not "RightFoot" in String(animation.track_get_path(track_index)):
			continue
		var key_count := animation.track_get_key_count(track_index)
		if key_count < 2:
			continue
		var first_value: Variant = animation.track_get_key_value(track_index, 0)
		for key_index in range(1, key_count):
			if _animation_values_differ(
				first_value,
				animation.track_get_key_value(track_index, key_index)
			):
				right_foot_moves = true
				break
		if right_foot_moves:
			break
	_expect(
		right_foot_moves,
		"%s moves the right foot across the cycle" % action_name
	)


func _animation_values_differ(first: Variant, other: Variant) -> bool:
	if first is Quaternion and other is Quaternion:
		return (first as Quaternion).angle_to(other as Quaternion) > deg_to_rad(3.0)
	if first is Vector3 and other is Vector3:
		return (first as Vector3).distance_to(other as Vector3) > 0.02
	return first != other


func _find_compatible_bone(skeleton: Skeleton3D, expected: String) -> int:
	var index := skeleton.find_bone(expected)
	if index >= 0:
		return index
	return skeleton.find_bone(expected.replace(":", "_"))


func _resolve_action(available: PackedStringArray, expected: String) -> String:
	for candidate in available:
		var name := String(candidate)
		if name == expected or name.ends_with("/" + expected):
			return name
	return ""


func _find_first(node: Node, class_name_value: String) -> Node:
	if node.is_class(class_name_value):
		return node
	for child in node.get_children():
		var found := _find_first(child, class_name_value)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)


func _finish() -> void:
	if failures.is_empty():
		print("MILITARY_TACTICAL_SUIT_ACTION_GLB_REGRESSION_PASS")
		quit(0)
	else:
		print("MILITARY_TACTICAL_SUIT_ACTION_GLB_REGRESSION_FAIL count=", failures.size())
		quit(1)
