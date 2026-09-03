extends SceneTree

const PROOF_GLB := (
	"res://assets/characters/operator_rig_v2/operator_rig_v2_sprint_forward_left.glb"
)
const EXPECTED_BONES := 69
const EXPECTED_MESHES := 14
const ACTION_NAME := "SprintForwardLeft"
const REPORT_PATH := (
	"res://assets/characters/operator_rig_v2/"
	+ "operator_rig_v2_sprint_forward_left_report.json"
)
const MIN_KNEE_SEPARATION_M := 0.10
const MIN_ANKLE_SEPARATION_M := 0.08

const LEFT := {
	"arm": "mixamorig:LeftArm_033",
	"elbow": "mixamorig:LeftForeArm_034",
	"wrist": "mixamorig:LeftHand_035",
	"knee": "mixamorig:LeftLeg_064",
	"ankle": "mixamorig:LeftFoot_065",
}
const RIGHT := {
	"arm": "mixamorig:RightArm_09",
	"elbow": "mixamorig:RightForeArm_010",
	"wrist": "mixamorig:RightHand_011",
	"knee": "mixamorig:RightLeg_058",
	"ankle": "mixamorig:RightFoot_059",
}

var failures: Array[String] = []


func _init() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(ProjectSettings.globalize_path(PROOF_GLB), state)
	_expect(error == OK, "Godot parses the isolated Operator Rig V2 GLB")
	if error != OK:
		_finish()
		return
	var instance := document.generate_scene(state)
	_expect(instance != null, "Godot generates the Operator Rig V2 scene")
	if instance == null:
		_finish()
		return
	root.add_child(instance)
	var skeleton := _find_first(instance, "Skeleton3D") as Skeleton3D
	var player := _find_first(instance, "AnimationPlayer") as AnimationPlayer
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(instance, meshes)
	_expect(skeleton != null, "Operator Rig V2 contains a Skeleton3D")
	_expect(player != null, "Operator Rig V2 contains an AnimationPlayer")
	_expect(meshes.size() == EXPECTED_MESHES, "all 14 authored suit sections survive export")
	if skeleton == null or player == null:
		_finish()
		return
	_expect(skeleton.get_bone_count() == EXPECTED_BONES, "native 69-bone deformation rig survives export")
	for mesh in meshes:
		_expect(mesh.skin != null, "%s retains authored skin weights" % mesh.name)
	var action := _resolve_action(player.get_animation_list(), ACTION_NAME)
	_expect(not action.is_empty(), "sprint-forward-left is baked into the proof GLB")
	if not action.is_empty():
		_verify_cycle(player, skeleton, action)
	_verify_blender_report()
	_finish()


func _verify_cycle(player: AnimationPlayer, skeleton: Skeleton3D, action: String) -> void:
	var animation := player.get_animation(action)
	_expect(animation != null and animation.length > 0.1, "diagonal sprint has a playable cycle")
	if animation == null:
		return
	var indices := {}
	for side_name in ["left", "right"]:
		var side: Dictionary = LEFT if side_name == "left" else RIGHT
		indices[side_name] = {}
		for joint in side:
			(indices[side_name] as Dictionary)[joint] = _find_compatible_bone(
				skeleton,
				String(side[joint])
			)
	var all_found := true
	for side_name in indices:
		for joint in (indices[side_name] as Dictionary):
			all_found = all_found and int((indices[side_name] as Dictionary)[joint]) >= 0
	_expect(all_found, "V2 resolves both arm and leg joint chains")
	if not all_found:
		return
	_expect(animation.get_track_count() >= 53, "Godot retains the optimized full-body track set")
	for side in [LEFT, RIGHT]:
		for joint in side:
			_expect(
				_track_has_motion(animation, String(side[joint])),
				"Godot imports changing %s motion" % String(side[joint])
			)


func _verify_blender_report() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REPORT_PATH))
	_expect(parsed is Dictionary, "V2 includes its Blender deformation report")
	if not parsed is Dictionary:
		return
	var report := parsed as Dictionary
	var audit: Dictionary = report.get("audit", {})
	_expect(report.get("status", "") == "pass", "Blender V2 audit passed")
	var knee := float(audit.get("minimum_knee_planar_separation_m", 0.0))
	var ankle := float(audit.get("minimum_ankle_planar_separation_m", 0.0))
	var left_elbow: Array = audit.get("left_elbow_angle_range_deg", [])
	var right_elbow: Array = audit.get("right_elbow_angle_range_deg", [])
	print(
		"OPERATOR_RIG_V2_METRIC knee_min=%.4f ankle_min=%.4f " % [knee, ankle],
		"left_elbow=%s right_elbow=%s" % [left_elbow, right_elbow]
	)
	_expect(knee >= MIN_KNEE_SEPARATION_M, "diagonal sprint keeps the knees uncrossed")
	_expect(ankle >= MIN_ANKLE_SEPARATION_M, "diagonal sprint keeps the ankles uncrossed")
	_expect(
		left_elbow.size() == 2
		and float(left_elbow[0]) >= 45.0
		and float(left_elbow[1]) <= 145.0,
		"left elbow stays inside a human sprint range"
	)
	_expect(
		right_elbow.size() == 2
		and float(right_elbow[0]) >= 45.0
		and float(right_elbow[1]) <= 145.0,
		"right elbow stays inside a human sprint range"
	)


func _track_has_motion(animation: Animation, bone_name: String) -> bool:
	var compatible := bone_name.replace(":", "_")
	for track_index in animation.get_track_count():
		var path := String(animation.track_get_path(track_index))
		if not bone_name in path and not compatible in path:
			continue
		var key_count := animation.track_get_key_count(track_index)
		if key_count < 2:
			continue
		var first: Variant = animation.track_get_key_value(track_index, 0)
		for key_index in range(1, key_count):
			if _animation_values_differ(first, animation.track_get_key_value(track_index, key_index)):
				return true
	return false


func _animation_values_differ(first: Variant, other: Variant) -> bool:
	if first is Quaternion and other is Quaternion:
		return (first as Quaternion).angle_to(other as Quaternion) > deg_to_rad(0.5)
	if first is Vector3 and other is Vector3:
		return (first as Vector3).distance_to(other as Vector3) > 0.001
	return first != other


func _bone_origin(skeleton: Skeleton3D, bone_index: int) -> Vector3:
	return skeleton.get_bone_global_pose(bone_index).origin


func _planar_distance(left: Vector3, right: Vector3) -> float:
	return Vector2(left.x, left.z).distance_to(Vector2(right.x, right.z))


func _elbow_angle(skeleton: Skeleton3D, indices: Dictionary) -> float:
	var arm := _bone_origin(skeleton, int(indices["arm"]))
	var elbow := _bone_origin(skeleton, int(indices["elbow"]))
	var wrist := _bone_origin(skeleton, int(indices["wrist"]))
	return rad_to_deg((arm - elbow).angle_to(wrist - elbow))


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


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, output)


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
		print("OPERATOR_RIG_V2_CHECK PASS ", message)
	else:
		failures.append(message)
		push_error("OPERATOR_RIG_V2_CHECK FAIL " + message)


func _finish() -> void:
	if failures.is_empty():
		print("OPERATOR_RIG_V2_PROOF_REGRESSION PASS")
		quit(0)
	else:
		print("OPERATOR_RIG_V2_PROOF_REGRESSION FAIL ", failures)
		quit(1)
