extends SceneTree

const Hybrid := preload("res://scripts/camera/camera_source_hybrid.gd")
const Command := preload("res://scripts/network/socom_movement_command.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	var main := load("res://main.tscn").instantiate() as Node3D
	var rig = main.get_node("IndependentCameraRig")
	rig.capture_mouse_on_ready = false
	root.add_child(main)
	print("MAIN_SOURCE_CAMERA booted main.tscn")
	rig.orbit_input_enabled = false
	var player = main.get_node("Player")
	player.set_local_input_enabled(false)
	for frame in 120:
		await physics_frame
		await process_frame
	main.get_node("WeaponController").set_input_enabled(false)
	var output := "/private/tmp/socom-source-camera-unit-proof"
	DirAccess.make_dir_recursive_absolute(output)
	var rows: Array = []
	for stance in ["standing", "crouched", "prone"]:
		print("MAIN_SOURCE_CAMERA testing ", stance)
		if stance != "standing":
			var command := Command.new()
			command.simulation_tick = Engine.get_physics_frames()
			command.crouch_released = stance == "crouched"
			command.prone_pressed = stance == "prone"
			player.queue_movement_command(command)
			await physics_frame
			await process_frame
		for trial in [false, true]:
			if trial: Hybrid.configure(rig.profile, true)
			else: rig.profile.source_camera_mix = 0.0
			for frame in 90:
				await physics_frame
				await process_frame
			var preferred_distance: float = Hybrid.open_distance(rig.profile)
			var row := {"stance": stance, "actual_stance": str(player.get_posture_name()), "trial": trial, "mix": rig.profile.source_camera_mix, "source_distance_m": rig.profile.source_camera_distance_m, "preferred_distance": preferred_distance, "preferred_height": rig.profile.height, "camera": str(rig.camera.global_position), "fov": rig.camera.fov}
			rows.append(row)
			if not is_equal_approx(preferred_distance, 2.36 if trial else 2.2): failures.append("unit-calibrated preference mismatch")
			if not is_equal_approx(rig.profile.height, 2.05): failures.append("trial modified preferred height")
			if not is_equal_approx(rig.camera.fov, 68.0): failures.append("trial modified open-camera FOV")
			if not rig.camera.global_position.is_finite(): failures.append("non-finite camera")
			if root.get_camera_3d() != rig.camera: failures.append("canonical camera is not active")
			if str(player.get_posture_name()).to_lower() != stance: failures.append("stance entry failed: " + stance)
			if "--capture" in OS.get_cmdline_user_args():
				RenderingServer.force_draw(false)
				root.get_texture().get_image().save_png(output + "/" + stance + ("-trial" if trial else "-baseline") + ".png")
	var file := FileAccess.open(output + "/measurements.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "  "))
	print("MAIN_SOURCE_CAMERA ", "PASS" if failures.is_empty() else "FAIL", " ", failures, " ", JSON.stringify(rows))
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
