extends SceneTree

const SWEEPS := {
	"standing": "res://assets/external/agls_intake/imported/weapon_hold/ALS_Props_Rifle_Aim_Sweep.scn",
	"crouched": "res://assets/external/agls_intake/imported/weapon_hold/ALS_Props_Rifle_Aim_Sweep_Crouched.scn",
	"prone": "res://assets/external/agls_intake/imported/weapon_hold/ALS_Crawl_Props_Rifle_Aim_Sweep.scn",
}

var failures: Array[String] = []


func _initialize() -> void:
	for posture in SWEEPS:
		_audit(posture, SWEEPS[posture])
	if failures.is_empty():
		print("AGLS_RIFLE_AIM_SWEEP_AUDIT PASS")
		quit(0)
	else:
		print("AGLS_RIFLE_AIM_SWEEP_AUDIT FAIL ", failures)
		quit(1)


func _audit(posture: String, path: String) -> void:
	var packed := load(path) as PackedScene
	_expect(packed != null, "%s aim sweep loads" % posture)
	if packed == null:
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	var skeleton := _find_skeleton(instance)
	var player := _find_animation_player(instance)
	_expect(skeleton != null and player != null, "%s sweep preserves animation rig" % posture)
	if skeleton == null or player == null:
		instance.free()
		return
	var gun_index := skeleton.find_bone("ik_hand_gun")
	var left_index := skeleton.find_bone("hand_l")
	var right_index := skeleton.find_bone("hand_r")
	_expect(
		gun_index >= 0 and left_index >= 0 and right_index >= 0,
		"%s sweep preserves gun and hand bones" % posture
	)
	var names := player.get_animation_list()
	_expect(not names.is_empty(), "%s sweep contains an animation" % posture)
	if names.is_empty() or gun_index < 0 or left_index < 0 or right_index < 0:
		instance.free()
		return
	var animation_name: StringName = names[0]
	if animation_name == &"RESET" and names.size() > 1:
		animation_name = names[1]
	var animation := player.get_animation(animation_name)
	var maximum_keys := 0
	for track_index in animation.get_track_count():
		maximum_keys = maxi(maximum_keys, animation.track_get_key_count(track_index))
		if "ik_hand_gun" in String(animation.track_get_path(track_index)):
			var key_count := animation.track_get_key_count(track_index)
			var sample_indices: Array[int] = [0]
			if key_count > 1:
				sample_indices.append(key_count / 2)
				sample_indices.append(key_count - 1)
			for key_index in sample_indices:
				print(
					"AGLS_RIFLE_AIM_SWEEP_TRACK posture=%s path=%s type=%d key=%d time=%.6f value=%s"
					% [
						posture,
						animation.track_get_path(track_index),
						animation.track_get_type(track_index),
						key_index,
						animation.track_get_key_time(track_index, key_index),
						str(animation.track_get_key_value(track_index, key_index)),
					]
				)
	player.play(animation_name)
	player.advance(0.0)
	var frame_count := maxi(1, int(round(animation.length * 30.0)))
	var minimum_hand_distance := INF
	var maximum_hand_distance := 0.0
	var reference_forward := Vector3.ZERO
	print(
		"AGLS_RIFLE_AIM_SWEEP_INFO posture=%s animation=%s length=%.6f frames=%d tracks=%d max_keys=%d"
		% [
			posture, animation_name, animation.length, frame_count,
			animation.get_track_count(), maximum_keys,
		]
	)
	for frame in range(frame_count):
		player.seek(minf(float(frame) / 30.0, animation.length), true)
		skeleton.force_update_all_bone_transforms()
		var gun := skeleton.get_bone_global_pose(gun_index)
		var left := skeleton.get_bone_global_pose(left_index)
		var right := skeleton.get_bone_global_pose(right_index)
		var hand_distance := left.origin.distance_to(right.origin)
		minimum_hand_distance = minf(minimum_hand_distance, hand_distance)
		maximum_hand_distance = maxf(maximum_hand_distance, hand_distance)
		var forward := (gun.basis.orthonormalized() * Vector3.BACK).normalized()
		if frame == frame_count / 2:
			reference_forward = forward
		print(
			"AGLS_RIFLE_AIM_SWEEP_SAMPLE posture=%s frame=%d forward=(%.6f,%.6f,%.6f) hands=%.6f gun_to_right=%.6f"
			% [
				posture,
				frame,
				forward.x,
				forward.y,
				forward.z,
				hand_distance,
				gun.origin.distance_to(right.origin),
			]
		)
	_expect(
		minimum_hand_distance >= 0.15 and maximum_hand_distance <= 0.45,
		"%s sweep keeps the authored two-hand relationship human-sized" % posture
	)
	_expect(reference_forward.length_squared() > 0.99, "%s sweep has a valid center frame" % posture)
	instance.free()


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
		print("AGLS_RIFLE_AIM_SWEEP_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("AGLS_RIFLE_AIM_SWEEP_CHECK FAIL %s" % label)
