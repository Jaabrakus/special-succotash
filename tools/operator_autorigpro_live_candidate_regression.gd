extends SceneTree

const DEFAULT_CANDIDATE_GLB := (
	"res://assets/characters/operator_rig_v2/"
	+ "operator_autorigpro_gameplay_library_humanoid.glb"
)
const EXPECTED_ACTION_TOKEN := "native__run_forward_left"
const EXPECTED_MESH_COUNT := 14
const EXPECTED_ACTION_COUNT := 82

var _failures: Array[String] = []


func _init() -> void:
	var candidate_glb := OS.get_environment("OPERATOR_ARP_CANDIDATE")
	if candidate_glb.is_empty():
		candidate_glb = DEFAULT_CANDIDATE_GLB
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(ProjectSettings.globalize_path(candidate_glb), state)
	_expect(error == OK, "Godot parses the corrected Auto-Rig Pro candidate")
	if error != OK:
		_finish()
		return
	var instance := document.generate_scene(state)
	_expect(instance != null, "Godot generates the corrected candidate scene")
	if instance == null:
		_finish()
		return
	root.add_child(instance)
	var skeleton := _find_first(instance, "Skeleton3D") as Skeleton3D
	var player := _find_first(instance, "AnimationPlayer") as AnimationPlayer
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(instance, meshes)
	_expect(skeleton != null, "candidate contains a Skeleton3D")
	_expect(player != null, "candidate contains an AnimationPlayer")
	_expect(meshes.size() == EXPECTED_MESH_COUNT, "all 14 suit sections are present")
	if skeleton == null or player == null:
		_finish()
		return
	for mesh in meshes:
		_expect(mesh.skin != null and not mesh.skeleton.is_empty(), "%s remains skinned" % mesh.name)
	var bone_names: Array[String] = []
	for bone_index in skeleton.get_bone_count():
		bone_names.append(skeleton.get_bone_name(bone_index))
	print("OPERATOR_ARP_CANDIDATE_BONES count=%d names=%s" % [skeleton.get_bone_count(), bone_names])
	for core_bone in [
		"root.x", "thigh_stretch.l", "leg_stretch.l", "foot.l", "toes_01.l",
		"thigh_stretch.r", "leg_stretch.r", "foot.r", "toes_01.r",
	]:
		var core_index := skeleton.find_bone(core_bone)
		var parent_index := skeleton.get_bone_parent(core_index) if core_index >= 0 else -1
		print(
			"OPERATOR_ARP_CANDIDATE_PARENT bone=%s parent=%s"
			% [core_bone, skeleton.get_bone_name(parent_index) if parent_index >= 0 else ""]
		)
	print("OPERATOR_ARP_CANDIDATE_ACTIONS names=%s" % [player.get_animation_list()])
	_expect(
		player.get_animation_list().size() >= EXPECTED_ACTION_COUNT,
		"complete 82-slot gameplay library is embedded"
	)
	for required_action in [
		"native__aim_idle",
		"native__combat_fire",
		"native__idle_crouch",
		"native__prone_forward",
		"native__reload",
		"native__jump_forward_action",
		"native__run_forward_left",
	]:
		_expect(
			not _resolve_action(player.get_animation_list(), required_action).is_empty(),
			"%s survives the production export" % required_action
		)
	_verify_pose_order(player, skeleton, &"native__aim_idle")
	var action_name := _resolve_action(player.get_animation_list(), EXPECTED_ACTION_TOKEN)
	_expect(not action_name.is_empty(), "corrected rifle sprint action is embedded")
	if not action_name.is_empty():
		_verify_action(player, skeleton, action_name)
	_finish()


func _verify_action(player: AnimationPlayer, skeleton: Skeleton3D, action_name: StringName) -> void:
	var animation := player.get_animation(action_name)
	_expect(animation != null and animation.length >= 0.45, "corrected sprint has a full cycle")
	if animation == null:
		return
	var animated_bones: Dictionary = {}
	for track_index in animation.get_track_count():
		var path := String(animation.track_get_path(track_index))
		if ":" not in path:
			continue
		var bone_name := path.rsplit(":", false, 1)[-1]
		if skeleton.find_bone(bone_name) >= 0:
			animated_bones[bone_name] = true
	print(
		"OPERATOR_ARP_CANDIDATE_ACTION name=%s length=%.4f tracks=%d animated_bones=%d"
		% [action_name, animation.length, animation.get_track_count(), animated_bones.size()]
	)
	_expect(animated_bones.size() >= 20, "action drives a full-body deform skeleton")
	var required_groups := {
		"hips": ["root.x", "c_root_master.x", "pelvis.x", "hips"],
		"left_hand": ["hand.l", "c_hand_ik.l", "lefthand"],
		"right_hand": ["hand.r", "c_hand_ik.r", "righthand"],
		"left_foot": ["foot.l", "c_foot_ik.l", "leftfoot"],
		"right_foot": ["foot.r", "c_foot_ik.r", "rightfoot"],
	}
	for group_name in required_groups:
		_expect(
			_has_compatible_bone(animated_bones, required_groups[group_name]),
			"action drives the %s chain" % group_name
		)
	player.play(action_name)
	for sample_index in range(9):
		player.seek(animation.length * float(sample_index) / 8.0, true)
		player.advance(0.0)
		for bone_index in skeleton.get_bone_count():
			var pose := skeleton.get_bone_global_pose(bone_index)
			_expect(
				pose.origin.is_finite() and pose.basis.is_finite(),
				"sample %d bone %s stays finite" % [sample_index, skeleton.get_bone_name(bone_index)]
			)
			if not _failures.is_empty():
				return


func _verify_pose_order(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	action_name: StringName
) -> void:
	player.play(action_name)
	player.seek(0.0, true)
	player.advance(0.0)
	var metrics := {}
	for bone_name in ["root.x", "head.x", "foot.l", "foot.r", "toes_01.l", "toes_01.r"]:
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index >= 0:
			metrics[bone_name] = skeleton.get_bone_global_pose(bone_index).origin.y
	print("OPERATOR_ARP_CANDIDATE_POSE action=%s heights=%s" % [action_name, metrics])
	_expect(
		float(metrics.get("head.x", -INF)) > float(metrics.get("root.x", INF)),
		"native aim keeps the head above the pelvis"
	)
	_expect(
		maxf(float(metrics.get("foot.l", INF)), float(metrics.get("foot.r", INF)))
		< float(metrics.get("root.x", -INF)),
		"native aim keeps both feet below the pelvis"
	)


func _has_compatible_bone(animated_bones: Dictionary, candidates: Array) -> bool:
	for raw_name in animated_bones:
		var compact := String(raw_name).to_lower().replace("_", "").replace(".", "").replace(":", "")
		for candidate in candidates:
			var expected := String(candidate).to_lower().replace("_", "").replace(".", "").replace(":", "")
			if compact == expected or expected in compact or compact in expected:
				return true
	return false


func _resolve_action(available: PackedStringArray, token: String) -> StringName:
	for candidate in available:
		var name := String(candidate)
		if name == token or name.ends_with("/" + token) or token in name:
			return StringName(name)
	return &""


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
		print("OPERATOR_ARP_CANDIDATE_CHECK PASS ", message)
	else:
		_failures.append(message)
		push_error("OPERATOR_ARP_CANDIDATE_CHECK FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("OPERATOR_ARP_LIVE_CANDIDATE_REGRESSION PASS")
		quit(0)
	else:
		print("OPERATOR_ARP_LIVE_CANDIDATE_REGRESSION FAIL ", _failures)
		quit(1)
