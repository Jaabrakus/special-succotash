class_name SocomOperatorGodotIkAimRuntime
extends Node3D

## Adapter for the built-in modifier graph demonstrated by
## `GODOT 4.6 - NEW IK AIM/Node/Player.tscn`.
## It deliberately owns presentation only: camera intent and shots remain SOCOM.

const WeaponContactGraph := preload(
	"res://scripts/weapons/weapon_contact_graph_contract.gd"
)
const WeaponHandAttachmentModifier := preload(
	"res://scripts/player/operator_weapon_hand_attachment_modifier.gd"
)
const TargetPivotArmAimModifier := preload(
	"res://scripts/player/operator_target_pivot_arm_aim_modifier.gd"
)
const HandContactObserver := preload(
	"res://scripts/player/operator_hand_contact_observer.gd"
)

var skeleton: Skeleton3D
var weapon_node: Node3D
var graph: Node3D
var pivot: Marker3D
var right_arm_target: Marker3D
var right_hand_target: Marker3D
var left_hand_target: Marker3D
var spine_target: Marker3D
var left_pole: Marker3D
var spine_ik: CCDIK3D
var left_hand_ik: TwoBoneIK3D
var right_arm_copy: CopyTransformModifier3D
var right_hand_copy: CopyTransformModifier3D
var left_hand_copy: CopyTransformModifier3D
var left_hand_contact_observer: SkeletonModifier3D
var target_pivot_arm_aim
var weapon_hand_attachment: SkeletonModifier3D
var support_socket: Node3D
var _primed := false
var authored_pivot_rotation := Vector3.ZERO
var authored_target_transforms: Dictionary = {}
var weapon_contact_graph_profile: Dictionary = WeaponContactGraph.default_profile()
var animation_drives_ready_hands := false
var procedural_ready_hand_weight := 1.0
var procedural_ready_spine_weight := 1.0


func bind(target_skeleton: Skeleton3D, attached_weapon: Node3D, control_graph: Node3D) -> void:
	skeleton = target_skeleton
	weapon_node = attached_weapon
	graph = control_graph
	if skeleton == null or graph == null:
		return
	pivot = graph.get_node_or_null("TargetPivot") as Marker3D
	right_arm_target = graph.get_node_or_null("TargetPivot/RHUpperArmWeaponTarget") as Marker3D
	right_hand_target = graph.get_node_or_null("TargetPivot/RHWeaponTarget") as Marker3D
	left_hand_target = graph.get_node_or_null("TargetPivot/LHWeaponContactTarget") as Marker3D
	spine_target = graph.get_node_or_null("TargetPivot/SpineTargetWeaponAim") as Marker3D
	left_pole = graph.get_node_or_null("LHPoleAnchor/LHPoleTarget") as Marker3D
	support_socket = _find_node(weapon_node, "Socket_LeftHand") as Node3D
	if not _controls_complete():
		push_error("Godot IK aim graph is missing required controls")
		return
	authored_pivot_rotation = pivot.rotation
	authored_target_transforms = {
		"right_shoulder": right_arm_target.transform,
		"trigger_hand": right_hand_target.transform,
		"spine_aim": spine_target.transform,
	}
	_install_reference_modifiers()
	_set_modifier_influence(0.0)
	_primed = true


func apply(
	world_aim_target: Vector3,
	ready_weight: float,
	_posture: StringName,
	aim_yaw: float,
	aim_pitch: float
) -> void:
	if not _primed or skeleton == null:
		return
	var weight := clampf(ready_weight, 0.0, 1.0)
	_apply_authored_target_offsets()
	# Match the purchased project: keep every target near the authored body pose
	# and rotate one shared pivot. Never send the spine target to the distant hit ray.
	pivot.rotation = authored_pivot_rotation + Vector3(
		aim_pitch + deg_to_rad(2.45),
		clampf(aim_yaw, -PI * 0.5, PI * 0.5),
		0.0
	)
	if support_socket != null:
		left_hand_target.global_transform = WeaponContactGraph.apply_offset(
			support_socket.global_transform,
			weapon_contact_graph_profile,
			"support_hand"
		)
	if target_pivot_arm_aim != null:
		target_pivot_arm_aim.set_aim_target(world_aim_target)
	if weapon_hand_attachment != null:
		weapon_hand_attachment.set_aim_target(world_aim_target, weight)
	# Low-ready and locomotion remain authored animation. The reference modifiers
	# enter only for ready aim, after their targets have valid world transforms.
	# Authored ready/fire hands keep the baked arm motion as the dominant layer.
	# The fire-ready latch may add one bounded procedural contact correction. The
	# same weight is zero during ordinary locomotion and authored reload.
	var modifier_weight := weight
	if animation_drives_ready_hands:
		modifier_weight *= procedural_ready_hand_weight
	_set_modifier_influence(modifier_weight)
	if animation_drives_ready_hands and spine_ik != null:
		# Constrained spine CCD aims the authored upper-body pose as one unit. It
		# does not replace the animation rotations on either arm or hand.
		spine_ik.influence = weight * procedural_ready_spine_weight


