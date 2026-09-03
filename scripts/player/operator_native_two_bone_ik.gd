class_name SocomOperatorNativeTwoBoneIK
extends RefCounted

## Godot 4.6+ arm modifier adapted from the local ik-demo-4.6 reference.
## The animation graph remains the base pose. TwoBoneIK3D owns only the upper
## arm/forearm position and CopyTransformModifier3D optionally owns wrist
## rotation after the solve.

var skeleton: Skeleton3D
var two_bone: TwoBoneIK3D
var hand_rotation: CopyTransformModifier3D
var internal_target: Marker3D
var internal_pole: Marker3D
var running := false

var interpolation := 1.0:
	set(value):
		interpolation = clampf(value, 0.0, 1.0)
		if two_bone != null:
			two_bone.influence = interpolation
		if hand_rotation != null:
			hand_rotation.influence = interpolation

var override_tip_basis := false:
	set(value):
		override_tip_basis = value
		if hand_rotation != null:
			hand_rotation.active = running and override_tip_basis

# Compatibility fields retained for older mobility callers. The native solver
# consumes explicit target and pole nodes instead of SkeletonIK3D's local data.
var use_magnet := true
var magnet := Vector3.ZERO
var target := Transform3D.IDENTITY


func bind(
	target_skeleton: Skeleton3D,
	node_name: String,
	root_bone_index: int,
	middle_bone_index: int,
	tip_bone_index: int
) -> void:
	skeleton = target_skeleton
	if skeleton == null:
		return
	# ProductionAnimation samples the graph and computes weapon targets at
	# process priority 100. Run the SkeletonModifier3D callback afterward so the
	# native two-bone pass consumes this frame's animation and target data.
	skeleton.process_priority = maxi(skeleton.process_priority, 200)
	internal_target = Marker3D.new()
	internal_target.name = "%sTarget" % node_name
	skeleton.add_child(internal_target)
	internal_pole = Marker3D.new()
	internal_pole.name = "%sPole" % node_name
	skeleton.add_child(internal_pole)

	two_bone = TwoBoneIK3D.new()
	two_bone.name = node_name
	two_bone.set_setting_count(1)
	two_bone.set_root_bone(0, root_bone_index)
	two_bone.set_root_bone_name(0, skeleton.get_bone_name(root_bone_index))
	two_bone.set_middle_bone(0, middle_bone_index)
	two_bone.set_middle_bone_name(0, skeleton.get_bone_name(middle_bone_index))
	two_bone.set_end_bone(0, tip_bone_index)
	two_bone.set_end_bone_name(0, skeleton.get_bone_name(tip_bone_index))
	two_bone.set_use_virtual_end(0, false)
	two_bone.set_extend_end_bone(0, false)
	# Configure every setting before the modifier enters the live tree. Godot's
	# native IK caches its chain and target during _ready(); assigning the paths
	# after add_child() leaves a runtime-created modifier visibly active but with
	# no resolved target, so the arm never moves.
	two_bone.set_target_node(0, NodePath("../%s" % internal_target.name))
	two_bone.set_pole_node(0, NodePath("../%s" % internal_pole.name))
	# Match the supplied Godot 4.6 project exactly. The modifier derives and may
	# update the working axes from the imported arm chain at runtime.
	two_bone.mutable_bone_axes = true
	two_bone.influence = interpolation
	two_bone.active = false
	skeleton.add_child(two_bone)

	hand_rotation = CopyTransformModifier3D.new()
	hand_rotation.name = "%sHandRotation" % node_name
	hand_rotation.set_setting_count(1)
	hand_rotation.set_amount(0, 1.0)
	hand_rotation.set_apply_bone(0, tip_bone_index)
	hand_rotation.set_apply_bone_name(0, skeleton.get_bone_name(tip_bone_index))
	hand_rotation.set_reference_type(0, BoneConstraint3D.REFERENCE_TYPE_NODE)
	hand_rotation.set_copy_flags(0, CopyTransformModifier3D.TRANSFORM_FLAG_ROTATION)
	hand_rotation.set_axis_flags(0, CopyTransformModifier3D.AXIS_FLAG_ALL)
	hand_rotation.set_additive(0, false)
	hand_rotation.set_reference_node(
		0,
		NodePath("../%s" % internal_target.name)
	)
	hand_rotation.influence = interpolation
	hand_rotation.active = false
	skeleton.add_child(hand_rotation)


func set_world_target(world_target: Transform3D, world_pole: Vector3) -> void:
	target = world_target
	if internal_target != null:
		internal_target.global_transform = world_target
	if internal_pole != null:
		internal_pole.global_position = world_pole


func start(_one_time := false) -> void:
	running = true
	if two_bone != null:
		two_bone.influence = interpolation
		two_bone.active = true
	if hand_rotation != null:
		hand_rotation.influence = interpolation
		hand_rotation.active = override_tip_basis


func stop() -> void:
	running = false
	if two_bone != null:
		two_bone.active = false
	if hand_rotation != null:
		hand_rotation.active = false


func is_running() -> bool:
	return running
