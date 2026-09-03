extends SceneTree

const AGLS_SCENE_PATH := (
	"res://assets/external/agls_intake/imported/locomotion_idle/"
	+ "MM_Neutral_Stand_Idle_Loop.scn"
)

var failures: Array[String] = []


func _initialize() -> void:
	var packed := load(AGLS_SCENE_PATH) as PackedScene
	_expect(packed != null, "native AGLS scene loads")
	if packed == null:
		_finish()
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	var skeleton := _find_skeleton(instance)
	_expect(skeleton != null, "native AGLS Skeleton3D exists")
	if skeleton == null:
		_finish()
		return
	var bone_count := skeleton.get_bone_count()
	print("AGLS_NATIVE_SKELETON_INFO bone_count=%d" % bone_count)
	_expect(
		bone_count == 70,
		"Godot runtime has 69 AGLS bones plus the imported root"
	)
	_expect(skeleton.get_bone_name(0) == "root", "imported root is explicit")
	for bone_name in [
		"pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head",
		"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
		"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
		"thigh_l", "calf_l", "foot_l", "ball_l",
		"thigh_r", "calf_r", "foot_r", "ball_r",
		"ik_hand_gun",
	]:
		_expect(skeleton.find_bone(bone_name) >= 0, "bone %s exists" % bone_name)
	var player := _find_animation_player(instance)
	_expect(player != null, "native AGLS animation player exists")
	if player != null:
		var names := player.get_animation_list()
		_expect(not names.is_empty(), "native AGLS idle animation exists")
		for animation_name in names:
			if animation_name == &"RESET":
				continue
			var animation := player.get_animation(animation_name)
			var tracked_bones: Dictionary = {}
			for track_index in animation.get_track_count():
				var path := String(animation.track_get_path(track_index))
				if ":" in path:
					var tracked_bone := path.rsplit(":", false, 1)[-1]
					tracked_bones[tracked_bone] = true
					if (
						tracked_bone in ["root", "pelvis"]
						and animation.track_get_type(track_index) == Animation.TYPE_POSITION_3D
						and animation.track_get_key_count(track_index) > 0
					):
						print("AGLS_NATIVE_SKELETON_INFO %s first_position=%s" % [
							tracked_bone,
							animation.track_get_key_value(track_index, 0),
						])
			_expect(tracked_bones.has("pelvis"), "native AGLS animation tracks pelvis")
			_expect(tracked_bones.has("hand_l"), "native AGLS animation tracks left hand")
			_expect(tracked_bones.has("hand_r"), "native AGLS animation tracks right hand")
			break
	_finish()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AGLS_NATIVE_SKELETON_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("AGLS_NATIVE_SKELETON_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("AGLS_NATIVE_SKELETON_REGRESSION PASS")
		quit(0)
		return
	print("AGLS_NATIVE_SKELETON_REGRESSION FAIL %s" % [failures])
	quit(1)