func configure_weapon_contact_graph(raw_profile: Variant) -> void:
	weapon_contact_graph_profile = WeaponContactGraph.parse(raw_profile)


func configure_dynamic_hold(raw_profile: Variant) -> void:
	if not raw_profile is Dictionary:
		animation_drives_ready_hands = false
		procedural_ready_hand_weight = 1.0
		procedural_ready_spine_weight = 1.0
		return
	var profile := raw_profile as Dictionary
	animation_drives_ready_hands = bool(
		profile.get("animation_drives_ready_hands", false)
	)
	procedural_ready_hand_weight = clampf(
		float(profile.get("procedural_ready_hand_weight", 0.35)),
		0.0,
		0.5
	)
	procedural_ready_spine_weight = clampf(
		float(profile.get("procedural_ready_spine_weight", 1.0)),
		0.0,
		1.0
	)


func rebind_weapon(attached_weapon: Node3D) -> void:
	weapon_node = attached_weapon
	support_socket = _find_node(weapon_node, "Socket_LeftHand") as Node3D
	if weapon_hand_attachment != null:
		weapon_hand_attachment.rebind_weapon(weapon_node)


func get_debug_state() -> Dictionary:
	var attachment_state := {
		"process_count": 0,
		"trigger_contact_error_m": INF,
	}
	if weapon_hand_attachment != null:
		attachment_state = {
			"process_count": int(weapon_hand_attachment.get("process_count")),
			"trigger_contact_error_m": float(
				weapon_hand_attachment.get("last_trigger_contact_error")
			),
			"trigger_hand_world": weapon_hand_attachment.get("last_trigger_hand_world"),
			"trigger_socket_world": weapon_hand_attachment.get("last_trigger_socket_world"),
		}
	var support_state := {
		"process_count": 0,
		"contact_error_m": INF,
	}
	if left_hand_contact_observer != null:
		support_state = {
			"process_count": int(left_hand_contact_observer.get("process_count")),
			"contact_error_m": float(
				left_hand_contact_observer.get("last_contact_error_m")
			),
			"hand_world": left_hand_contact_observer.get("last_hand_world"),
			"target_world": left_hand_contact_observer.get("last_target_world"),
		}
	return {
		"owner": &"PLAYER_TARGET_PIVOT_GRIP",
		"primed": _primed,
		"weapon_realized": weapon_node != null and is_instance_valid(weapon_node),
		"weapon_name": String(weapon_node.name) if weapon_node != null else "",
		"weapon_path": String(weapon_node.get_path()) if weapon_node != null else "",
		"weapon_visible": weapon_node.visible if weapon_node != null else false,
		"has_trigger_socket": _find_node(weapon_node, "Socket_RightHand") != null,
		"has_support_socket": support_socket != null,
		"has_muzzle_socket": _find_node(weapon_node, "Socket_Muzzle") != null,
		"pivot_rotation": pivot.rotation if pivot != null else Vector3.ZERO,
		"connected_arm_influence": (
			target_pivot_arm_aim.influence if target_pivot_arm_aim != null else 0.0
		),
		"connected_arm_aim_dot": (
			float(target_pivot_arm_aim.get("last_aim_dot"))
			if target_pivot_arm_aim != null else -1.0
		),
		"support_ik_influence": left_hand_ik.influence if left_hand_ik != null else 0.0,
		"spine_ik_influence": spine_ik.influence if spine_ik != null else 0.0,
		"weapon_attachment_influence": (
			weapon_hand_attachment.influence if weapon_hand_attachment != null else 0.0
		),
		"animation_drives_ready_hands": animation_drives_ready_hands,
		"procedural_ready_hand_weight": procedural_ready_hand_weight,
		"procedural_ready_spine_weight": procedural_ready_spine_weight,
		"weapon_attachment": attachment_state,
		"support_contact": support_state,
	}


