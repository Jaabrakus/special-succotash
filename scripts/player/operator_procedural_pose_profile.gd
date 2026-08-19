class_name SocomOperatorProceduralPoseProfile
extends RefCounted

## Nondestructive, stance-aware corrections applied after a source animation is
## retargeted and before camera aim, weapon IK, recoil, and obstruction solving.

const PROFILE_PATH := "res://config/operator_procedural_pose_profile.json"
const SUPPORTED_POSTURES := [&"STANDING", &"CROUCHED", &"PRONE"]
const SUPPORTED_BONES := [
	&"spine", &"spine1", &"spine2", &"neck", &"head",
	&"left_shoulder", &"right_shoulder",
	&"left_upper_arm", &"right_upper_arm",
]

var corrections: Dictionary = {}


func _init() -> void:
	_reset_structure()


func load_project_profile() -> bool:
	_reset_structure()
	if not FileAccess.file_exists(PROFILE_PATH):
		return false
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	if not parsed is Dictionary:
		return false
	var document := parsed as Dictionary
	var posture_data: Variant = document.get("postures", {})
	if not posture_data is Dictionary:
		return false
	for posture: StringName in SUPPORTED_POSTURES:
		var source: Variant = (posture_data as Dictionary).get(String(posture), {})
		if not source is Dictionary:
			continue
		for bone: StringName in SUPPORTED_BONES:
			var rotation: Variant = (source as Dictionary).get(String(bone), {})
			if rotation is Dictionary:
				set_rotation_degrees(posture, bone, Vector3(
					float((rotation as Dictionary).get("pitch", 0.0)),
					float((rotation as Dictionary).get("yaw", 0.0)),
					float((rotation as Dictionary).get("roll", 0.0))
				))
	return true


func save_project_profile() -> bool:
	var postures: Dictionary = {}
	for posture: StringName in SUPPORTED_POSTURES:
		var bones: Dictionary = {}
		for bone: StringName in SUPPORTED_BONES:
			var rotation := get_rotation_degrees(posture, bone)
			bones[String(bone)] = {
				"pitch": rotation.x,
				"yaw": rotation.y,
				"roll": rotation.z,
			}
		postures[String(posture)] = bones
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"schema_version": 1,
		"space": "local_additive_degrees",
		"application_order": "after_animation_before_aim_and_weapon_ik",
		"postures": postures,
	}, "  "))
	file.close()
	return true


func get_rotation_degrees(posture: StringName, bone: StringName) -> Vector3:
	if not corrections.has(posture):
		return Vector3.ZERO
	return (corrections[posture] as Dictionary).get(bone, Vector3.ZERO)


func set_rotation_degrees(posture: StringName, bone: StringName, value: Vector3) -> void:
	if posture not in SUPPORTED_POSTURES or bone not in SUPPORTED_BONES:
		return
	var anatomical_limit := 48.0 if bone in [&"neck", &"head"] else 30.0
	if bone in [&"left_shoulder", &"right_shoulder"]:
		anatomical_limit = 22.0
	elif bone in [&"left_upper_arm", &"right_upper_arm"]:
		anatomical_limit = 38.0
	var safe := Vector3(
		clampf(value.x, -anatomical_limit, anatomical_limit),
		clampf(value.y, -anatomical_limit, anatomical_limit),
		clampf(value.z, -anatomical_limit, anatomical_limit)
	)
	(corrections[posture] as Dictionary)[bone] = safe


func _reset_structure() -> void:
	corrections.clear()
	for posture: StringName in SUPPORTED_POSTURES:
		var bones: Dictionary = {}
		for bone: StringName in SUPPORTED_BONES:
			bones[bone] = Vector3.ZERO
		corrections[posture] = bones
