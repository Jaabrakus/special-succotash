extends SceneTree

var failures: Array[String] = []
var rig: Skeleton3D
var base: Array[Transform3D] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var player: Node = preload("res://scenes/player/operator_player.tscn").instantiate()
	player.set_local_input_enabled(false)
	root.add_child(player)
	await process_frame
	var driver = player.get_node("Mannequin/ProductionAnimation")
	driver.set_process(false)
	driver.animation_tree.active = false
	rig = driver.skeleton
	var layer = driver.posture_layer
	for posture in [&"STANDING", &"CROUCHED"]:
		var clip: Animation = driver.animation_player.get_animation(&"idle_rifle" if posture == &"STANDING" else &"idle_crouch")
		rig.reset_bone_poses()
		for track in clip.get_track_count():
			var bone := rig.find_bone(str(clip.track_get_path(track)).get_slice(":", 1))
			if bone < 0: continue
			if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				rig.set_bone_pose_rotation(bone, clip.rotation_track_interpolate(track, 0.0))
			elif clip.track_get_type(track) == Animation.TYPE_POSITION_3D:
				rig.set_bone_pose_position(bone, clip.position_track_interpolate(track, 0.0))
		base.clear()
		for bone in rig.get_bone_count(): base.append(rig.get_bone_pose(bone))
		for family in [&"TWO_HAND_RIFLE", &"TWO_HAND_PISTOL"]:
			layer.authored_peek_family = family
			layer.peek_travel_weight = 0.0
			for amount in [-1.0, -0.5, 0.5, 1.0]:
				_restore()
				layer.preserve_grounded_lean_legs = false
				if not layer._apply_authored_peek(posture, signf(amount)):
					failures.append("Missing authored lean: %s/%s" % [family, posture])
				# Oracle: one blend from base to the held endpoint, never double
				# weighting a scrubbed entry animation on the way back from fire.
				for bone in rig.get_bone_count():
					rig.set_bone_pose_rotation(bone, base[bone].basis.get_rotation_quaternion().slerp(rig.get_bone_pose_rotation(bone), absf(amount)))
				var head := rig.find_bone("mixamorig_Head")
				var expected := rig.get_bone_global_pose(head).basis.get_rotation_quaternion()
				var hips := rig.find_bone("mixamorig_Hips")
				var expected_hips := rig.get_bone_pose_rotation(hips)
				_restore()
				layer.preserve_grounded_lean_legs = true
				layer.standing_lean_weight = 0.0
				if not layer._apply_authored_peek(posture, amount):
					failures.append("Missing preserved lean: %s/%s" % [family, posture])
				var actual := rig.get_bone_global_pose(head).basis.get_rotation_quaternion()
				var error := rad_to_deg(expected.angle_to(actual))
				var label := "%s/%s/%s" % [family, posture, amount]
				print("LEAN_FRAME ", label, " orientation_error_deg=", error)
				if error > 0.1: failures.append(label + " upper frame differs from authored lean")
				for bone in rig.get_bone_count():
					var name := str(rig.get_bone_name(bone))
					if "Hips" in name or "Leg" in name or "Foot" in name or "Toe" in name:
						if not rig.get_bone_pose(bone).is_equal_approx(base[bone]): failures.append(label + " altered grounded leg " + name)
				if posture == &"STANDING":
					_restore()
					var height: float = layer._lean_support_height()
					layer.standing_lean_weight = 1.0
					layer._apply_authored_peek(posture, amount)
					if rad_to_deg(expected_hips.angle_to(rig.get_bone_pose_rotation(hips))) > 0.1:
						failures.append(label + " stationary hips must match authored lean")
					if absf(height - layer._lean_support_height()) > 0.00001:
						failures.append(label + " stationary lean changed support height")
					actual = rig.get_bone_global_pose(head).basis.get_rotation_quaternion()
					if rad_to_deg(expected.angle_to(actual)) > 0.1:
						failures.append(label + " stationary torso must match authored lean")
	player.free()
	print("LEAN_UPPER_FRAME ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _restore() -> void:
	for bone in base.size():
		rig.set_bone_pose_position(bone, base[bone].origin)
		rig.set_bone_pose_rotation(bone, base[bone].basis.get_rotation_quaternion())