func _apply_authored_target_offsets() -> void:
	for entry in [
		["right_shoulder", right_arm_target],
		["trigger_hand", right_hand_target],
		["spine_aim", spine_target],
	]:
		var target_id: String = entry[0]
		var target := entry[1] as Marker3D
		var base: Transform3D = authored_target_transforms.get(
			target_id,
			target.transform
		)
		target.transform = WeaponContactGraph.apply_offset(
			base,
			weapon_contact_graph_profile,
			target_id
		)


func _install_reference_modifiers() -> void:
	spine_ik = skeleton.get_node_or_null("SpineCCDIK3D") as CCDIK3D
	if spine_ik == null:
		spine_ik = CCDIK3D.new()
		spine_ik.name = "SpineCCDIK3D"
		skeleton.add_child(spine_ik)
	spine_ik.set("setting_count", 1)
	spine_ik.set("settings/0/target_node", spine_ik.get_path_to(spine_target))
	spine_ik.set("settings/0/root_bone_name", "mixamorig_Spine")
	spine_ik.set("settings/0/root_bone", skeleton.find_bone("mixamorig_Spine"))
	spine_ik.set("settings/0/end_bone_name", "mixamorig_Head")
	spine_ik.set("settings/0/end_bone", skeleton.find_bone("mixamorig_Head"))
	spine_ik.set("settings/0/extend_end_bone", false)
	spine_ik.set("settings/0/joint_count", 5)
	# The purchased New IK graph limits each CCD spine joint. Preserve its exact
	# cone angles instead of allowing an unconstrained chain to fold or oscillate.
	for joint_index in range(4):
		var property_path := "settings/0/joints/%d/limitation" % joint_index
		if spine_ik.get(property_path) == null:
			var limitation := JointLimitationCone3D.new()
			limitation.angle = [0.9424778, 0.5026548, 0.5654867, 0.2513274][joint_index]
			spine_ik.set(property_path, limitation)

	right_arm_copy = _copy_rotation_modifier(
		"WeaponCopyTransformModifier3D",
		&"mixamorig_RightArm",
		right_arm_target
	)
	right_hand_copy = _copy_rotation_modifier(
		"WeaponCopyTransformModifier3D2",
		&"mixamorig_RightHand",
		 right_hand_target
	)
	target_pivot_arm_aim = skeleton.get_node_or_null("TargetPivotArmAimModifier")
	if target_pivot_arm_aim == null:
		target_pivot_arm_aim = TargetPivotArmAimModifier.new()
		target_pivot_arm_aim.name = "TargetPivotArmAimModifier"
		skeleton.add_child(target_pivot_arm_aim)
	target_pivot_arm_aim.bind(
		skeleton,
		pivot,
		right_arm_target,
		right_hand_target
	)
	weapon_hand_attachment = skeleton.get_node_or_null(
		"WeaponHandAttachmentModifier"
	) as SkeletonModifier3D
	if weapon_hand_attachment == null:
		weapon_hand_attachment = WeaponHandAttachmentModifier.new()
		weapon_hand_attachment.name = "WeaponHandAttachmentModifier"
		skeleton.add_child(weapon_hand_attachment)
	weapon_hand_attachment.bind(
		skeleton,
		weapon_node,
		right_hand_target,
		left_hand_target
	)
	# The trigger hand always owns the held weapon, including locomotion and
	# reload. Ready weight controls body IK only; it must never disable the mount.
	weapon_hand_attachment.influence = 1.0

	left_hand_ik = skeleton.get_node_or_null("LHTwoBoneIK3D") as TwoBoneIK3D
	if left_hand_ik == null:
		left_hand_ik = TwoBoneIK3D.new()
		left_hand_ik.name = "LHTwoBoneIK3D"
		skeleton.add_child(left_hand_ik)
	left_hand_ik.set("setting_count", 1)
	left_hand_ik.set("settings/0/target_node", left_hand_ik.get_path_to(left_hand_target))
	left_hand_ik.set("settings/0/pole_node", left_hand_ik.get_path_to(left_pole))
	left_hand_ik.set("settings/0/root_bone_name", "mixamorig_LeftArm")
	left_hand_ik.set("settings/0/root_bone", skeleton.find_bone("mixamorig_LeftArm"))
	left_hand_ik.set("settings/0/middle_bone_name", "mixamorig_LeftForeArm")
	left_hand_ik.set("settings/0/middle_bone", skeleton.find_bone("mixamorig_LeftForeArm"))
	left_hand_ik.set("settings/0/end_bone_name", "mixamorig_LeftHand")
	left_hand_ik.set("settings/0/end_bone", skeleton.find_bone("mixamorig_LeftHand"))
	# Match the purchased graph. The real LeftHand bone is the contact endpoint;
	# a fabricated virtual endpoint changes the palm solution on this skeleton.
	left_hand_ik.set("settings/0/use_virtual_end", false)
	left_hand_ik.set("settings/0/extend_end_bone", false)
	# The reference graph follows TwoBoneIK3D with a full hand contact copy. The
	# IK aims the chain's end, while this final pass places and rotates the palm
	# origin on the support socket without changing the authoritative body.
	left_hand_copy = skeleton.get_node_or_null(
		"LHCopyTransformModifier3D2"
	) as CopyTransformModifier3D
	if left_hand_copy == null:
		left_hand_copy = _copy_transform_modifier(
			"LHCopyTransformModifier3D2",
			&"mixamorig_LeftHand",
			left_hand_target,
			3
		)
	left_hand_contact_observer = skeleton.get_node_or_null(
		"LeftHandContactObserver"
	) as SkeletonModifier3D
	if left_hand_contact_observer == null:
		left_hand_contact_observer = HandContactObserver.new()
		left_hand_contact_observer.name = "LeftHandContactObserver"
		skeleton.add_child(left_hand_contact_observer)
	left_hand_contact_observer.bind(
		skeleton,
		&"mixamorig_LeftHand",
		left_hand_target
	)
	# Godot evaluates SkeletonModifier3D children in scene-tree order. Keep the
	# dependency chain explicit: torso -> connected trigger arm/hand -> weapon
	# attachment -> support-arm IK -> final support-palm contact. Evaluating the
	# weapon before the trigger-hand modifier produces a one-frame/stale hand basis.
	skeleton.move_child(spine_ik, 0)
	skeleton.move_child(target_pivot_arm_aim, 1)
	skeleton.move_child(weapon_hand_attachment, 2)
	skeleton.move_child(left_hand_ik, 3)
	skeleton.move_child(left_hand_copy, 4)
	skeleton.move_child(left_hand_contact_observer, 5)


