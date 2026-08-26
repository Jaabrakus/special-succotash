extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for _frame in range(45):
		await physics_frame
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var rig := scene.get_node_or_null("IndependentCameraRig")
	var driver := scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	_expect(player != null and rig != null and driver != null, "prone gameplay rig is live")
	if player == null or rig == null or driver == null:
		_finish()
		return

	player.global_position = Vector3(0.0, 0.05, 6.0)
	player.velocity = Vector3.ZERO
	player.call("_try_set_posture", 2)
	rig.call("set_aim_angles", 0.0, 0.0, true)
	for _frame in range(90):
		await physics_frame
	await process_frame

	_expect(StringName(player.call("get_posture_name")) == &"PRONE", "player reaches prone posture")
	_expect(StringName(driver.get("current_clip")) == &"idle_prone", "settled prone selects idle_prone")
	var animation_player := driver.get("animation_player") as AnimationPlayer
	var idle_animation := animation_player.get_animation(&"idle_prone") if animation_player else null
	var fire_animation := animation_player.get_animation(&"prone_fire") if animation_player else null
	_expect(idle_animation != null and _maximum_transform_keys(idle_animation) <= 1, "idle prone is a frozen supported pose, not a firing loop")
	_expect(fire_animation != null and _maximum_transform_keys(fire_animation) > 1, "actual prone fire keeps its authored motion")
	# Floor and barrel alignment belong to the reticle-driven Ready Aim solve.
	# Relaxed prone intentionally keeps its authored rifle carry and does not point
	# the rail at the reticle. Enter the same presentation state used by an
	# accepted shot before auditing the floor and shared-target contract.
	driver.set("requested_weapon_ready_weight", 1.0)
	driver.set("weapon_ready_weight", 1.0)
	driver.set("_fire_ready_hold_remaining", 10.0)
	for _frame in range(45):
		await physics_frame
	await process_frame

	var snapshot: Dictionary = driver.call("get_animation_debug_state")
	var pose: Dictionary = snapshot.get("weapon_pose", {})
	var ready_buttstock: Dictionary = pose.get("buttstock_constraint", {})
	var ready_pocket: Vector3 = ready_buttstock.get(
		"pocket_world_position", Vector3.ZERO
	)
	var solver: Node = driver.get("weapon_pose_solver") as Node
	var floor_clearance := float(pose.get("muzzle_floor_clearance_m", -1.0))
	print(
		"PRONE_WEAPON_FLOOR_METRIC clearance_m=%.4f lift_m=%.4f aim_error_deg=%.4f shot_blocked=%s collider=%s"
		% [
			floor_clearance,
			float(pose.get("prone_floor_lift_m", 0.0)),
			float(pose.get("weapon_aim_error_deg", 180.0)),
			str(rig.get("shot_blocked")),
			str(rig.get("shot_collider_name")),
		]
	)
	_expect(bool(pose.get("prone_floor_contact_detected", false)), "prone weapon detects the supporting floor")
	_expect(floor_clearance >= 0.075, "prone muzzle stays at least 7.5 cm above the floor")
	var minimum_arm_clearance := INF
	var skeleton := driver.get("skeleton") as Skeleton3D
	if solver != null and skeleton != null:
		for bone_name in [
			"mixamorig_LeftForeArm",
			"mixamorig_LeftHand",
			"mixamorig_RightForeArm",
			"mixamorig_RightHand",
		]:
			var bone_index := skeleton.find_bone(bone_name)
			if bone_index < 0:
				continue
			var point := skeleton.global_transform * skeleton.get_bone_global_pose(bone_index).origin
			minimum_arm_clearance = minf(
				minimum_arm_clearance,
				float(solver.call("_floor_clearance", player, point))
			)
	print("PRONE_WEAPON_ARM_METRIC minimum_clearance_m=%.4f" % minimum_arm_clearance)
	_expect(minimum_arm_clearance >= 0.045, "prone forearms and hands remain above the supporting floor")
	_expect(float(pose.get("weapon_aim_error_deg", 180.0)) <= 0.15, "prone barrel remains aligned to the reticle target")
	_expect(
		"floor" not in String(rig.get("shot_collider_name")).to_lower(),
		"level prone aim does not collide with the floor before the reticle target"
	)

	var mannequin := player.get_node_or_null("Mannequin")
	var muzzle: Node3D = mannequin.call("get_active_muzzle_marker") if mannequin else null
	var shared_target: Vector3 = rig.get("weapon_aim_point")
	if muzzle != null:
		var barrel_direction: Vector3 = mannequin.call("get_active_barrel_direction")
		var target_direction := (shared_target - muzzle.global_position).normalized()
		print(
			"PRONE_WEAPON_AIM_METRIC barrel_target_deg=%.4f barrel=%s target=%s muzzle=%s target_point=%s"
			% [
				rad_to_deg(barrel_direction.angle_to(target_direction)),
				str(barrel_direction),
				str(target_direction),
				str(muzzle.global_position),
				str(shared_target),
			]
		)
		_expect(
			rad_to_deg(barrel_direction.angle_to(target_direction)) <= 0.15,
			"visible prone rifle and authoritative target share one line"
		)
	_expect(driver.call("notify_fired"), "prone fire enters its upper-body action")
	var fire_layer = driver.get("locomotion_graph").fire_layer_node
	_expect(
		fire_layer != null
		and not fire_layer.is_path_filtered(NodePath(".:mixamorig_Spine2"))
		and not fire_layer.is_path_filtered(NodePath(".:mixamorig_RightShoulder"))
		and fire_layer.is_path_filtered(NodePath(".:mixamorig_RightArm")),
		"prone fire keeps the settled torso frame while the firing arms animate"
	)
	for _frame in range(12):
		await physics_frame
	await process_frame
	var firing_snapshot: Dictionary = driver.call("get_animation_debug_state")
	var firing_pose: Dictionary = firing_snapshot.get("weapon_pose", {})
	var firing_buttstock: Dictionary = firing_pose.get("buttstock_constraint", {})
	var firing_pocket: Vector3 = firing_buttstock.get(
		"pocket_world_position", Vector3.INF
	)
	_expect(
		bool(firing_buttstock.get("stable_reference_active", false)),
		"prone fire uses the settled chest-relative buttstock reference"
	)
	_expect(
		firing_pocket.is_finite()
		and firing_pocket.distance_to(ready_pocket) <= 0.03,
		"prone fire cannot lift the shoulder pocket with its animated shoulder"
	)
	if skeleton != null and muzzle != null:
		var head_index := skeleton.find_bone("mixamorig_Head")
		if head_index >= 0:
			var head_world := (
				skeleton.global_transform
				* skeleton.get_bone_global_pose(head_index).origin
			)
			var optic_socket := solver.get("optic_socket") as Node3D if solver != null else null
			var trigger_socket := solver.get("trigger_socket") as Node3D if solver != null else null
			var stock_socket := solver.get("stock_socket") as Node3D if solver != null else null
			print(
				"PRONE_WEAPON_FACE_METRIC head_y=%.4f stock_y=%.4f trigger_y=%.4f optic_y=%.4f muzzle_y=%.4f delta_y=%.4f"
				% [
					head_world.y,
					stock_socket.global_position.y if stock_socket != null else INF,
					trigger_socket.global_position.y if trigger_socket != null else INF,
					optic_socket.global_position.y if optic_socket != null else INF,
					muzzle.global_position.y,
					muzzle.global_position.y - head_world.y,
				]
			)
			_expect(
				trigger_socket != null
				and optic_socket != null
				and absf(trigger_socket.global_position.y - head_world.y) <= 0.08
				and optic_socket.global_position.y <= head_world.y + 0.22,
				"prone firing keeps the receiver in the face band instead of above the head"
			)
	var target_pixels: Vector2 = rig.get("camera").unproject_position(shared_target)
	var viewport_size: Vector2 = rig.get_viewport().get_visible_rect().size
	var reticle: Vector2 = rig.get("reticle_screen_normalized")
	_expect(
		target_pixels.distance_to(Vector2(reticle.x * viewport_size.x, reticle.y * viewport_size.y)) <= 2.0,
		"prone ballistic target stays on the visible reticle"
	)
	var settled_lift := float(pose.get("prone_floor_lift_m", 0.0))
	var maximum_moving_lift := settled_lift
	Input.action_press(&"move_forward")
	for _frame in range(90):
		await physics_frame
		var moving_snapshot: Dictionary = driver.call("get_animation_debug_state")
		var moving_pose: Dictionary = moving_snapshot.get("weapon_pose", {})
		maximum_moving_lift = maxf(
			maximum_moving_lift,
			float(moving_pose.get("prone_floor_lift_m", 0.0))
		)
	Input.action_release(&"move_forward")
	var final_moving_snapshot: Dictionary = driver.call("get_animation_debug_state")
	var final_moving_pose: Dictionary = final_moving_snapshot.get("weapon_pose", {})
	var final_moving_lift := float(final_moving_pose.get("prone_floor_lift_m", 0.0))
	print(
		"PRONE_WEAPON_MOVEMENT_LIFT_METRIC settled=%.4f maximum=%.4f final=%.4f"
		% [settled_lift, maximum_moving_lift, final_moving_lift]
	)
	_expect(
		maximum_moving_lift <= settled_lift + 0.05
		and final_moving_lift <= settled_lift + 0.05,
		"moving prone clearance remains bounded instead of lifting the rifle every frame"
	)

	scene.queue_free()
	await process_frame
	_finish()


func _maximum_transform_keys(animation: Animation) -> int:
	var maximum := 0
	for track in range(animation.get_track_count()):
		if animation.track_get_type(track) in [
			Animation.TYPE_POSITION_3D,
			Animation.TYPE_ROTATION_3D,
			Animation.TYPE_SCALE_3D,
		]:
			maximum = maxi(maximum, animation.track_get_key_count(track))
	return maximum


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PRONE_WEAPON_FLOOR_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("PRONE_WEAPON_FLOOR_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("PRONE_WEAPON_FLOOR_REGRESSION PASS")
		quit(0)
	else:
		print("PRONE_WEAPON_FLOOR_REGRESSION FAIL ", failures)
		quit(1)
