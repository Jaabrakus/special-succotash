extends SceneTree

## Real main owner/stance pipeline. No extra camera, no asset/profile writes.
const Command := preload("res://scripts/network/socom_movement_command.gd")
var failures: Array[String] = []
var rows: Array = []
var lean_rows: Array = []
var output := "/private/tmp/source-gameplay-camera-main"
var candidate := false
var visual_quick := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	candidate = not "--authored-camera" in OS.get_cmdline_user_args()
	visual_quick = "--visual-quick" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	var durable_proof := ProjectSettings.globalize_path("res://art_source/source_camera_hybrid_verified_20260913")
	if not output.begins_with("/private/tmp/") and output != durable_proof:
		push_error("proof output must be a temporary directory or the dedicated ignored hybrid proof folder")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	root.size = Vector2i(1280,800)
	var main := load("res://main.tscn").instantiate() as Node3D
	var rig = main.get_node("IndependentCameraRig")
	_expect(rig.source_camera_match.lens_enabled() and rig.source_camera_match.settings.preferred_position_enabled, "saved main default enables verified full source camera")
	if not candidate: rig.source_camera_match.settings.enabled = false
	if "--source-camera" in OS.get_cmdline_user_args(): rig.source_camera_match.settings.framing_mode = "source"
	rig.capture_mouse_on_ready = false
	root.add_child(main)
	var player = main.get_node("Player")
	player.set_local_input_enabled(false)
	rig.orbit_input_enabled = false
	rig.orbit_drag_enabled = false
	await _frames(60)
	var gameplay_spawn: Vector3 = player.global_position
	main.get_node("WeaponController").set_input_enabled(false)
	var platform := StaticBody3D.new()
	platform.position = Vector3(500,-.5,500)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30,1,30)
	collider.shape = box
	platform.add_child(collider)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	platform.add_child(mesh)
	main.add_child(platform)
	player.global_position = Vector3(500,.02,500)
	player.velocity = Vector3.ZERO
	rig.yaw = 0.0
	rig.aim_yaw = 0.0
	rig.pitch = 0.0
	rig.aim_pitch = 0.0
	rig.reset_camera_to_target()
	await _frames(90)
	var driver = player.get_node("Mannequin/ProductionAnimation")
	var skeleton: Skeleton3D = driver.skeleton
	_expect(skeleton.find_bone("skel_root") < 0, "current retarget missing independent original root is reported")
	_expect(skeleton.has_node("SourceCameraAnchor"), "independent source observer retained without adding bones")
	for stance in ["standing", "crouched", "prone"]:
		if stance != "standing":
			var command := Command.new()
			command.simulation_tick = Engine.get_physics_frames()
			command.crouch_released = stance == "crouched"
			command.prone_pressed = stance == "prone"
			player.queue_movement_command(command)
			await _frames(60)
		for degrees in [-30.0,0.0,25.0,28.0]:
			for yaw_degrees in ([0.0] if visual_quick else [0.0,65.0]):
				rig.yaw = deg_to_rad(yaw_degrees)
				rig.aim_yaw = rig.yaw
				rig.pitch = deg_to_rad(degrees)
				rig.aim_pitch = rig.pitch
				await _frames(35)
				var size: Vector2 = root.get_visible_rect().size
				var aspect := size.x / size.y
				var horizontal := rad_to_deg(2.0*atan(tan(deg_to_rad(rig.camera.fov)*.5)*aspect))
				var actual := str(player.get_posture_name()).to_lower()
				var head_world := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_Head")).origin
				var chest_world := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_Spine2")).origin
				var actual_head: Vector2 = rig.camera.unproject_position(head_world) / size
				var actual_chest: Vector2 = rig.camera.unproject_position(chest_world) / size
				var row := {"candidate":candidate,"stance":stance,"actual_stance":actual,"pitch_degrees":degrees,"yaw_degrees":yaw_degrees,"viewport":str(size),"vertical_fov":rig.camera.fov,"horizontal_fov":horizontal,"camera":str(rig.camera.global_position),"preferred_position":str(rig.preferred_camera_position),"camera_collision_active":rig.collision_active,"source_position_active":false,"native_root_bone_missing":true,"head_projection":rig.camera.unproject_position(rig.head_marker.global_position),"actual_mesh_head_normalized":[actual_head.x,actual_head.y],"actual_mesh_chest_normalized":[actual_chest.x,actual_chest.y],"body_aim":str(rig.get_shared_body_aim_yaw_pitch())}
				rows.append(row)
				var preference: Dictionary = rig.preferred_shot_solver.source_preference()
				row["source_position_active"] = not preference.is_empty()
				row["observer_root"] = str(skeleton.get_node("SourceCameraAnchor").root_source)
				row["observer_coverage"] = skeleton.get_node("SourceCameraAnchor").coverage
				if candidate: _expect(not preference.is_empty(), "source channel actually drives stance " + stance)
				_expect(actual == stance, "real stance command " + stance)
				if candidate:
					_expect(absf(horizontal - rig.source_camera_match.active_horizontal_fov()) < .0001, "saved HFOV remains fixed across stance/pitch/yaw")
				else:
					_expect(absf(rig.camera.fov - rig.profile.vertical_fov) < .0001, "default authored lens preserved")
				if degrees == 0.0:
					_expect(actual_head.y >= 0.0 and actual_head.y < .95, "render acceptance: actual mesh head visible at level aim " + stance)
					_expect(actual_chest.y >= 0.0 and actual_chest.y < 1.02, "render acceptance: actual mesh chest visible at level aim " + stance)
				if candidate and rig.source_camera_match.hybrid_enabled():
					_expect(actual_head.y >= 0.0 and actual_head.y < .99,"hybrid keeps actual head in viewport at signed pitch "+stance+"/"+str(degrees))
					_expect(not rig.collision_active,"open-platform hybrid does not force a ground-compressed boom")
				_expect(root.get_camera_3d() == rig.camera, "canonical camera active")
				_expect(rig.camera.global_position.is_finite(), "finite actual camera")
				_expect(rig.camera.keep_aspect == Camera3D.KEEP_HEIGHT, "existing vertical projection convention retained")
				var cursor := size * Vector2(.56,.44)
				var direction: Vector3 = rig.camera.project_ray_normal(cursor)
				var point: Vector3 = rig.camera.global_position + direction * 20.0
				_expect(rig.camera.unproject_position(point).distance_to(cursor) < .02, "reticle projection round trip")
				if "--capture" in OS.get_cmdline_user_args():
					RenderingServer.force_draw(false)
					root.get_texture().get_image().save_png(output.path_join("%s-pitch%d-yaw%d.png" % [stance,degrees,yaw_degrees]))
		print("MAIN_SOURCE_GAMEPLAY_CAMERA sampled ", stance)
		if stance in ["standing", "crouched"]:
			await _lean_proof(player, rig, stance)
		if stance == "standing" and candidate and not visual_quick:
			rig.yaw = 0.0
			rig.aim_yaw = 0.0
			rig.pitch = 0.0
			rig.aim_pitch = 0.0
			var start: Vector3 = player.global_position
			for frame in 60:
				var move := Command.new()
				move.simulation_tick = Engine.get_physics_frames()+frame
				move.move_axis = Vector2(0,-1)
				move.direction_held_mask = 1
				player.queue_movement_command(move)
			# Queue contiguous physics commands. Sending once per rendered frame
			# can inject neutral gaps, which correctly trigger gameplay tap combos.
			for frame in 60:
				await _frames(1)
				var moving: Dictionary = rig.preferred_shot_solver.source_preference()
				_expect(not moving.is_empty(),"running source preference present")
				if not moving.is_empty():
					_expect(Vector3(moving.root_source).x == 0.0 and Vector3(moving.root_source).z == 0.0,"original runtime removes horizontal root travel")
					_expect(absf((Vector3(moving.position)-player.global_position).z-2.8)<.0001,"running boom remains28source units, not raw animation travel")
				if frame in [5,30,59] and "--capture" in OS.get_cmdline_user_args():
					RenderingServer.force_draw(false)
					root.get_texture().get_image().save_png(output.path_join("running-frame%d.png" % frame))
			_expect(player.global_position.distance_to(start)>.3,"real owner advances from queued running input")
			player.global_position = start
			player.velocity = Vector3.ZERO
			await _frames(35)
			await _wall_lean_proof(player, rig, main)
	# A resize must preserve HFOV without restarting or changing aim angles.
	for viewport in [Vector2i(1280,720), Vector2i(1024,768)]:
		root.size = viewport
		await _frames(4)
		var size: Vector2 = root.get_visible_rect().size
		var horizontal := rad_to_deg(2.0*atan(tan(deg_to_rad(rig.camera.fov)*.5)*size.x/size.y))
		if candidate: _expect(absf(horizontal-rig.source_camera_match.active_horizontal_fov())<.0001, "resize HFOV")
		else: _expect(absf(rig.camera.fov-rig.profile.vertical_fov)<.0001, "resize default authored lens")
	# Capture the actual playable map too, not just the controlled open platform.
	player.call("_try_set_posture",0)
	player.global_position = gameplay_spawn
	player.velocity = Vector3.ZERO
	rig.yaw = 0.0
	rig.aim_yaw = 0.0
	rig.pitch = 0.0
	rig.aim_pitch = 0.0
	rig.reset_camera_to_target()
	await _frames(60)
	if "--capture" in OS.get_cmdline_user_args():
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(output.path_join("main-map-rifle-idle.png"))
	var file := FileAccess.open(output.path_join("measurements.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"source_default":candidate,"visual_quick":visual_quick,"framing_mode":rig.source_camera_match.settings.get("framing_mode"),"horizontal_fov_degrees":rig.source_camera_match.active_horizontal_fov(),"rows":rows,"lean_rows":lean_rows,"failures":failures,"position_parity":"Source-based hybrid constant-radius preference and existing pitch framing/collision/trailing","lens_parity":"fixed saved hybrid lens or source70HFOV mapped to viewport; original raster/zoom not claimed","visual_limits":"Level-aim head/chest visibility checked; not complete original collision or mesh parity"},"  "))
	print("MAIN_SOURCE_GAMEPLAY_CAMERA ", "PASS" if failures.is_empty() else "FAIL", " rows=",rows.size()," failures=",failures," output=",output)
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _lean_proof(player, rig, stance: String) -> void:
	rig.yaw = 0.0
	rig.aim_yaw = 0.0
	rig.pitch = 0.0
	rig.aim_pitch = 0.0
	await _frames(45)
	var baseline: Vector3 = rig.camera.global_position-player.global_position
	for state in [["left",1,-1.0],["right",2,1.0],["neutral",2,0.0]]:
		var command := Command.new()
		command.simulation_tick = Engine.get_physics_frames()
		command.peek_held_mask = state[1]
		player.queue_movement_command(command)
		var previous: Vector3 = rig.camera.global_position
		var maximum_step := 0.0
		for frame in 60:
			await _frames(1)
			maximum_step = maxf(maximum_step,previous.distance_to(rig.camera.global_position))
			previous = rig.camera.global_position
			if stance == "standing" and state[0] == "left" and frame in [5,20,59] and "--capture" in OS.get_cmdline_user_args():
				RenderingServer.force_draw(false)
				root.get_texture().get_image().save_png(output.path_join("lean-entry-frame%d.png"%frame))
		var offset: Vector3 = rig.camera.global_position-player.global_position
		var lean: float = player.get_peek_amount()
		_expect(absf(lean-float(state[2]))<.01,"real latched lean "+stance+" "+state[0])
		if float(state[2]) != 0:
			_expect((offset.x-baseline.x)*float(state[2])>.08,"rendered camera follows signed lean "+stance+" "+state[0])
		else:
			_expect(absf(offset.x-baseline.x)<.04,"neutral camera restores lateral offset "+stance)
		_expect(absf(rig.aim_yaw)<.000001 and absf(rig.aim_pitch)<.000001,"lean does not rewrite aim angles")
		lean_rows.append({"stance":stance,"state":state[0],"lean":lean,"camera_offset":str(offset),"lateral_delta":offset.x-baseline.x,"maximum_rendered_step_m":maximum_step,"aim_yaw":rig.aim_yaw,"aim_pitch":rig.aim_pitch})
		if "--capture" in OS.get_cmdline_user_args():
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png(output.path_join("%s-lean-%s.png"%[stance,state[0]]))

func _frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func _wall_lean_proof(player, rig, main: Node3D) -> void:
	var wall := StaticBody3D.new()
	wall.position = player.global_position+Vector3(0,2,2.1)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(5,4,.3)
	collider.shape = shape
	wall.add_child(collider)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	wall.add_child(mesh)
	main.add_child(wall)
	await _frames(45)
	for mask in [1,2,2]:
		var command := Command.new()
		command.peek_held_mask = mask
		command.simulation_tick = Engine.get_physics_frames()
		player.queue_movement_command(command)
		for frame in 45:
			await _frames(1)
			var query := PhysicsShapeQueryParameters3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius = rig.profile.camera_collision_radius*.95
			query.shape = sphere
			query.transform.origin = rig.camera.global_position
			query.exclude = [player.get_rid()]
			_expect(player.get_world_3d().direct_space_state.intersect_shape(query,4).is_empty(),"wall lean keeps lens volume outside solids")
			_expect(absf(rig.aim_yaw)<.000001 and absf(rig.aim_pitch)<.000001,"wall lean retains aim input")
		if "--capture" in OS.get_cmdline_user_args():
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png(output.path_join("wall-lean-%s.png"%str(snappedf(player.get_peek_amount(),.1))))
	wall.queue_free()
	await _frames(60)

func _expect(value: bool, label: String) -> void:
	if not value and not label in failures: failures.append(label)
