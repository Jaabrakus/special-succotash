@tool
class_name SocomOperatorWeaponHandAttachmentModifier
extends SkeletonModifier3D

## Post-animation weapon mount for the TargetPivot presentation graph.
##
## Animation and the right-arm modifiers pose the trigger hand first. This
## modifier then places the weapon trigger socket on that final hand pose and
## updates the support-hand target. The following TwoBoneIK3D therefore solves
## the left hand against the same weapon transform in the same frame.

# Exact weapon-in-right-hand basis from the purchased New IK scene's
# `RShoulderBoneAttachment3D2/WeaponHolder/Gun` node. The reference scene uses
# this local basis after the RightHand BoneAttachment3D; its RHikTarget is the
# inverse contact frame. Keeping this correction separate from the character
# rest basis lets the same contact graph drive the canonical Mixamo skeleton.
const REFERENCE_WEAPON_IN_RIGHT_HAND_BASIS := Basis(
	Vector3(-0.174087, 0.051405, 0.983388),
	Vector3(0.937065, 0.315582, 0.14939),
	Vector3(-0.30266, 0.947505, -0.103108)
)

var weapon_node: Node3D
var trigger_socket: Node3D
var support_socket: Node3D
var support_target: Node3D
var trigger_hand_bone := -1
var process_count := 0
var last_trigger_hand_world := Vector3.ZERO
var last_trigger_socket_world := Vector3.ZERO
var last_trigger_contact_error := INF
var aim_world_target := Vector3.ZERO
var aim_weight := 0.0


func bind(
	target_skeleton: Skeleton3D,
	attached_weapon: Node3D,
	_right_hand_target: Node3D,
	left_hand_target: Node3D
) -> void:
	weapon_node = attached_weapon
	# Keep the parameter in the shared bind signature because the editable
	# TargetPivot graph still owns the right-hand pose. The weapon itself follows
	# the resulting hand bone, exactly like the reference BoneAttachment3D.
	support_target = left_hand_target
	trigger_hand_bone = (
		target_skeleton.find_bone(&"mixamorig_RightHand")
		if target_skeleton != null else -1
	)
	_rebind_sockets()


func rebind_weapon(attached_weapon: Node3D) -> void:
	weapon_node = attached_weapon
	_rebind_sockets()


func set_aim_target(world_target: Vector3, weight: float) -> void:
	aim_world_target = world_target
	aim_weight = clampf(weight, 0.0, 1.0)


func _process_modification() -> void:
	process_count += 1
	var target_skeleton := get_skeleton()
	if (
		target_skeleton == null
		or weapon_node == null
		or trigger_socket == null
		or trigger_hand_bone < 0
	):
		return
	var trigger_hand_world := (
		target_skeleton.global_transform
		* target_skeleton.get_bone_global_pose(trigger_hand_bone)
	)
	last_trigger_hand_world = trigger_hand_world.origin
	# Socket transforms are authored in weapon-local metres. Remove the current
	# weapon transform so this remains valid after a Gunsmith socket edit.
	var trigger_from_weapon := (
		weapon_node.global_transform.affine_inverse()
		* trigger_socket.global_transform
	)
	var animated_weapon_basis := (
		trigger_hand_world.basis.orthonormalized()
		* REFERENCE_WEAPON_IN_RIGHT_HAND_BASIS
	).orthonormalized()
	var desired_weapon_basis := animated_weapon_basis
	var aim_direction := aim_world_target - trigger_hand_world.origin
	if aim_weight > 0.001 and aim_direction.length_squared() > 0.000001:
		var aimed_basis := _basis_with_positive_z_forward(aim_direction.normalized())
		desired_weapon_basis = Basis(
			animated_weapon_basis.get_rotation_quaternion().slerp(
				aimed_basis.get_rotation_quaternion(),
				aim_weight
			).normalized()
		).orthonormalized()
	# Place the authored M4 trigger socket on the palm while retaining the New IK
	# gun-in-hand orientation. This is the runtime equivalent of the purchased
	# RightHand BoneAttachment3D plus its Gun child transform.
	weapon_node.global_transform = Transform3D(
		desired_weapon_basis,
		trigger_hand_world.origin - desired_weapon_basis * trigger_from_weapon.origin
	)
	last_trigger_socket_world = trigger_socket.global_position
	last_trigger_contact_error = last_trigger_socket_world.distance_to(
		trigger_hand_world.origin
	)
	if support_socket != null and support_target != null:
		support_target.global_transform = support_socket.global_transform


func _basis_with_positive_z_forward(forward: Vector3) -> Basis:
	var up_reference := Vector3.UP
	if absf(forward.dot(up_reference)) > 0.98:
		up_reference = Vector3.FORWARD
	var right := up_reference.cross(forward).normalized()
	var up := forward.cross(right).normalized()
	return Basis(right, up, forward).orthonormalized()


func _rebind_sockets() -> void:
	trigger_socket = _find_node(weapon_node, "Socket_RightHand") as Node3D
	support_socket = _find_node(weapon_node, "Socket_LeftHand") as Node3D


func _find_node(node: Node, wanted_name: String) -> Node:
	if node == null:
		return null
	if node.name == wanted_name:
		return node
	for child in node.get_children():
		var found := _find_node(child, wanted_name)
		if found != null:
			return found
	return null
