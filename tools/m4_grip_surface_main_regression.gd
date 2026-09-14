extends "res://tools/main_source_motion_proof.gd"
## Canonical equip and real movement; review cameras are observer-only.
var contact_rows: Array[Dictionary] = []
var checks := 0
var candidate_contacts := 0
var embedded_contacts := 0
var saved_profile_hash := ""

func _initialize() -> void:
	weapon_id = "m4a1"
	output_prefix = "/private/tmp/m4-grip-surface"
	super._initialize()

func _run() -> void:
	if "--automated-test" in OS.get_cmdline_user_args() or (capture and DisplayServer.get_name() == "headless"):
		failures.append("Real inputs and display-backed capture required")
		_finish()
		return
	saved_profile_hash = FileAccess.get_sha256("res://config/weapon_grip_surfaces/m4a1.tres")
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	ProjectSettings.set_setting("socom/session/public_training", true)
	root.size = Vector2i(1280, 800)
	scene = load("res://main.tscn").instantiate()
	scene.get_node("IndependentCameraRig").capture_mouse_on_ready = false
	root.add_child(scene)
	player = scene.get_node("Player")
	player.set_local_input_enabled(false)
	scene.get_node("IndependentCameraRig").orbit_input_enabled = false
	scene.get_node("IndependentCameraRig").pitch = 0.0
	scene.get_node("IndependentCameraRig").aim_pitch = 0.0
	await _frames(60)
	controller = scene.get_node("WeaponController")
	controller.set_input_enabled(false)
	driver = player.get_node("Mannequin/ProductionAnimation")
	_install_fixture()
	feeder = HeldCommandFeeder.new()
	feeder.actor = player
	feeder.process_physics_priority = -100
	scene.add_child(feeder)
	if not controller.apply_authorized_weapon_pickup("res://config/weapons/m4a1.json"):
		failures.append("M4 equip refused")
	await _frames(60)
	if driver.equipped_weapon_config.model_fbx != load("res://config/weapon_grip_surfaces/m4a1.tres").expected_model:
		# The public M4 was migrated to the ISO geometry. This prototype's legacy
		# shape must never be silently reused on the different mesh. Original
		# AGLS measurements are historical, not proof of current source contact.
		_check(not driver.weapon_node.has_node("CalibratedWeaponPivot/GripContactSurface"), "source M4 excludes AGLS surface")
		_check(not driver.weapon_node.has_meta(&"grip_surface_profile"), "source M4 has no legacy contact metadata")
		for frame in 35: await _command(Vector2.UP)
		if _request_shot(): await _frames(12)
		for result: Dictionary in driver.weapon_grip_contact.surface_results.values():
			_check(result.status == "unconfigured", "source fingers not corrected by legacy shape")
		_check(saved_profile_hash == FileAccess.get_sha256("res://config/weapon_grip_surfaces/m4a1.tres"), "legacy profile not mutated")
		print("M4_GRIP_SURFACE_MAIN ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " scope=ISO model guard; legacy 18-row probe inactive")
		_finish()
		return
	if not driver.weapon_grip_contact.source_rifle_grip or driver.weapon_grip_contact.applied_bone_count != 30:
		failures.append("Canonical rifle/finger path did not initialize; no visual conclusion")
		_finish()
		return
	_check_surface()
	for stance in [0, 1, 2]:
		player.call("_try_set_posture", stance)
		for frame in 100: await _command(Vector2.ZERO)
		_measure_contact(str(stance) + "_idle")
		if capture: await _sample(str(stance) + "_idle")
		if _request_shot():
			for frame in 32:
				await _command(Vector2.ZERO)
				if frame in [0, 8, 30]:
					var label := str(stance) + "_fire_" + str(frame)
					_measure_contact(label)
					if capture: await _sample(label)
		if stance < 2:
			for direction in [Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
				var start: Vector3 = player.global_position
				for frame in 35:
					await _command(direction)
					_check_saved_fingers()
				_check(player.global_position.distance_to(start) > .2, "canonical movement actually advances")
				_measure_contact(str(stance) + "_move_" + str(direction))
				if capture: await _sample(str(stance) + "_move_" + str(direction))
			for frame in 90: await _command(Vector2.ZERO)
	var coordinator := scene.get_node("WeaponReloadCoordinator")
	_check(coordinator.request_reload(), "canonical reload accepted")
	var free_frames := 0
	for frame in 160:
		await _command(Vector2.ZERO)
		if driver.requested_action != &"":
			free_frames += 1
			if not driver.weapon_grip_contact.surface_results.is_empty():
				print("RELOAD_CONTACT_FRAME ", frame, " action=", driver.requested_action, " clip=", driver.current_clip,
					" owner=", driver.weapon_pose_solver.get_weapon_presentation_owner_state(), " source=", driver.source_rifle_attachment)
			_check(driver.weapon_grip_contact.surface_results.is_empty(), "animation-free reload hand not constrained")
	_check(free_frames > 10, "reload animation actually played")
	_check_surface()
	_check_saved_fingers()
	for id in ["ak-47", "mark_23", "m4a1"]:
		var old_weapon: Node3D = driver.weapon_node
		_check(controller.apply_authorized_weapon_pickup("res://config/weapons/" + id + ".json"), "equip " + id)
		await _frames(45)
		_check(not is_instance_valid(old_weapon), "old weapon and surface released " + id)
		if id == "m4a1": _check_surface()
		else: _check(not driver.weapon_node.has_node("CalibratedWeaponPivot/GripContactSurface"), "other guns untouched " + id)
	_check(candidate_contacts > 0, "contact geometry produced candidate boundary")
	_check(embedded_contacts > 0, "existing penetration remains diagnosed, not concealed")
	_check(saved_profile_hash == FileAccess.get_sha256("res://config/weapon_grip_surfaces/m4a1.tres"), "test did not mutate saved profile")
	var file := FileAccess.open(output_prefix + "-contact.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": contact_rows, "failures": failures, "checks": checks,
		"scope": "Saved observation-only prototype; contact correction not visually accepted",
		"candidate_contacts": candidate_contacts, "embedded_contacts": embedded_contacts}, "\t"))
	file.close()
	print("M4_GRIP_SURFACE_MAIN ", "PASS" if failures.is_empty() else "FAIL", " rows=", contact_rows.size(), " checks=", checks)
	_finish()

