class_name SocomOperatorCombatReadyCcdik
extends Node3D

## Post-animation combat-ready spine aim. Authored locomotion, arms, hands, and
## weapon attachment remain untouched until an accepted shot selects Ready Aim.

const ContactGraph := preload(
	"res://scripts/weapons/weapon_contact_graph_contract.gd"
)
const SPINE_BONES := [
	"mixamorig_Spine",
	"mixamorig_Spine1",
	"mixamorig_Spine2",
	"mixamorig_Neck",
	"mixamorig_Head",
]
const CONE_ANGLES := [0.9424778, 0.5026548, 0.5654867, 0.2513274]

var skeleton: Skeleton3D
var target_pivot: Marker3D
var spine_target: Marker3D
var spine_ccdik: CCDIK3D
var contact_profile: Dictionary = ContactGraph.default_profile()
var base_pivot_global := Transform3D.IDENTITY
var base_target_local := Transform3D.IDENTITY
var active_weight := 0.0


func bind(target_skeleton: Skeleton3D, raw_contact_profile: Variant) -> void:
	skeleton = target_skeleton
	contact_profile = ContactGraph.parse(raw_contact_profile)
	if skeleton == null:
		return
	var spine_index := skeleton.find_bone(SPINE_BONES.front())
	var head_index := skeleton.find_bone(SPINE_BONES.back())
	if spine_index < 0 or head_index < 0:
		push_error("Combat-ready CCDIK requires the canonical spine and head bones")
		return
	target_pivot = Marker3D.new()
	target_pivot.name = "CombatReadyTargetPivot"
	add_child(target_pivot)
	spine_target = Marker3D.new()
	spine_target.name = "SpineTargetWeaponAim"
	target_pivot.add_child(spine_target)
	var spine_world := skeleton.global_transform * skeleton.get_bone_global_pose(spine_index)
	var head_world := skeleton.global_transform * skeleton.get_bone_global_pose(head_index)
	target_pivot.global_transform = Transform3D(
		skeleton.global_basis.orthonormalized(),
		spine_world.origin
	)
	spine_target.global_transform = Transform3D(
		head_world.basis.orthonormalized(),
		head_world.origin
	)
	base_pivot_global = target_pivot.global_transform
	base_target_local = target_pivot.global_transform.affine_inverse() * spine_target.global_transform
	spine_ccdik = CCDIK3D.new()
	spine_ccdik.name = "CombatReadySpineCCDIK3D"
	skeleton.add_child(spine_ccdik)
	spine_ccdik.set("setting_count", 1)
	spine_ccdik.set("settings/0/target_node", spine_ccdik.get_path_to(spine_target))
	spine_ccdik.set("settings/0/root_bone_name", SPINE_BONES.front())
	spine_ccdik.set("settings/0/root_bone", spine_index)
	spine_ccdik.set("settings/0/end_bone_name", SPINE_BONES.back())
	spine_ccdik.set("settings/0/end_bone", head_index)
	spine_ccdik.set("settings/0/extend_end_bone", false)
	spine_ccdik.set("settings/0/joint_count", SPINE_BONES.size())
	for joint_index in range(CONE_ANGLES.size()):
		var limitation := JointLimitationCone3D.new()
		limitation.angle = CONE_ANGLES[joint_index]
		spine_ccdik.set(
			"settings/0/joints/%d/limitation" % joint_index,
			limitation
		)
	spine_ccdik.influence = 0.0


func apply(aim_yaw: float, aim_pitch: float, weight: float) -> void:
	active_weight = clampf(weight, 0.0, 1.0)
	if spine_ccdik == null or target_pivot == null or spine_target == null:
		return
	var aim_rotation := Basis.from_euler(
		Vector3(
			clampf(aim_pitch, deg_to_rad(-45.0), deg_to_rad(45.0)),
			clampf(aim_yaw, deg_to_rad(-70.0), deg_to_rad(70.0)),
			0.0
		),
		EULER_ORDER_YXZ
	)
	target_pivot.global_transform = Transform3D(
		(base_pivot_global.basis * aim_rotation).orthonormalized(),
		base_pivot_global.origin
	)
	spine_target.transform = ContactGraph.apply_offset(
		base_target_local,
		contact_profile,
		"spine_aim"
	)
	spine_ccdik.influence = active_weight


func reconfigure(raw_contact_profile: Variant) -> void:
	contact_profile = ContactGraph.parse(raw_contact_profile)


func get_debug_state() -> Dictionary:
	return {
		"owner": &"COMBAT_READY_TARGET_PIVOT_CCDIK",
		"active_weight": active_weight,
		"modifier_influence": spine_ccdik.influence if spine_ccdik != null else 0.0,
		"joint_count": SPINE_BONES.size(),
		"joint_limits_radians": CONE_ANGLES,
		"guns_lab_profile_enabled": bool(contact_profile.get("enabled", false)),
		"target_pivot_path": String(target_pivot.get_path()) if target_pivot != null else "",
	}
