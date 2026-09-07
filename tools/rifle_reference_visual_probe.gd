extends SceneTree

## Canonical, input-driven rifle comparison. No animation/profile overrides.
## --weapon=ak-47|m4a1 --output-prefix=/private/tmp/rifle-before --capture
## The optional review cameras and distant flat platform are test fixtures.

var weapon_id := "ak-47"
var output_prefix := "/private/tmp/rifle-reference"
var capture := false
var require_shoulder_lock := false
var failures: Array[String] = []
var samples: Array[Dictionary] = []
var scene: Node3D
var player: CharacterBody3D
var driver: Node
var controller: Node
var camera: Camera3D


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--weapon="):
			weapon_id = argument.trim_prefix("--weapon=")
		elif argument.begins_with("--output-prefix="):
			output_prefix = argument.trim_prefix("--output-prefix=")
		elif argument == "--capture":
			capture = true
		elif argument == "--require-shoulder-lock":
			require_shoulder_lock = true
	_run.call_deferred()


func _run() -> void:
	if "--automated-test" in OS.get_cmdline_user_args():
		failures.append("--automated-test disables canonical movement input; omit it for this probe")
		_finish()
		return
	if weapon_id not in ["ak-47", "m4a1"]:
		failures.append("Only AK-47 and M4A1 are in this probe's scope")
		_finish()
		return
	if capture and DisplayServer.get_name() == "headless":
		failures.append("--capture requires a display-backed run")
		_finish()
		return
	root.size = Vector2i(1280, 800)
	DirAccess.make_dir_recursive_absolute(output_prefix.get_base_dir())
	scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await _frames(45)
	player = scene.get_node_or_null("Player") as CharacterBody3D
	controller = scene.get_node_or_null("WeaponController")
	driver = player.get_node_or_null("Mannequin/ProductionAnimation") if player else null
	if player == null or controller == null or driver == null:
		failures.append("Canonical player, weapon controller and animation driver must exist")
		_finish()
		return
	_install_fixture()
	var equipped: bool = controller.call("apply_authorized_weapon_pickup", "res://config/weapons/%s.json" % weapon_id)
	if not equipped:
		failures.append("Canonical authorized weapon handoff failed")
		_finish()
		return
	await _frames(90)
	# Map setup can finish while the weapon imports. Re-enter the already
	# registered fixture after that startup settle, then confirm grounded input.
	player.global_position = Vector3(500.0, 0.02, 500.0)
	player.velocity = Vector3.ZERO
	await _frames(36)
	for posture in [0, 1]:
		# Exercise the canonical posture/collision owner, not a visual-only stance.
		var changed: bool = player.call("_try_set_posture", posture)
		if not changed:
			failures.append("Posture %s was refused by the canonical movement owner" % posture)
		await _frames(36)
		var prefix := "standing" if posture == 0 else "crouched"
		await _sample(prefix + "_idle")
		for direction: StringName in [&"move_forward", &"move_left", &"move_right"]:
			Input.action_press(direction)
			await _frames(32)
			await _sample(prefix + "_" + String(direction))
			# A real accepted shot enters recovery while the gait continues.
			if _request_shot():
				await _frames(6)
				await _sample(prefix + "_" + String(direction) + "_fire")
			Input.action_release(direction)
			await _frames(88)
		if _request_shot():
			await _frames(1)
			await _sample(prefix + "_fire_early")
			await _frames(1)
			await _sample(prefix + "_fire_peak")
			await _frames(22)
			await _sample(prefix + "_fire_recovery")
		await _frames(90)
		await _sample(prefix + "_returned_idle")
	_finish()


func _request_shot() -> bool:
	var result: Dictionary = controller.call("request_fire")
	var accepted := bool(result.get("fired", false))
	if not accepted:
		failures.append("Canonical shot refused: %s" % JSON.stringify(result))
	return accepted


