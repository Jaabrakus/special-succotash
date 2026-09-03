extends SceneTree

const STANDING_PATH := (
	"res://assets/external/agls_intake/imported/weapon_hold/"
	+ "ALS_Props_Rifle_M4A1_Poses.scn"
)
const CRAWL_PATH := (
	"res://assets/external/agls_intake/imported/weapon_hold/"
	+ "ALS_Crawl_Props_Rifle_M4A1_Poses.scn"
)

var failures: Array[String] = []


func _initialize() -> void:
	_inspect(STANDING_PATH, "standing")
	_inspect(CRAWL_PATH, "crawl")
	if failures.is_empty():
		print("AGLS_M4_HOLD_POSE_REGRESSION PASS")
		quit(0)
	else:
		print("AGLS_M4_HOLD_POSE_REGRESSION FAIL ", failures)
		quit(1)


func _inspect(path: String, label: String) -> void:
	var packed := load(path) as PackedScene
	_expect(packed != null, "%s M4 hold scene loads" % label)
	if packed == null:
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	var player := _find_animation_player(instance)
	_expect(player != null, "%s M4 hold scene contains animation" % label)
	if player != null:
		var names := player.get_animation_list()
		_expect(not names.is_empty(), "%s M4 hold animation is named" % label)
		for animation_name in names:
			var animation := player.get_animation(animation_name)
			var maximum_keys := 0
			for track_index in animation.get_track_count():
				maximum_keys = maxi(maximum_keys, animation.track_get_key_count(track_index))
			print(
				"AGLS_M4_HOLD_INFO label=%s animation=%s length=%.6f tracks=%d max_keys=%d" % [
					label,
					animation_name,
					animation.length,
					animation.get_track_count(),
					maximum_keys,
				]
			)
			_expect(animation.get_track_count() >= 50, "%s hold preserves the authored skeleton tracks" % label)
			_expect(animation.length > 0.0, "%s hold has a sample range" % label)
			if label == "standing":
				_print_hand_samples(instance, player, animation_name, animation)
	instance.free()


func _print_hand_samples(
	instance: Node,
	player: AnimationPlayer,
	animation_name: StringName,
	animation: Animation
) -> void:
	var skeleton := _find_skeleton(instance)
	_expect(skeleton != null, "standing M4 hold contains a skeleton")
	if skeleton == null:
		return
	var left_index := _find_bone(skeleton, ["hand_l", "mixamorig_LeftHand", "LeftHand"])
	var right_index := _find_bone(skeleton, ["hand_r", "mixamorig_RightHand", "RightHand"])
	var gun_index := _find_bone(skeleton, ["ik_hand_gun"])
	_expect(left_index >= 0 and right_index >= 0, "standing M4 hold preserves both hand bones")
	_expect(gun_index >= 0, "standing M4 hold preserves the authored gun mount bone")
	if left_index < 0 or right_index < 0:
		return
	player.play(animation_name)
	player.advance(0.0)
	var frame_count := maxi(1, int(round(animation.length * 30.0)))
	for frame in range(frame_count):
		player.seek(minf(float(frame) / 30.0, animation.length), true)
		var left := skeleton.get_bone_global_pose(left_index)
		var right := skeleton.get_bone_global_pose(right_index)
		var relative := right.affine_inverse() * left
		var gun_relative := Transform3D.IDENTITY
		if gun_index >= 0:
			gun_relative = right.affine_inverse() * skeleton.get_bone_global_pose(gun_index)
		print(
			"AGLS_M4_HOLD_SAMPLE frame=%d distance=%.6f relative=(%.6f,%.6f,%.6f) gun=(%.6f,%.6f,%.6f)" % [
				frame,
				left.origin.distance_to(right.origin),
				relative.origin.x,
				relative.origin.y,
				relative.origin.z,
				gun_relative.origin.x,
				gun_relative.origin.y,
				gun_relative.origin.z,
			]
		)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_bone(skeleton: Skeleton3D, candidates: Array[String]) -> int:
	for candidate in candidates:
		var index := skeleton.find_bone(candidate)
		if index >= 0:
			return index
	return -1


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
		print("AGLS_M4_HOLD_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("AGLS_M4_HOLD_CHECK FAIL %s" % label)
