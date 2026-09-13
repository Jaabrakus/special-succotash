class_name SocomOperatorWeaponGripContact
extends RefCounted

## Final presentation-only hand contact pass.
##
## Weapon sockets own palm location. The arm IK owns wrist/elbow placement.
## This component only curls the operator's existing finger bones around those
## contacts after animation and IK have finished for the frame.

const FINGER_SEGMENT_WEIGHTS := [0.45, 0.35, 0.20]
const FINGER_NAMES := ["Index", "Middle", "Ring", "Pinky"]
const SupportWrist := preload("res://scripts/player/operator_support_wrist.gd")

var skeleton: Skeleton3D
var weapon: Node3D
var applied_right: bool = false
var applied_left: bool = false
var applied_bone_count: int = 0
var source_rifle_grip: bool = false
var source_pistol_grip: bool = false
var _desired_global_poses: Dictionary = {}
var _source_pistol_owned_bones: Array[int] = []


func bind(target_skeleton: Skeleton3D, attached_weapon: Node3D) -> void:
	_release_source_pistol_overrides()
	skeleton = target_skeleton
	weapon = attached_weapon
	applied_right = false
	applied_left = false
	applied_bone_count = 0
	source_pistol_grip = false
	_desired_global_poses.clear()


func rebind_weapon(attached_weapon: Node3D) -> void:
	_release_source_pistol_overrides()
	weapon = attached_weapon


func apply(
	weapon_owner: StringName,
	support_hand_mode: StringName,
	weapon_visible: bool
) -> void:
	_release_source_pistol_overrides()
	source_pistol_grip = false
	applied_right = false
	applied_left = false
	applied_bone_count = 0
	_desired_global_poses.clear()
	if skeleton == null or weapon == null or not weapon_visible:
		return
	if weapon_owner == &"GRENADE_ACTION":
		return
	var raw_pose: Variant = weapon.get_meta("support_hand_pose", {})
	var pose: Dictionary = raw_pose if raw_pose is Dictionary else {}
	var curl := clampf(float(pose.get("finger_curl", 0.72)), 0.0, 1.0)
	var thumb := clampf(float(pose.get("thumb_wrap", 0.64)), 0.0, 1.0)
	if not source_rifle_grip and curl <= 0.001 and thumb <= 0.001:
		curl = 0.72
		thumb = 0.64

	# The trigger palm remains attached for every rifle state except grenade.
	# Keep its index finger comparatively open while the other fingers retain
	# the pistol grip. This changes only the skinned fingers, never shot input.
	if source_rifle_grip:
		_apply_source_hand("Right", curl, thumb)
	else:
		_apply_hand("Right", curl, thumb, -1.0, 0.38)
	applied_right = true
	if support_hand_mode == &"IK_TO_WEAPON":
		if source_rifle_grip:
			var support: Dictionary = SupportWrist.profile
			var underhand: bool = bool(support.get("enabled", false)) and bool(support.get("palm_under_fore_end", false))
			_apply_source_hand("Left", clampf(float(support.get("finger_curl", curl)), 0.0, 1.0) if underhand else curl,
				clampf(float(support.get("thumb_wrap", thumb)), 0.0, 1.0) if underhand else thumb)
		else:
			_apply_hand("Left", curl, thumb, 1.0, 1.0)
		applied_left = true


func apply_source_pistol(weapon_visible: bool, close_support: bool) -> void:
	# Source clips own arms and wrists. Only missing target finger articulation
	# is supplied here; a nearby support hand is not automatically a held grip.
	_release_source_pistol_overrides()
	applied_right = false
	applied_left = false
	applied_bone_count = 0
	source_pistol_grip = false
	_desired_global_poses.clear()
	if not is_instance_valid(skeleton) or not is_instance_valid(weapon) or not weapon_visible:
		return
	var raw_pose: Variant = weapon.get_meta("support_hand_pose", {})
	var pose: Dictionary = raw_pose if raw_pose is Dictionary else {}
	var curl := clampf(float(pose.get("finger_curl", 0.72)), 0.0, 1.0)
	var thumb := clampf(float(pose.get("thumb_wrap", 0.64)), 0.0, 1.0)
	if not is_finite(curl) or curl <= 0.001:
		curl = 0.72
	if not is_finite(thumb) or thumb <= 0.001:
		thumb = 0.64
	_apply_source_hand("Right", curl, thumb)
	applied_right = true
	if close_support:
		_apply_source_hand("Left", curl, thumb)
		applied_left = true
	for bone: int in _desired_global_poses:
		_source_pistol_owned_bones.append(bone)
	source_pistol_grip = true


