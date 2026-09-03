extends SceneTree

const DEFAULT_LIBRARY_PATH := "res://assets/characters/military_tactical_suit/military_tactical_suit_animation_library.glb"
const OPERATOR_MAP_PATH := "res://config/operator_animation_map.json"
const EXPECTED_BONES := 69
const MIN_TRACKS_PER_ACTION := 53
const CRITICAL_BONE_CORES := [
	"Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "LeftFoot",
	"RightUpLeg", "RightLeg", "RightFoot",
]

var failures: Array[String] = []


func _init() -> void:
	var expected_actions := _expected_actions()
	_expect(expected_actions.size() > 0, "operator animation map supplies expected actions")
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var library_path := OS.get_environment("SUIT_LIBRARY_GLB_PATH")
	if library_path.is_empty():
		library_path = ProjectSettings.globalize_path(DEFAULT_LIBRARY_PATH)
	var error := document.append_from_file(library_path, state)
	_expect(error == OK, "Godot parses the tactical-suit animation library GLB")
	if error != OK:
		_finish()
		return
	var instance := document.generate_scene(state)
	_expect(instance != null, "Godot generates the tactical-suit animation library scene")
	if instance == null:
		_finish()
		return
	root.add_child(instance)
	var skeleton := _find_first(instance, "Skeleton3D") as Skeleton3D
	var player := _find_first(instance, "AnimationPlayer") as AnimationPlayer
	_expect(skeleton != null, "animation library contains a Skeleton3D")
	_expect(player != null, "animation library contains an AnimationPlayer")
	if skeleton != null:
		_expect(skeleton.get_bone_count() == EXPECTED_BONES, "animation library keeps 69 bones")
	if player != null:
		var available := player.get_animation_list()
		_expect(available.size() == expected_actions.size(), "animation library action count matches the operator map")
		for action_name in expected_actions:
			_expect(action_name in available, "%s exists in the Godot animation library" % action_name)
			if action_name in available:
				_verify_action(player.get_animation(action_name), action_name)
	_finish()


func _expected_actions() -> PackedStringArray:
	var file := FileAccess.open(OPERATOR_MAP_PATH, FileAccess.READ)
	if file == null:
		return PackedStringArray()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return PackedStringArray()
	var clips: Dictionary = (parsed as Dictionary).get("clips", {})
	var names := PackedStringArray()
	for action_name in clips.keys():
		names.append(String(action_name))
	names.sort()
	return names


func _verify_action(animation: Animation, action_name: String) -> void:
	_expect(animation != null and animation.length > 0.1, "%s has a non-zero cycle" % action_name)
	if animation == null:
		return
	var track_paths: Array[String] = []
	for track_index in animation.get_track_count():
		track_paths.append(String(animation.track_get_path(track_index)))
	var missing_critical: Array[String] = []
	for bone_core in CRITICAL_BONE_CORES:
		if not track_paths.any(func(path: String) -> bool: return bone_core in path):
			missing_critical.append(bone_core)
	_expect(
		animation.get_track_count() >= MIN_TRACKS_PER_ACTION and missing_critical.is_empty(),
		"%s contains the optimized full-body track set (tracks=%d missing=%s)" % [
			action_name,
			animation.get_track_count(),
			missing_critical,
		]
	)
	var has_motion := false
	var values_are_finite := true
	for track_index in animation.get_track_count():
		var key_count := animation.track_get_key_count(track_index)
		if key_count == 0:
			continue
		var first_value: Variant = animation.track_get_key_value(track_index, 0)
		values_are_finite = values_are_finite and _value_is_finite(first_value)
		for key_index in range(1, key_count):
			var value: Variant = animation.track_get_key_value(track_index, key_index)
			values_are_finite = values_are_finite and _value_is_finite(value)
			if not has_motion and _values_differ(first_value, value):
				has_motion = true
	_expect(values_are_finite, "%s contains only finite animation keys" % action_name)
	_expect(has_motion, "%s contains changing pose keys" % action_name)


func _value_is_finite(value: Variant) -> bool:
	if value is Vector3:
		return (value as Vector3).is_finite()
	if value is Quaternion:
		return (value as Quaternion).is_finite()
	if value is float:
		return is_finite(value as float)
	return true


func _values_differ(first: Variant, other: Variant) -> bool:
	if first is Quaternion and other is Quaternion:
		return (first as Quaternion).angle_to(other as Quaternion) > deg_to_rad(0.25)
	if first is Vector3 and other is Vector3:
		return (first as Vector3).distance_to(other as Vector3) > 0.001
	return first != other


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
		print("MILITARY_TACTICAL_SUIT_ANIMATION_LIBRARY_GLB_REGRESSION_PASS")
		quit(0)
	else:
		print("MILITARY_TACTICAL_SUIT_ANIMATION_LIBRARY_GLB_REGRESSION_FAIL count=", failures.size())
		quit(1)
