class_name SocomAnimationStudioWeaponOwnershipPreview
extends RefCounted

## Editor-only keeper for the canonical Gunsmith right-hand mount. Animation
## Studio never detaches the rifle during playback, pause, or joint editing.

var hand_attachment: BoneAttachment3D
var weapon: Node3D
var skeleton: Skeleton3D
var hand_local_transform := Transform3D.IDENTITY
var has_hand_local_transform := false

const TWO_HAND_CARRY := preload(
	"res://scripts/player/operator_two_hand_weapon_carry.gd"
)
const WEAPON_CONTACT_SOLVER := preload(
	"res://scripts/player/operator_weapon_contact_solver.gd"
)

const LEFT_HAND_BONES := [
	"mixamorig_LeftHand", "mixamorig:LeftHand", "Hand.L.001", "Bip01 L Hand",
]
const RIGHT_HAND_BONES := [
	"mixamorig_RightHand", "mixamorig:RightHand", "Hand.R.001", "Bip01 R Hand",
]


func bind(
	next_skeleton: Skeleton3D,
	next_hand_attachment: BoneAttachment3D,
	next_weapon: Node3D
) -> void:
	skeleton = next_skeleton
	hand_attachment = next_hand_attachment
	weapon = next_weapon
	if (
		weapon != null
		and hand_attachment != null
		and weapon.get_parent() == hand_attachment
		and not has_hand_local_transform
	):
		hand_local_transform = weapon.transform
		has_hand_local_transform = true


func stabilize_two_hand_carry(
	trigger_socket: Marker3D,
	support_socket: Marker3D,
	barrel_base_socket: Marker3D,
	muzzle_socket: Marker3D,
	optic_socket: Marker3D,
	fallback_direction: Vector3 = Vector3.FORWARD
) -> Dictionary:
	if skeleton == null or hand_attachment == null or weapon == null:
		return {"applied": false}
	var left_hand_index := _find_bone(LEFT_HAND_BONES)
	var right_hand_index := _find_bone(RIGHT_HAND_BONES)
	if left_hand_index < 0 or right_hand_index < 0:
		return {"applied": false}
	var left_hand_world := WEAPON_CONTACT_SOLVER.palm_contact_world(
		skeleton,
		left_hand_index,
		WEAPON_CONTACT_SOLVER.calculate_palm_anchor(
			skeleton, &"left", left_hand_index
		)
	)
	var right_hand_world := WEAPON_CONTACT_SOLVER.palm_contact_world(
		skeleton,
		right_hand_index,
		WEAPON_CONTACT_SOLVER.calculate_palm_anchor(
			skeleton, &"right", right_hand_index
		)
	)
	return TWO_HAND_CARRY.place(
		weapon,
		trigger_socket,
		support_socket,
		barrel_base_socket,
		muzzle_socket,
		optic_socket,
		right_hand_world,
		left_hand_world,
		Vector3.UP,
		fallback_direction
	)


func _find_bone(candidates: Array) -> int:
	for candidate in candidates:
		var bone_index := skeleton.find_bone(String(candidate))
		if bone_index >= 0:
			return bone_index
	return -1


func restore_hand_mount() -> void:
	if weapon == null or hand_attachment == null:
		return
	if not is_instance_valid(weapon) or not is_instance_valid(hand_attachment):
		return
	if weapon.get_parent() != hand_attachment:
		weapon.reparent(hand_attachment, false)
	if has_hand_local_transform:
		weapon.transform = hand_local_transform


func reset() -> void:
	skeleton = null
	hand_attachment = null
	weapon = null
	hand_local_transform = Transform3D.IDENTITY
	has_hand_local_transform = false
