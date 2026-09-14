extends SceneTree

const Command := preload("res://scripts/network/socom_movement_command.gd")
var failures: Array[String] = []
var rows: Array = []
var output := "/private/tmp/main-dive-camera"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	var durable := ProjectSettings.globalize_path("res://art_source/dive_camera_verified_20260913")
	if not output.begins_with("/private/tmp/") and output != durable:
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	root.size = Vector2i(1280,800)
	var main := load("res://main.tscn").instantiate() as Node3D
	var rig = main.get_node("IndependentCameraRig")
	rig.capture_mouse_on_ready = false
	root.add_child(main)
	var player = main.get_node("Player")
	player.set_local_input_enabled(false)
	main.get_node("WeaponController").set_input_enabled(false)
	rig.orbit_input_enabled = false
	rig.orbit_drag_enabled = false
	await _frames(60)
	var platform := StaticBody3D.new()
	platform.position = Vector3(500,-.5,500)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50,1,50)
	collider.shape = box
	platform.add_child(collider)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	platform.add_child(mesh)
	main.add_child(platform)
	var driver = player.get_node("Mannequin/ProductionAnimation")
	var skeleton: Skeleton3D = driver.skeleton
	var anchor = skeleton.get_node("SourceCameraAnchor")
	var initial_duration: float = player.dive_duration
	for stance in ["standing", "crouched"]:
		for pitch_degrees in [0.0,-25.0,25.0]:
			# Reset only fixture position between independent owner-command trials.
			# Posture, action, jump and all motion within each trial use real commands.
			if player.get_posture_name() == &"PRONE":
				var crouch := Command.new()
				crouch.crouch_released = true
				player.queue_movement_command(crouch)
				await _frames(35)
			if String(player.get_posture_name()).to_lower() != stance:
				var toggle := Command.new()
				toggle.crouch_released = true
				player.queue_movement_command(toggle)
				await _frames(35)
			player.global_position = Vector3(500,.02,500)
			player.velocity = Vector3.ZERO
			rig.yaw = 0.0
			rig.aim_yaw = 0.0
			rig.pitch = deg_to_rad(pitch_degrees)
			rig.aim_pitch = rig.pitch
			rig.reset_camera_to_target()
			await _frames(60)
			_expect(String(player.get_posture_name()).to_lower() == stance, "real entry stance "+stance)
			var start: Vector3 = player.global_position
			# Continuous approach, one Z/dive press, then movement release. No
			# frame-by-frame input gaps capable of generating double-tap combos.
			for tick in 100:
				var command := Command.new()
				command.simulation_tick = Engine.get_physics_frames()+tick
				command.aim_pitch = rig.aim_pitch
				if tick < 25:
					command.move_axis = Vector2(0,-1)
					command.direction_held_mask = 1
				command.dive_pressed = tick == 24
				player.queue_movement_command(command)
			var saw_dive := false
			var late_samples := 0
			var captured := {}
			var previous_lens := Vector3.ZERO
			for sample_index in 110:
				await _frames(1)
				var state := String(player.get_motion_state_name())
				var phase: float = player.get_action_phase()
				var preference: Dictionary = rig.preferred_shot_solver.source_preference()
				var head := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_Head")).origin
				var head_uv: Vector2 = rig.camera.unproject_position(head) / root.get_visible_rect().size
				var lens: Vector3 = rig.camera.global_position
				rows.append({"entry":stance,"pitch":pitch_degrees,"sample":sample_index,"state":state,"posture":String(player.get_posture_name()),"phase":phase,"clip":String(driver.current_clip),"root_y":float(anchor.root_source.y),"coverage":float(anchor.coverage),"player":_array(player.global_position),"lens":_array(lens),"lens_step":0.0 if previous_lens==Vector3.ZERO else lens.distance_to(previous_lens),"preferred":_array(rig.preferred_camera_position),"source_preferred":_array(preference.get("position",Vector3.ZERO)),"head_uv":[head_uv.x,head_uv.y],"collision":rig.collision_active,"marker_y":rig.head_marker.global_position.y-player.global_position.y})
				previous_lens = lens
				_expect(lens.is_finite() and not preference.is_empty(),"finite paired dive camera")
				_expect(absf(rig.aim_pitch-deg_to_rad(pitch_degrees))<.00001 and absf(rig.aim_yaw)<.00001,"dive leaves shared aim unchanged")
				var label := ""
				if state == "DIVING":
					saw_dive = true
					_expect(player.is_fire_locked_by_mobility(),"dive firing lock retained")
					_expect(is_equal_approx(player.action_duration,initial_duration),"dive action duration unchanged")
					label = "early" if phase < .3 else ("middle" if phase < .7 else "late")
					if phase >= .82:
						late_samples += 1
						_expect(anchor.coverage > .99,"late source dive has complete observer coverage")
						_expect(float(anchor.root_source.y)<4.0,"late dive root stays prone instead of restoring upright closure")
						if pitch_degrees == 0.0:
							_expect(head_uv.y>=0.0 and head_uv.y<.95,"level late-dive skinned head remains in frame")
				elif saw_dive and sample_index>85: label = "settled"
				if label!="" and not captured.has(label):
					captured[label] = true
					if "--capture" in OS.get_cmdline_user_args():
						RenderingServer.force_draw(false)
						root.get_texture().get_image().save_png(output.path_join("%s-pitch%d-%s.png"%[stance,pitch_degrees,label]))
			_expect(saw_dive and late_samples>0,"actual dive command entered and reached late action")
			_expect(player.get_posture_name()==&"PRONE","dive finishes prone")
			_expect(player.global_position.distance_to(start)>.5,"actual owner approach and dive moved body")
			print("MAIN_DIVE_CAMERA sampled ",stance," pitch=",pitch_degrees)
	var file := FileAccess.open(output.path_join("measurements.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":rows,"failures":failures,"duration":initial_duration,"scope":"actual main Z/dive from standing/crouch; directional AGLS combos not covered"},"  "))
	file.close()
	print("MAIN_DIVE_CAMERA ","PASS" if failures.is_empty() else "FAIL"," rows=",rows.size()," failures=",failures," output=",output)
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func _array(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _expect(value: bool, label: String) -> void:
	if not value and not label in failures: failures.append(label)
