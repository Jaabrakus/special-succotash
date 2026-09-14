extends "res://tools/rifle_reference_visual_probe.gd"

var checks := 0
class ReloadObserver extends Node:
	var driver: Node
	var rows: Array[Dictionary] = []
	func _process(_delta: float) -> void:
		if driver == null: return
		rows.append({"logical":String(driver.requested_action), "evaluated":String(driver.source_spine_pitch_evaluated_action), "bones":driver.posture_layer.aim_spine_pitch.last_bone_count})


func _initialize() -> void:
	output_prefix = "/private/tmp/aim-spine-main"
	super._initialize()


func _run() -> void:
	if capture and DisplayServer.get_name() == "headless":
		_check(false, "rendering requires a native display")
		_finish()
		return
	DirAccess.make_dir_recursive_absolute(output_prefix.get_base_dir())
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	ProjectSettings.set_setting("socom/session/public_training", true)
	root.size = Vector2i(1280, 800)
	scene = load("res://main.tscn").instantiate()
	scene.get_node("IndependentCameraRig").capture_mouse_on_ready = false
	root.add_child(scene)
	player = scene.get_node("Player")
	player.set_local_input_enabled(false)
	var rig: Node3D = scene.get_node("IndependentCameraRig")
	rig.orbit_input_enabled = false
	await _frames(45)
	controller = scene.get_node("WeaponController")
	driver = player.get_node("Mannequin/ProductionAnimation")
	controller.set_input_enabled(false)
	_install_fixture()
	await _frames(40)
	_check(driver.model_root.scene_file_path == "res://assets/characters/modern_soldier/modern_soldier_iso.scn", "actual selected model")
	var scale_before: Vector3 = driver.model_root.scale
	for gun: String in ["m4a1", "mark_23"]:
		weapon_id = gun
		_check(controller.apply_authorized_weapon_pickup("res://config/weapons/" + gun + ".json"), "canonical equip " + gun)
		await _frames(40)
		_check(String(driver.equipped_weapon_config.get("weapon_id", "")) == gun, "equipped identity " + gun)
		for stance in 3:
			_check(player.call("_try_set_posture", stance), "canonical stance " + str(stance))
			await _frames(100)
			for degrees in [-25.0, 0.0, 25.0]:
				rig.yaw = 0.0
				rig.aim_yaw = 0.0
				rig.pitch = deg_to_rad(degrees)
				rig.aim_pitch = rig.pitch
				await _frames(70)
				var label := gun + "_stance_" + str(stance) + "_pitch_" + str(degrees)
				for frame in 6:
					await _frames(1)
					_check_pose(label, degrees)
				await _record(label)
				if gun == "m4a1" and stance == 0 and degrees == 25.0 and _request_shot():
					for stage in [1, 7, 24]:
						await _frames(stage)
						_check_pose("accepted_fire_" + str(stage), degrees)
					await _record("accepted_fire")
					_check(scene.call("_request_weapon_reload"), "real reload accepted")
					var observer := ReloadObserver.new()
					observer.process_priority = 1000
					observer.driver = driver
					scene.add_child(observer)
					await _frames(4)
					_check(driver.posture_layer.aim_spine_pitch.last_bone_count == 0, "reload suppresses spine overlay")
					await _record("reload_suppressed")
					for reload_frame in 360:
						await _frames(1)
						if String(driver.source_spine_pitch_evaluated_action).contains("reload"):
							_check(driver.posture_layer.aim_spine_pitch.last_bone_count == 0, "evaluated reload frame stays suppressed")
						if not bool(player.get_meta("reload_action_pending", false)) and driver.requested_action == &"": break
					await _frames(2)
					var observed_reload_tail := false
					var observed_reload_frames := 0
					for row in observer.rows:
						if row.evaluated.contains("reload"):
							observed_reload_frames += 1
							_check(row.bones == 0, "late-process evaluated reload suppressed")
							if row.logical == "": observed_reload_tail = true
					_check(observed_reload_frames > 0, "late-process observer sampled reload")
					print("AIM_SPINE_RELOAD_TAIL observed=", observed_reload_tail, " frames=", observed_reload_frames)
					# Coordinator cancellation can clear the action before the driver
					# begins, so not every real reload has a timer-expiry tail. Every
					# frame that actually evaluates reload must nevertheless be clear.
					observer.free()
					await _frames(40)
		_check(driver.model_root.scale == scale_before and player.scale == Vector3.ONE, "visual scale and body owner preserved")
	print("AIM_SPINE_MAIN ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	_finish()


func _check_pose(label: String, degrees: float) -> void:
	var spine: RefCounted = driver.posture_layer.aim_spine_pitch
	_check(spine.last_reason == "applied" and spine.last_bone_count == 3, label + " active chain")
	var shared_angles: Vector2 = scene.get_node("IndependentCameraRig").get_shared_body_aim_yaw_pitch()
	if player.has_method("get_animation_aim_state"):
		shared_angles = player.call("get_animation_aim_state").angles
	# On a newly accepted shot the camera may have just published its next VRC
	# target. Compare camera to driver only after settled input; the helper's
	# recorded consumed input and driver remain identical even at that boundary.
	if not label.begins_with("accepted_fire"):
		_check(absf(driver.aim_pitch_rad - shared_angles.y) < .005, label + " shared aim forwarded")
	_check(absf(spine.last_input_pitch_rad - driver.aim_pitch_rad) < .00001, label + " exact driver pitch consumed")
	_check(spine.last_protected_delta < .00001, label + " pelvis/feet unchanged by pass")
	var settings: Dictionary = driver.posture_layer.look_pitch_profile.spine_aim[String(driver.posture).to_lower()]
	var expected := clampf(spine.last_input_pitch_rad * float(settings.gain), -deg_to_rad(settings.down_limit_deg), deg_to_rad(settings.up_limit_deg))
	_check(absf(spine.last_pitch_rad - expected) < .002, label + " follows bounded shared pitch")
	if absf(degrees) >= .01:
		_check(signf(spine.last_pitch_rad) == signf(degrees) and absf(spine.last_pitch_rad) > .01, label + " pitch direction and magnitude")
	var measured := _measure_physical_pose()
	_check(float(measured.get("trigger_contact_m", INF)) < .025, label + " trigger contact")
	# Native one-handed pistol deliberately releases support: not a failed grip.
	if weapon_id == "m4a1": _check(float(measured.get("support_contact_m", INF)) < .025, label + " support contact")
	_check(player.is_on_floor(), label + " body remains grounded")


func _record(label: String) -> void:
	var spine: RefCounted = driver.posture_layer.aim_spine_pitch
	var row := _measure_physical_pose()
	row.merge({"state":label, "shared_pitch_deg":rad_to_deg(driver.aim_pitch_rad), "consumed_pitch_deg":rad_to_deg(spine.last_input_pitch_rad), "evaluated_action":String(driver.source_spine_pitch_evaluated_action), "applied_pitch_deg":rad_to_deg(spine.last_pitch_rad), "protected_delta":spine.last_protected_delta, "spine_rotation_delta":spine.last_spine_delta, "head_y":_height(driver.skeleton, &"mixamorig_Head"), "hips_y":_height(driver.skeleton, &"mixamorig_Hips"), "left_foot_y":_height(driver.skeleton, &"mixamorig_LeftFoot"), "right_foot_y":_height(driver.skeleton, &"mixamorig_RightFoot")})
	if capture:
		# Preserve the actual canonical camera for one view, followed by the
		# inherited explicitly diagnostic rear/side views. No gameplay stepping.
		var prior_pause := paused
		paused = true
		driver.skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		_flush_capture_transforms(driver.weapon_node)
		root.get_camera_3d().force_update_transform()
		RenderingServer.force_sync()
		RenderingServer.force_draw(false, 0.0)
		var path := output_prefix + "-" + label + "-canonical.png"
		_check(root.get_texture().get_image().save_png(path) == OK, "canonical capture")
		paused = prior_pause
		await super._sample(label)
		samples.back().merge(row)
		samples.back().images["canonical"] = path
	else:
		samples.append(row)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("AIM_SPINE_MAIN " + label)