func _copy_rotation_modifier(
	node_name: String,
	bone_name: StringName,
	target: Node3D
) -> CopyTransformModifier3D:
	return _copy_transform_modifier(node_name, bone_name, target, 2)


func _copy_transform_modifier(
	node_name: String,
	bone_name: StringName,
	target: Node3D,
	copy_flags: int
) -> CopyTransformModifier3D:
	var modifier := CopyTransformModifier3D.new()
	modifier.name = node_name
	skeleton.add_child(modifier)
	modifier.set("setting_count", 1)
	modifier.set("settings/0/amount", 1.0)
	modifier.set("settings/0/apply_bone_name", String(bone_name))
	modifier.set("settings/0/apply_bone", skeleton.find_bone(bone_name))
	modifier.set("settings/0/reference_type", 1)
	modifier.set("settings/0/reference_node", modifier.get_path_to(target))
	modifier.set("settings/0/copy", copy_flags)
	modifier.set("settings/0/axes", 7)
	modifier.set("settings/0/invert", 0)
	modifier.set("settings/0/additive", false)
	return modifier


func _set_modifier_influence(weight: float) -> void:
	# The purchased right-arm targets are absolute rotations authored for its
	# GeneralSkeleton rest basis. The canonical Mixamo-rest operator already gets
	# its correct two-hand pose from the ready/fire AnimationTree layer, so those
	# two foreign rotations must not overwrite it. The weapon still follows that
	# animated trigger hand and the native left-hand chain follows its foregrip.
	for modifier in [
		spine_ik,
		target_pivot_arm_aim,
		left_hand_ik,
		left_hand_copy,
		left_hand_contact_observer,
	]:
		if modifier != null:
			modifier.influence = weight
	for incompatible_copy in [right_arm_copy, right_hand_copy]:
		if incompatible_copy != null:
			incompatible_copy.influence = 0.0


func _controls_complete() -> bool:
	return (
		pivot != null
		and right_arm_target != null
		and right_hand_target != null
		and left_hand_target != null
		and spine_target != null
		and left_pole != null
	)


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
