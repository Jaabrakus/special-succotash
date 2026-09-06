extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	await _frames(60)
	var player := scene.get_node("Player") as CharacterBody3D
	var mannequin := player.get_node("Mannequin")
	var controller := scene.get_node("WeaponController")
	var driver: Node = mannequin.production_animation
	player.set_physics_process(false)
	mannequin.set_process(false)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	for weapon: String in ["m4a1", "mark_23", "870"]:
		_check(controller.apply_authorized_weapon_pickup("res://config/weapons/%s.json" % weapon), "equip " + weapon)
		await _frames(20)
		for stance: int in [0, 1]:
			player._try_set_posture(stance)
			var posture := &"STANDING" if stance == 0 else &"CROUCHED"
			var target := player.global_position + Vector3(0.0, 1.3, -25.0)
			driver.set_visual_inputs(Vector2.ZERO, posture, 0.0, 0.0, 1.0, false, 0.0, 0.0, &"LOCOMOTION", 0.0, &"FULL", 0.0, target, Vector2.ZERO, 0.0, &"STATIONARY", 0.0)
			await _frames(30)
			while float(controller.ballistics.fire_cooldown) > 0.0:
				await physics_frame
			var shot: Dictionary = controller.request_fire()
			_check(bool(shot.get("fired", false)), "accepted " + weapon)
			var pose: Node3D = driver.weapon_pose_solver
			_check(pose.fire_recoil.age < 0.01, "accepted shot triggers pulse")
			driver.set_process(false)
			pose.fire_recoil.age = 1.0
			driver._process(0.0)
			var baseline: Vector3 = pose._bone_world_position(&"mixamorig_RightForeArm")
			var palm_before: Transform3D = pose._right_hand_grip_world_transform()
			var shoulder_before: Vector3 = pose._bone_world_position(&"mixamorig_RightArm")
			pose.fire_recoil.age = pose.fire_recoil.attack
			# Compare one identical solved frame. Calling the entire driver twice
			# also advances its ownership handoff, confounding recoil with readiness.
			pose.fire_recoil.apply_elbow(pose, posture)
			var peak: Vector3 = pose._bone_world_position(&"mixamorig_RightForeArm")
			var shift := baseline.distance_to(peak)
			_check(palm_before.is_equal_approx(pose._right_hand_grip_world_transform()), "fixed trigger palm transform")
			_check(shoulder_before.is_equal_approx(pose._bone_world_position(&"mixamorig_RightArm")), "fixed shoulder endpoint")
			print("RECOIL_LIVE ", weapon, " ", posture, " elbow_shift_m=", shift)
			_check(shift > 0.0001 and shift < 0.06, "visible bounded elbow displacement")
			_check(pose.trigger_hand_error_m < 0.01 and pose.support_hand_error_m < 0.01, "contacts retained")
			driver.set_process(true)
			for phase: String in ["early", "peak", "return"]:
				pose.fire_recoil.age = {"early": 0.01, "peak": 0.035, "return": 0.24}[phase]
				driver._process(0.0)
				if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
					for view: String in ["rear", "side"]:
						var focus := player.global_position + Vector3(0.0, 1.25 if stance == 0 else 0.95, 0.0)
						camera.global_position = focus + (Vector3(0.8, 0.4, 2.3) if view == "rear" else Vector3(2.3, 0.3, 0.4))
						camera.look_at(focus)
						await process_frame
						RenderingServer.force_draw(false)
						root.get_texture().get_image().save_png("/private/tmp/recoil-%s-%s-%s-%s.png" % [weapon, posture, phase, view])
			driver.set_process(true)
			await _frames(60)
	scene.queue_free()
	await _frames(2)
	print("RECOIL_LIVE ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