func _release_source_pistol_overrides() -> void:
	if is_instance_valid(skeleton):
		for bone: int in _source_pistol_owned_bones:
			if bone < skeleton.get_bone_count():
				skeleton.set_bone_global_pose_override(bone, Transform3D.IDENTITY, 0.0, false)
	_source_pistol_owned_bones.clear()


func snapshot() -> Dictionary:
	return {
		"right_grip_applied": applied_right,
		"left_grip_applied": applied_left,
		"bone_count": applied_bone_count,
		"source_rifle_grip": source_rifle_grip,
		"source_pistol_grip": source_pistol_grip,
	}


func _apply_source_hand(side: String, curl: float, thumb: float) -> void:
	# Dual-source rig preserves its native finger rests: BOTH hands flex toward
	# palm +Z around local +X. Mirroring the right sign opens its fingers.
	# Define the held shape from rest so animation samples cannot add another
	# fist on top of it; keep the existing saved Gunsmith curl/wrap controls.
	for finger in FINGER_NAMES:
		var angles := Vector3(55.0, 75.0, 45.0)
		if side == "Right" and finger == "Index":
			angles = Vector3(12.0, 30.0, 20.0)
		for segment in range(1, 4):
			var index := skeleton.find_bone("mixamorig_%sHand%s%d" % [side, finger, segment])
			if index >= 0:
				_apply_bone_delta(index, Quaternion(Vector3.RIGHT, deg_to_rad(angles[segment - 1] * curl)), true)
	# Oppose the thumb toward the middle finger rather than spreading it away.
	var opposition := 1.0 if side == "Right" else -1.0
	for segment in range(1, 4):
		var index := skeleton.find_bone("mixamorig_%sHandThumb%d" % [side, segment])
		if index < 0:
			continue
		var rotation := Quaternion(Vector3.RIGHT, deg_to_rad(25.0 * thumb))
		if segment == 1:
			rotation = Quaternion(Vector3.BACK, deg_to_rad(30.0 * thumb * opposition)) * rotation
		_apply_bone_delta(index, rotation, true)


func _apply_hand(
	side: String,
	curl: float,
	thumb_wrap: float,
	direction: float,
	index_scale: float
) -> void:
	for finger_name in FINGER_NAMES:
		var finger_scale := index_scale if finger_name == "Index" else 1.0
		for segment in range(1, 4):
			var bone_index := skeleton.find_bone(
				"mixamorig_%sHand%s%d" % [side, finger_name, segment]
			)
			if bone_index < 0:
				continue
			var bend := (
				deg_to_rad(curl * 80.0)
				* float(FINGER_SEGMENT_WEIGHTS[segment - 1])
				* finger_scale
				* direction
			)
			_apply_bone_delta(bone_index, Quaternion(Vector3.RIGHT, bend))

	var thumb_angle := deg_to_rad(thumb_wrap * 65.0) * direction
	for segment in range(1, 4):
		var thumb_index := skeleton.find_bone(
			"mixamorig_%sHandThumb%d" % [side, segment]
		)
		if thumb_index < 0:
			continue
		var wrap := Quaternion(Vector3.FORWARD, thumb_angle * 0.5)
		if segment == 1:
			wrap *= Quaternion(Vector3.UP, thumb_angle * 0.3)
		_apply_bone_delta(thumb_index, wrap)


func _apply_bone_delta(bone_index: int, delta: Quaternion, from_rest: bool = false) -> void:
	var local_pose := skeleton.get_bone_pose(bone_index)
	var local_scale := local_pose.basis.get_scale()
	var local_rotation := skeleton.get_bone_pose_rotation(bone_index)
	if from_rest:
		local_rotation = skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion()
	local_pose.basis = Basis((local_rotation * delta).normalized()).scaled(local_scale)
	var parent_index := skeleton.get_bone_parent(bone_index)
	var parent_global := Transform3D.IDENTITY
	if parent_index >= 0:
		parent_global = _desired_global_poses.get(
			parent_index,
			skeleton.get_bone_global_pose(parent_index)
		)
	var desired_global: Transform3D = parent_global * local_pose
	_desired_global_poses[bone_index] = desired_global
	# The weapon solver clears these overrides at the beginning of the next
	# animation frame. The curl therefore cannot feed back or accumulate.
	skeleton.set_bone_global_pose_override(bone_index, desired_global, 1.0, true)
	applied_bone_count += 1
