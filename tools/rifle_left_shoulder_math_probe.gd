extends "res://tools/rifle_reference_visual_probe.gd"

## Translation: diagnose A shoulder residual in canonical AK/M4. Acceptance:
## physical before/after shoulder points explain the same chest owner's math.
## Diagnostic only: no profiles, sockets, hand pose, body/camera, leg or bob changes.
## Frozen direct calls exercise the EXISTING posture owner; no replacement writer.
## Proof: per-stance canonical samples, ancestry/scales and one/two/three passes.


func _run() -> void:
	scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await _frames(45)
	player = scene.get_node("Player") as CharacterBody3D
	controller = scene.get_node("WeaponController")
	driver = player.get_node("Mannequin/ProductionAnimation")
	_install_fixture()
	if not bool(controller.call("apply_authorized_weapon_pickup", "res://config/weapons/%s.json" % weapon_id)):
		failures.append("Canonical equip failed")
		_finish()
		return
	await _frames(60)
	for stance in [0, 1]:
		Input.action_release(&"move_left")
		player.global_position = Vector3(500, 0.02, 500)
		player.velocity = Vector3.ZERO
		player.call("_try_set_posture", stance)
		await _frames(100)
		Input.action_press(&"move_left")
		await _frames(100)
		for firing: bool in [false, true]:
			if firing:
				_request_shot()
				await _frames(25)
			paused = true
			var skeleton: Skeleton3D = driver.get("skeleton")
			var owner: RefCounted = driver.get("posture_layer")
			var target: Vector3 = driver.get("visual_aim_target")
			var row := {"stance": stance, "firing": firing, "before": _math_state(skeleton, owner, target), "passes": []}
			for iteration in 3:
				owner.call("_apply_square_shoulders", target, 1.0, true, 0.0, 90.0)
				row.passes.append(_math_state(skeleton, owner, target))
			for name: StringName in [&"mixamorig_RightArm", &"mixamorig_RightForeArm", &"mixamorig_RightHand"]:
				skeleton.set_bone_global_pose_override(skeleton.find_bone(name), Transform3D.IDENTITY, 0.0, true)
			skeleton.force_update_all_bone_transforms()
			row["after_prior_elbow_clear"] = _math_state(skeleton, owner, target)
			owner.call("_apply_square_shoulders", target, 1.0, true, 0.0, 90.0)
			row["after_one_clean_pass"] = _math_state(skeleton, owner, target)
			samples.append(row)
			print("LEFT_SHOULDER_MATH ", JSON.stringify(row))
			paused = false
			await _frames(2)
	_finish()


func _math_state(skeleton: Skeleton3D, owner: RefCounted, target: Vector3) -> Dictionary:
	var left := skeleton.find_bone("mixamorig_LeftArm")
	var right := skeleton.find_bone("mixamorig_RightArm")
	var l := skeleton.global_transform * skeleton.get_bone_global_pose(left).origin
	var r := skeleton.global_transform * skeleton.get_bone_global_pose(right).origin
	var aim_right := (target - (l + r) * 0.5).cross(Vector3.UP).normalized()
	var bar := (r - l).normalized()
	var chain: Array[Dictionary] = []
	for name: StringName in [&"mixamorig_Hips", &"mixamorig_Spine", &"mixamorig_Spine1", &"mixamorig_Spine2", &"mixamorig_LeftShoulder", &"mixamorig_RightShoulder", &"mixamorig_LeftArm", &"mixamorig_RightArm"]:
		var index := skeleton.find_bone(name)
		var parent := skeleton.get_bone_parent(index)
		var basis := skeleton.get_bone_global_pose(index).basis
		var scale := basis.get_scale()
		var q := basis.get_rotation_quaternion().normalized()
		var qo := basis.orthonormalized().get_rotation_quaternion().normalized()
		chain.append({"bone": str(name), "parent": skeleton.get_bone_name(parent) if parent >= 0 else "", "global_scale": str(scale), "pose_scale": str(skeleton.get_bone_pose_scale(index)), "global_det": basis.determinant(), "ortho_quaternion_error_deg": rad_to_deg(q.angle_to(qo)), "world_origin": str(skeleton.global_transform * skeleton.get_bone_global_pose(index).origin)})
	return {"physical_error_deg": rad_to_deg(acos(clampf(absf(bar.dot(aim_right)), 0.0, 1.0))), "left_world": str(l), "right_world": str(r), "skeleton_scale": str(skeleton.global_basis.get_scale()), "chain": chain, "posture": owner.call("get_debug_state")}