func _measure_contact(label: String) -> void:
	_check_saved_fingers()
	var sk: Skeleton3D = driver.skeleton
	var pivot: Node3D = driver.weapon_node.get_node("CalibratedWeaponPivot")
	var row := {"label": label, "grip": driver.weapon_grip_contact.snapshot(), "fingers": {}}
	for finger: String in ["Index", "Middle", "Ring", "Pinky", "Thumb"]:
		var points := []
		for segment in [1, 2, 3]:
			var index := sk.find_bone("mixamorig_LeftHand" + finger + str(segment))
			var point: Vector3 = pivot.to_local(sk.global_transform * sk.get_bone_global_pose(index).origin)
			points.append([point.x, point.y, point.z])
		row.fingers[finger] = points
	row["mesh_bounds"] = _mesh_slice(pivot.get_node("WeaponMesh"), pivot)
	for result: Dictionary in driver.weapon_grip_contact.surface_results.values():
		if result.status == "contact_limited": candidate_contacts += 1
		if result.status == "embedded_open_pose": embedded_contacts += 1
	contact_rows.append(row)
	print("CONTACT_OBSERVATION ", JSON.stringify(row))

func _check_surface() -> void:
	var area := driver.weapon_node.get_node_or_null("CalibratedWeaponPivot/GripContactSurface") as Area3D
	_check(area != null, "saved M4 shape attached through canonical owner")
	if area == null: return
	_check(area.collision_layer == 0 and area.collision_mask == 0 and not area.monitoring and not area.monitorable,
		"surface excluded from gameplay queries and physics")
	var collider := area.get_node("ForeEnd") as CollisionShape3D
	_check(collider.shape is CapsuleShape3D, "real Godot shape resource")
	var query := PhysicsRayQueryParameters3D.create(collider.global_position + Vector3.UP,
		collider.global_position - Vector3.UP)
	query.collide_with_areas = true
	var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
	_check(hit.get("collider") != area, "shot-style ray cannot hit presentation surface")

func _check_saved_fingers() -> void:
	var grip = driver.weapon_grip_contact
	_check(grip.source_rifle_grip and grip.applied_left and grip.applied_bone_count == 30, "source hand owner active")
	_check(grip.surface_results.size() == 4, "four support probes only")
	for result: Dictionary in grip.surface_results.values():
		_check(not bool(result.get("correction_enabled", true)) and is_equal_approx(result.curl, .72), "saved correction disabled")
	var sk: Skeleton3D = driver.skeleton
	for finger: String in ["Index", "Middle", "Ring", "Pinky"]:
		for segment in [1,2,3]:
			var index := sk.find_bone("mixamorig_LeftHand" + finger + str(segment))
			var parent := sk.get_bone_parent(index)
			var local := sk.get_bone_global_pose(parent).basis.inverse() * sk.get_bone_global_pose(index).basis
			var expected := sk.get_bone_rest(index).basis.orthonormalized() * Basis(Vector3.RIGHT, deg_to_rad([55.,75.,45.][segment-1] * .72))
			_check(local.orthonormalized().get_rotation_quaternion().angle_to(expected.get_rotation_quaternion()) < .002,
				"observation cannot alter authored finger pose")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not message in failures: failures.append(message)

func _mesh_slice(node: Node, pivot: Node3D) -> Dictionary:
	var points := PackedVector3Array()
	_collect_vertices(node, pivot, points)
	var low := Vector3(INF, INF, INF)
	var high := -low
	var count := 0
	for point in points:
		if point.z < .26 or point.z > .37: continue
		low = low.min(point)
		high = high.max(point)
		count += 1
	return {"min": str(low), "max": str(high), "vertices": count}

func _collect_vertices(node: Node, pivot: Node3D, points: PackedVector3Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var relative: Transform3D = pivot.global_transform.affine_inverse() * node.global_transform
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]: points.append(relative * point)
	for child in node.get_children(): _collect_vertices(child, pivot, points)
