extends "res://tools/map_jump_ledge_regression.gd"

## Diagnostic only: unchanged main/map collision, real queued movement.
## Does not reinterpret a rejected climb as a passing traversal test.
var warehouse_report := {}
var capture_rows: Array = []

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	var map_path := "user://maps/active_map.json" if "--user-map" in OS.get_cmdline_user_args() else "res://config/maps/current_map.json"
	var document: Dictionary = load("res://scripts/maps/socom_map_document.gd").load_path(map_path)
	ProjectSettings.set_setting("socom/session/selected_map_document", document)
	warehouse_report["map_path"] = map_path
	print("WAREHOUSE_MAP ", map_path)
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	for frame in 90:
		await physics_frame
		await process_frame
	player = world.get_node("Player")
	player.set_local_input_enabled(false)
	world.get_node("WeaponController").set_input_enabled(false)
	if "--capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(1280,800)
		camera = Camera3D.new()
		camera.fov = 55.0
		world.add_child(camera)
	var objects := {}
	for node in world.find_children("*", "Node3D", true, false):
		var id := str(node.get_meta("map_object_id", ""))
		if id not in ["relic_014", "relic_021", "relic_024", "relic_025"]: continue
		var bounds := AABB()
		var first := true
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null: continue
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		var colliders: Array = []
		for shape: CollisionShape3D in node.find_children("*", "CollisionShape3D", true, false):
			colliders.append({"path":str(shape.get_path()), "type":shape.shape.get_class(), "disabled":shape.disabled})
		objects[id] = {"bounds":str(bounds), "colliders":colliders}
		print("WAREHOUSE_OBJECT ", id, " ", objects[id])
	warehouse_report["geometry"] = objects
	var sections: Array = []
	for x: float in [-17.6, -17.2, -16.8, -16.4, -16.18, -16.1, -15.8, -15.4, -15.0, -14.6, -14.2, -13.8, -13.4, -13.0, -12.6, -12.2]:
		var hit := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 10, 1), Vector3(x, -1, 1), player.collision_mask, [player.get_rid()]))
		sections.append({"x":x, "position":str(hit.get("position",Vector3.INF)), "normal":str(hit.get("normal",Vector3.ZERO)), "collider":str(hit.collider.get_path()) if hit.has("collider") else ""})
	warehouse_report["cross_section_z1"] = sections
	print("WAREHOUSE_SECTION ", JSON.stringify(sections))
	var capsule: CapsuleShape3D = player.get_node("CollisionShape3D").shape
	var apex_probe: Dictionary = player.traversal.mantle_motor.probe_climb(player,Vector3.LEFT,capsule.height,capsule.radius,Vector3(-15.79145,3.349498,1))
	warehouse_report["baseline_apex_query"] = apex_probe
	print("WAREHOUSE_APEX_QUERY ", apex_probe)
	_expect(bool(apex_probe.get("accepted",false)), "measured old apex rejection finds real fascia with unchanged reach")
	if not "--scan" in OS.get_cmdline_user_args():
		for sample: Dictionary in [
			{"id":"ground_z4_hold", "start":Vector3(-14.5,0.12,4), "run_frames":8},
			{"id":"container_early_z1_hold", "start":Vector3(-13.7,2.22,1), "run_frames":8},
			{"id":"container_apex_z1_second_tap", "start":Vector3(-13.7,2.22,1), "run_frames":8,"held":false,"tap_frame":18},
			{"id":"container_late_z1_hold", "start":Vector3(-14.3,2.22,1), "run_frames":8},
			{"id":"container_late_z1_second_tap", "start":Vector3(-14.3,2.22,1), "run_frames":8, "held":false,"tap_frame":4},
		]:
			if "--capture" in OS.get_cmdline_user_args() and sample.id != "container_late_z1_hold": continue
			await _warehouse_approach(sample)
	warehouse_report["approaches"] = rows
	warehouse_report["captures"] = capture_rows
	var file := FileAccess.open("/private/tmp/warehouse-awning-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(warehouse_report,"\t"))
	world.queue_free()
	await process_frame
	print("WAREHOUSE_AWNING ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _warehouse_approach(sample: Dictionary) -> void:
	direction = Vector3.LEFT
	await _reset(sample.start)
	for frame in 60: await _step()
	var settled := player.global_position
	var grounded := player.is_on_floor()
	for frame in int(sample.run_frames): await _step(false,false,false,-1)
	var launch := player.global_position
	await _capture("launch-ready")
	await _step(true,false,false,-1)
	var jumped: bool = player.velocity.y > 0 and not player.traversal.is_active()
	await _capture("jump")
	var apex := player.global_position.y
	var samples: Array = []
	var captured := false
	var shape: CapsuleShape3D = player.get_node("CollisionShape3D").shape
	for frame in 110:
		await _step(frame == int(sample.get("tap_frame",-1)),bool(sample.get("held",true)),false,-1)
		apex = maxf(apex,player.global_position.y)
		var probe: Dictionary = player.traversal.mantle_motor.probe_climb(player,direction,shape.height,shape.radius)
		if frame % 3 == 0 or bool(probe.get("accepted",false)):
			samples.append({"frame":frame,"feet":str(player.global_position),"velocity":str(player.velocity),"probe":probe,"state":player.get_traversal_presentation(),"face_samples":_face_samples(shape)})
		if player.traversal.is_active():
			captured = true
			break
	var capture_position := player.global_position
	var stable_hang := false
	var pull_up_started := false
	if captured:
		await _capture("grab-entry")
		for frame in 40: await _step()
		stable_hang = player.traversal.is_hanging()
		await _capture("hang")
		await _step(false,false,false,-1)
		pull_up_started = player.traversal.is_mantling()
		var stage := 0
		for frame in 150:
			await _step()
			var state: Dictionary = player.get_traversal_presentation()
			if stage < 3 and state.get("slot","") in ["pull_up","pull_up_free"] and float(state.get("phase",0.0)) >= [0.1,0.45,0.8][stage]:
				await _capture("pullup-"+str(stage))
				stage += 1
		await _capture("landed")
	var row := {"id":sample.id,"start":str(settled),"grounded_start":grounded,"launch":str(launch),"physical_jump":jumped,"apex_feet_y":apex,"captured":captured,"capture_position":str(capture_position),"stable_hang":stable_hang,"pull_up_started":pull_up_started,"landed":player.is_on_floor(),"still_active":player.traversal.is_active(),"end":str(player.global_position),"samples":samples}
	rows.append(row)
	print("WAREHOUSE_APPROACH ", JSON.stringify(row))
	_expect(grounded and jumped,str(sample.id)+" starts with real grounded jump")
	if str(sample.id).begins_with("ground"):
		_expect(not captured and player.is_on_floor(),"ground stays unreachable with ordinary safe landing")
	else:
		_expect(captured and stable_hang and pull_up_started,str(sample.id)+" catches, settles, and responds to fresh forward")
		_expect(player.is_on_floor() and not player.traversal.is_active() and player.global_position.y>3.8,str(sample.id)+" exits once onto supported awning")

func _face_samples(shape: CapsuleShape3D) -> Array:
	var found: Array = []
	var profile: Dictionary = player.traversal.mantle_motor.climb_profile
	for fraction: float in [0.25,0.5,0.75,0.95]:
		var origin := player.global_position + Vector3.UP * float(profile.raised_hand_reach_m) * fraction
		var hit := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,origin+direction*(shape.radius+float(profile.forward_reach_m)),player.collision_mask,[player.get_rid()]))
		found.append({"fraction":fraction,"point":str(hit.get("position",Vector3.INF)),"normal":str(hit.get("normal",Vector3.ZERO))})
	return found