func _sample(state: String) -> void:
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var pose: Dictionary = debug.get("weapon_pose", {})
	var skeleton := driver.get("skeleton") as Skeleton3D
	var row := {
		"body_position": str(player.global_position),
		"state": state,
		"weapon": weapon_id,
		"physics_frame": Engine.get_physics_frames(),
		"current_clip": String(debug.get("logical_clip", "")),
		"source_take": String(debug.get("source_take", "")),
		"requested_action": String(driver.get("requested_action")),
		"posture": player.get("posture"),
		"motion_state": player.get("motion_state"),
		"horizontal_speed_mps": Vector2(player.velocity.x, player.velocity.z).length(),
		"spine_height_m": _height(skeleton, &"mixamorig_Spine"),
		"head_height_m": _height(skeleton, &"mixamorig_Head"),
		"trigger_contact_error_m": pose.get("trigger_hand_error_m", -1.0),
		"support_contact_error_m": pose.get("support_hand_error_m", -1.0),
		"right_elbow_angle_deg": pose.get("right_elbow_angle_deg", -1.0),
		"left_elbow_angle_deg": pose.get("left_elbow_angle_deg", -1.0),
		"weapon_aim_error_deg": pose.get("weapon_aim_error_deg", -1.0),
		"physical": _measure_physical_pose(),
		"presentation_ready_weight": debug.get("presentation_ready_weight", 0.0),
		"fire_recoil_weight": pose.get("fire_recoil_weight", -1.0),
		"weapon_owner": String(pose.get("weapon_owner", "")),
		"locomotion": driver.get("locomotion_graph").get_debug_state(),
		"fire_upper_body_latch": debug.get("fire_upper_body_latch", {}),
		"images": {},
	}
	if state.contains("_move_") and float(row.horizontal_speed_mps) < 0.5:
		failures.append("Movement sample did not actually move: " + state)
	if require_shoulder_lock and (state.ends_with("fire") or state.contains("_fire_")):
		var measured: Dictionary = row.physical
		if measured.is_empty():
			failures.append("Missing physical weapon measurements: " + state)
		else:
			if float(measured.bore_to_reticle_degrees) > 6.0:
				failures.append("Physical bore is off reticle: " + state)
			if float(measured.trigger_contact_m) > 0.01 or float(measured.support_contact_m) > 0.01:
				failures.append("Physical palm contact exceeds 1cm: " + state)
			if float(row.presentation_ready_weight) >= 0.98 and float(measured.stock_to_expected_carry_m) > 0.015:
				failures.append("Settled stock is more than 1.5cm from shoulder pocket plus authorized D release: " + state)
	if capture:
		# Draw synchronously: awaiting a scene frame while paused can advance
		# mixer source time without the matching presentation pass. That made
		# consecutive labeled stop frames skip a large part of the actual fade.
		var gameplay_camera := root.get_camera_3d()
		var prior_pause := paused
		var capture_before := _capture_invariants()
		paused = true
		# Flush existing scene presentation to its render resources. This dispatches
		# the normal dirty-pose notification, not an animation/modifier time step.
		skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		player.force_update_transform()
		(driver.get("weapon_node") as Node3D).force_update_transform()
		var focus := player.global_position + Vector3.UP * (1.10 if int(player.get("posture")) == 0 else 0.80)
		for view: String in ["rear", "side"]:
			var offset := Vector3(1.45, 0.60, 2.65) if view == "rear" else Vector3(2.85, 0.40, 0.15)
			camera.global_position = focus + player.global_basis * offset
			camera.look_at(focus)
			camera.current = true
			camera.force_update_transform()
			RenderingServer.force_sync()
			RenderingServer.force_draw(false, 0.0)
			var image := root.get_texture().get_image()
			var path := "%s-%s-%s.png" % [output_prefix, state, view]
			if image == null or image.is_empty() or image.save_png(path) != OK:
				failures.append("Capture failed: " + path)
			else:
				row.images[view] = path
		if is_instance_valid(gameplay_camera):
			gameplay_camera.make_current()
		else:
			camera.clear_current(false)
		if root.get_camera_3d() != gameplay_camera:
			failures.append("Review capture did not restore the gameplay camera: " + state)
		paused = prior_pause
		var capture_after := _capture_invariants()
		row["capture_preserved_source"] = capture_before == capture_after
		row["capture_process_frame"] = Engine.get_process_frames()
		if capture_before != capture_after:
			failures.append("Review capture advanced or changed its source pose: " + state)
	samples.append(row)
	print("RIFLE_REFERENCE_SAMPLE ", JSON.stringify(row))


func _capture_invariants() -> Dictionary:
	var skeleton := driver.get("skeleton") as Skeleton3D
	var bones: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		bones.append(skeleton.get_bone_global_pose(index))
	var pose: Node3D = driver.get("weapon_pose_solver")
	return {
		"physics_frame": Engine.get_physics_frames(),
		"process_frame": Engine.get_process_frames(),
		"player": player.global_transform,
		"velocity": player.velocity,
		"bones": bones,
		"weapon": pose.weapon_node.global_transform,
		"locomotion": driver.get("locomotion_graph").get_debug_state().duplicate(true),
		"ready": driver.get("weapon_ready_weight"),
		"presentation_ready": driver.get("_presentation_ready_weight"),
		"action": driver.get("requested_action"),
	}


