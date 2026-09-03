extends SceneTree

const SUIT_SCENE := preload(
	"res://assets/characters/military_tactical_suit/military_tactical_suit_safe_scale.glb"
)
const RETARGET_SERVICE := preload(
	"res://scripts/labs/animation_retarget_service.gd"
)
const ROOT_SANITIZER := preload(
	"res://scripts/player/operator_animation_root_sanitizer.gd"
)
const EXPECTED_BONES := 65
const EXPECTED_MESHES := 14
const REPRESENTATIVE_CLIPS := {
	&"aim_idle": "res://assets/animations/mixamo/Shooter Pack/rifle aiming idle.fbx",
	&"run_forward": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/sprint forward.fbx",
	&"crouch_idle": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/idle crouching.fbx",
}
const REQUIRED_BONES := [
	"mixamorig_Hips",
	"mixamorig_Spine",
	"mixamorig_Spine1",
	"mixamorig_Spine2",
	"mixamorig_Neck",
	"mixamorig_Head",
	"mixamorig_LeftArm",
	"mixamorig_LeftForeArm",
	"mixamorig_LeftHand",
	"mixamorig_RightArm",
	"mixamorig_RightForeArm",
	"mixamorig_RightHand",
	"mixamorig_LeftUpLeg",
	"mixamorig_LeftLeg",
	"mixamorig_LeftFoot",
	"mixamorig_RightUpLeg",
	"mixamorig_RightLeg",
	"mixamorig_RightFoot",
]

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model := SUIT_SCENE.instantiate() as Node3D
	root.add_child(model)
	var skeleton := _find_skeleton(model)
	var meshes := _find_meshes(model)
	_expect(skeleton != null, "canonical suit imports a Skeleton3D")
	if skeleton == null:
		_finish()
		return
	_expect(skeleton.get_bone_count() == EXPECTED_BONES, "canonical suit contains exactly 65 bones")
	_expect(meshes.size() == EXPECTED_MESHES, "canonical suit retains all 14 production mesh sections")
	_expect(_transform_is_unit(model.transform), "imported suit root uses scale 1")
	_expect(_transform_is_unit(skeleton.transform), "imported armature uses scale 1")
	for bone_name in REQUIRED_BONES:
		_expect(skeleton.find_bone(bone_name) >= 0, "canonical bone exists: %s" % bone_name)
	for mesh in meshes:
		_expect(mesh.skin != null, "%s retains an authored skin" % mesh.name)
		_expect(not mesh.skeleton.is_empty(), "%s targets the canonical skeleton" % mesh.name)
	_expect(_rest_chain_lengths_are_human(skeleton), "rest arms and legs use human segment lengths")

	var player := AnimationPlayer.new()
	player.name = "CanonicalSuitRegressionPlayer"
	skeleton.add_child(player)
	player.root_node = player.get_path_to(skeleton)
	var library := AnimationLibrary.new()
	player.add_animation_library("canonical", library)
	for clip_name: StringName in REPRESENTATIVE_CLIPS:
		var loaded: bool = RETARGET_SERVICE.new().load_fbx(
			{"key": clip_name, "path": REPRESENTATIVE_CLIPS[clip_name]},
			library,
			player,
			skeleton,
			true,
			{},
			clip_name != &"aim_idle",
			ROOT_SANITIZER,
			false
		)
		_expect(loaded, "%s loads through the production retarget service" % clip_name)
		if not loaded:
			continue
		var animation := library.get_animation(clip_name)
		_expect(animation != null and animation.length > 0.1, "%s has a playable duration" % clip_name)
		if animation == null:
			continue
		player.play(StringName("canonical/%s" % clip_name))
		player.seek(animation.length * 0.5, true)
		player.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		_expect(_poses_are_finite(skeleton), "%s produces only finite bone transforms" % clip_name)
		_expect(_pose_extent(skeleton) < 3.0, "%s remains inside a human-sized volume" % clip_name)
		_expect(_chain_lengths_are_stable(skeleton), "%s keeps arms and legs connected" % clip_name)
	_finish()


func _transform_is_unit(value: Transform3D) -> bool:
	return (
		absf(value.basis.x.length() - 1.0) <= 0.0001
		and absf(value.basis.y.length() - 1.0) <= 0.0001
		and absf(value.basis.z.length() - 1.0) <= 0.0001
	)


func _rest_chain_lengths_are_human(skeleton: Skeleton3D) -> bool:
	for pair in [
		["mixamorig_LeftArm", "mixamorig_LeftForeArm"],
		["mixamorig_LeftForeArm", "mixamorig_LeftHand"],
		["mixamorig_RightArm", "mixamorig_RightForeArm"],
		["mixamorig_RightForeArm", "mixamorig_RightHand"],
		["mixamorig_LeftUpLeg", "mixamorig_LeftLeg"],
		["mixamorig_LeftLeg", "mixamorig_LeftFoot"],
		["mixamorig_RightUpLeg", "mixamorig_RightLeg"],
		["mixamorig_RightLeg", "mixamorig_RightFoot"],
	]:
		var first := skeleton.find_bone(pair[0])
		var second := skeleton.find_bone(pair[1])
		if first < 0 or second < 0:
			return false
		var length := (
			skeleton.get_bone_global_rest(first).origin
			- skeleton.get_bone_global_rest(second).origin
		).length()
		if length < 0.20 or length > 0.55:
			return false
	return true


func _poses_are_finite(skeleton: Skeleton3D) -> bool:
	for index in range(skeleton.get_bone_count()):
		if not skeleton.get_bone_global_pose(index).is_finite():
			return false
	return true


func _pose_extent(skeleton: Skeleton3D) -> float:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for index in range(skeleton.get_bone_count()):
		var point := skeleton.get_bone_global_pose(index).origin
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return (maximum - minimum).length()


func _chain_lengths_are_stable(skeleton: Skeleton3D) -> bool:
	for pair in [
		["mixamorig_LeftArm", "mixamorig_LeftForeArm"],
		["mixamorig_LeftForeArm", "mixamorig_LeftHand"],
		["mixamorig_RightArm", "mixamorig_RightForeArm"],
		["mixamorig_RightForeArm", "mixamorig_RightHand"],
		["mixamorig_LeftUpLeg", "mixamorig_LeftLeg"],
		["mixamorig_LeftLeg", "mixamorig_LeftFoot"],
		["mixamorig_RightUpLeg", "mixamorig_RightLeg"],
		["mixamorig_RightLeg", "mixamorig_RightFoot"],
	]:
		var first := skeleton.find_bone(pair[0])
		var second := skeleton.find_bone(pair[1])
		var rest_length := (
			skeleton.get_bone_global_rest(first).origin
			- skeleton.get_bone_global_rest(second).origin
		).length()
		var pose_length := (
			skeleton.get_bone_global_pose(first).origin
			- skeleton.get_bone_global_pose(second).origin
		).length()
		if absf(pose_length - rest_length) > 0.025:
			return false
	return true


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		result.append_array(_find_meshes(child))
	return result


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("CANONICAL_SUIT_CHECK PASS ", message)
	else:
		failures.append(message)
		push_error("CANONICAL_SUIT_CHECK FAIL %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("MILITARY_TACTICAL_SUIT_CANONICAL_SKIN_REGRESSION PASS")
		quit(0)
	else:
		print("MILITARY_TACTICAL_SUIT_CANONICAL_SKIN_REGRESSION FAIL ", failures)
		quit(1)