func _capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await create_timer(0.0).timeout
	var output := "res://art_source/traversal_runtime_proof"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var driver := player.get_node("Mannequin/ProductionAnimation")
	var row := {"label":label,"feet":str(player.global_position),"state":player.get_traversal_presentation(),"weapon_visible":driver.weapon_node.visible,"images":[]}
	row["hand_errors_m"] = driver.traversal_hand_contact.errors_m.duplicate()
	row["evaluated_hand_weights"] = driver.traversal_hand_contact.evaluated_hand_weights.duplicate()
	row["arm_diagnostics"] = driver.traversal_hand_contact.reach_diagnostics.duplicate(true)
	var was_paused := paused
	paused = true
	for side in [-1,1]:
		camera.global_position = player.global_position + Vector3(4.0,2.2,side*2.8)
		camera.look_at(player.global_position+Vector3.UP*1.0)
		camera.make_current()
		camera.force_update_transform()
		RenderingServer.force_draw(false)
		var path := output.path_join("awning-"+label+"-side"+str(side)+".png")
		var error := root.get_texture().get_image().save_png(path)
		_expect(error==OK,"saved "+path)
		row.images.append(path)
	paused = was_paused
	capture_rows.append(row)
	print("AWNING_RENDER ",JSON.stringify(row))