func _measure_physical_pose() -> Dictionary:
	# Independent read-only geometry; diagnostic defaults are not alignment proof.
	var solver: Node = driver.get("weapon_pose_solver")
	if solver == null:
		return {}
	var muzzle := solver.get("muzzle_socket") as Node3D
	var barrel := solver.get("barrel_base_socket") as Node3D
	var stock := solver.get("stock_socket") as Node3D
	var trigger := solver.get("trigger_socket") as Node3D
	var support := solver.get("support_socket") as Node3D
	var constraint: Node = solver.get("stock_constraint")
	if muzzle == null or barrel == null or stock == null or trigger == null or support == null or constraint == null:
		return {}
	var target: Vector3 = solver.get("last_target_point")
	var forward := muzzle.global_position.direction_to(target)
	var bore := barrel.global_position.direction_to(muzzle.global_position)
	var right: Vector3 = solver.call("_bone_world_position", &"mixamorig_RightArm")
	var left: Vector3 = solver.call("_bone_world_position", &"mixamorig_LeftArm")
	var by_posture: Dictionary = constraint.get("offsets_by_posture")
	var offsets: Dictionary = by_posture.get(solver.get("last_posture"), {})
	var pocket := right + right.direction_to(left) * float(offsets.get("inward_offset_m", constraint.get("inward_offset_m")))
	pocket -= Vector3.UP * float(offsets.get("downward_offset_m", constraint.get("downward_offset_m")))
	pocket += forward * float(offsets.get("forward_offset_m", constraint.get("forward_offset_m")))
	var right_palm: Transform3D = solver.call("_right_hand_grip_world_transform")
	var left_palm: Transform3D = solver.call("_left_hand_grip_world_transform")
	var shoulder_bar := right - left
	shoulder_bar.y = 0.0
	var aim_right := forward.cross(Vector3.UP).normalized()
	var right_release: float = solver.get("authored_stock_release_applied_m")
	var release_direction: Vector3 = solver.get("authored_stock_release_direction_world")
	return {
		"shoulder_square_error_degrees": rad_to_deg(acos(clampf(absf(shoulder_bar.normalized().dot(aim_right)), 0.0, 1.0))),
		"muzzle_to_target_m": muzzle.global_position.distance_to(target),
		"aim_target_world": str(target),
		"bore_to_reticle_degrees": rad_to_deg(bore.angle_to(forward)),
		"stock_to_pocket_m": stock.global_position.distance_to(pocket),
		"stock_forward_release_m": right_release,
		"stock_to_expected_carry_m": stock.global_position.distance_to(pocket + release_direction * right_release),
		"stock_height_relative_to_pocket_m": stock.global_position.y - pocket.y,
		"trigger_contact_m": trigger.global_position.distance_to(right_palm.origin),
		"support_contact_m": support.global_position.distance_to(left_palm.origin),
		"stock_world": str(stock.global_position),
		"pocket_world": str(pocket),
	}


func _height(skeleton: Skeleton3D, bone_name: StringName) -> float:
	if skeleton == null:
		return -1.0
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return -1.0
	return (skeleton.global_transform * skeleton.get_bone_global_pose(index).origin).y - player.global_position.y


func _install_fixture() -> void:
	var floor := StaticBody3D.new()
	floor.name = "RifleReferenceFlatFixture"
	floor.position = Vector3(500.0, -0.5, 500.0)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	collision.shape = box
	floor.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.24, 0.26)
	mesh.material_override = material
	floor.add_child(mesh)
	scene.add_child(floor)
	player.global_position = Vector3(500.0, 0.02, 500.0)
	player.velocity = Vector3.ZERO
	camera = Camera3D.new()
	camera.name = "RifleReferenceReviewCamera"
	camera.fov = 42.0
	camera.set_cull_mask_value(20, false)
	scene.add_child(camera)
	var light := DirectionalLight3D.new()
	light.name = "RifleReferenceFill"
	light.rotation_degrees = Vector3(-35.0, 130.0, 0.0)
	light.light_energy = 1.5
	scene.add_child(light)
	_hide_canvas(scene)
	var visualizer := scene.find_child("CameraBoomVisualizer", true, false) as Node3D
	if visualizer:
		visualizer.visible = false


func _hide_canvas(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	for child in node.get_children():
		_hide_canvas(child)


func _frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func _finish() -> void:
	for action: StringName in [&"move_forward", &"move_left", &"move_right"]:
		Input.action_release(action)
	paused = false
	var report := {
		"canonical_scene": "res://main.tscn",
		"weapon": weapon_id,
		"capture_enabled": capture,
		"shoulder_lock_required": require_shoulder_lock,
		"samples": samples,
		"failures": failures,
		"pass": failures.is_empty(),
		"note": "Measurements are comparative evidence, not a claim of visual parity. Gameplay and saved profiles are unchanged by this tool.",
	}
	var output := FileAccess.open(output_prefix + ".json", FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	else:
		failures.append("Could not save report")
	print("RIFLE_REFERENCE_PROBE ", "PASS" if failures.is_empty() else "FAIL", " ", output_prefix, " ", failures)
	if scene:
		scene.queue_free()
	quit(0 if failures.is_empty() else 1)
