extends "res://tools/seal_stance_visual_probe.gd"

## Canonical jump diagnostic. No pose or movement overrides.
func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	root.size = Vector2i(1280,800)
	var fence := InputFence.new()
	fence.process_priority = -10000
	root.add_child(fence)
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await _frames(60)
	player = scene.get_node("Player")
	driver = player.get_node("Mannequin/ProductionAnimation")
	controller = scene.get_node("WeaponController")
	controller.set_input_enabled(false)
	_install_fixture()
	var rows: Array[Dictionary] = []
	for gun in ["ak-47","mark_23"]:
		controller.apply_authorized_weapon_pickup("res://config/weapons/"+gun+".json")
		for moving in [false,true]:
			fence.held.clear()
			player.global_position = Vector3(500,0.02,500)
			player.velocity = Vector3.ZERO
			await _frames(90)
			if moving: fence.held.assign([&"move_forward"])
			await _frames(30)
			var label: String = gun + ("_moving" if moving else "_idle")
			var previous: Dictionary = {}
			var maximum := 0.0
			var maximum_hip_step := 0.0
			var previous_hip := 0.0
			var previous_air := false
			var previous_tick := Engine.get_physics_frames()
			player.request_jump()
			for frame in 65:
				await _frames(1)
				var ticks: int = maxi(Engine.get_physics_frames()-previous_tick,1)
				previous_tick = Engine.get_physics_frames()
				var row := {"case":label,"frame":frame,"state":String(driver.movement_state),"clip":String(driver.current_clip),"body_y":player.position.y,"vy":player.velocity.y,"phase":driver.source_jump_frame.duplicate(true)}
				for bone in ["Hips","Spine2","Head","LeftUpLeg","RightUpLeg"]:
					var index: int = driver.skeleton.find_bone("mixamorig_"+bone)
					var pose: Transform3D = driver.skeleton.get_bone_global_pose(index)
					var rotation: Quaternion = pose.basis.orthonormalized().get_rotation_quaternion()
					row[bone+"_y"] = (driver.skeleton.global_transform * pose.origin).y - player.position.y
					row[bone+"_rotation"] = [rotation.x,rotation.y,rotation.z,rotation.w]
					if previous.has(bone):
						var step := rad_to_deg(rotation.angle_to(previous[bone]))
						row[bone+"_step"] = step
						maximum = maxf(maximum,step/ticks)
					previous[bone] = rotation
				if previous_air and driver.movement_state==&"AIRBORNE":
					maximum_hip_step = maxf(maximum_hip_step,absf(float(row.Hips_y)-previous_hip)/ticks)
				previous_hip = float(row.Hips_y)
				previous_air = driver.movement_state==&"AIRBORNE"
				rows.append(row)
				if capture and frame in [2,10,14,22,29,35,43]:
					await _sample(label+"_"+str(frame))
			print("JUMP_CONTINUITY ",label," max_bone_step_deg=",maximum," max_airborne_hip_step_m=",maximum_hip_step)
			if maximum>25.0: failures.append(label+" bone snap exceeds 25 degrees per physics tick")
			if maximum_hip_step>0.04: failures.append(label+" duplicate hip jump exceeds 4 cm per physics tick")
	var output := FileAccess.open(output_prefix+"-continuity.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(rows))
	output.close()
	fence.held.clear()
	_finish()
