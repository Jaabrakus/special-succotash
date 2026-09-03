extends SceneTree

## Validates the visual weapon-pose layer against the shared camera aim target.
## The checks intentionally use the complete game scene so imported scale,
## stance changes, camera ownership and the multiplayer-safe CharacterBody
## boundary are all present.

const WeaponOwnershipContract := preload(
	"res://scripts/player/weapon_ownership_contract.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_weapon_ownership_contract()
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _steps(45)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var rig := scene.get_node_or_null("IndependentCameraRig")
	var driver = scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	_expect(player != null, "authoritative CharacterBody exists")
	_expect(rig != null, "shared camera aim source exists")
	_expect(driver != null, "65-bone visual driver exists")
	if player == null or rig == null or driver == null:
		_finish()
		return
	var initial_debug_pose: Dictionary = driver.call(
		"get_animation_debug_state"
	).get("weapon_pose", {})
	if bool(initial_debug_pose.get("authored_animation_owns_weapon_mount", false)):
		await _check_authored_animation_mount(player, rig, driver)
		_finish()
		return

	# This regression audits the reticle-driven Ready Aim solver. Normal
	# gameplay intentionally starts at relaxed rifle carry and enters Ready Aim
	# after aim/fire intent, so make that presentation input explicit here.
	driver.set("requested_weapon_ready_weight", 1.0)
	driver.set("weapon_ready_weight", 1.0)
	# The production mannequin intentionally supplies a zero manual-ready input;
	# accepted fire owns the temporary Ready Aim hold. Keep that real semantic
	# state active for the complete stance/locomotion audit.
	driver.set("_fire_ready_hold_remaining", 10.0)
	await _steps(3)

	_check_pose("standing center", driver, rig)
	var standing_center_pose: Dictionary = driver.call(
		"get_animation_debug_state"
	).get("weapon_pose", {})
	var stock_state: Dictionary = standing_center_pose.get("buttstock_constraint", {})
	_expect(
		bool(stock_state.get("active", false))
		and StringName(stock_state.get("socket", &"")) == &"Socket_Buttstock",
		"ready rifle uses the hierarchical buttstock-to-shoulder contract"
	)
	_expect(
		float(stock_state.get("contact_error_m", 1.0)) <= 0.025,
		"buttstock remains within 2.5 cm of the right shoulder pocket"
	)
	var stock_solver := driver.get("weapon_pose_solver") as Node
	var stock_component := (
		stock_solver.get_node_or_null("ButtstockConstraint")
		if stock_solver != null
		else null
	)
	_expect(
		stock_component != null
		and stock_solver.get_parent().name == "40_WeaponMuzzleAlignment"
		and stock_component.get_node_or_null("RightShoulderPocket") != null,
		"buttstock constraint and shoulder pocket exist in the pose node hierarchy"
	)
	_expect(
		StringName(standing_center_pose.get("weapon_owner", &"")) == &"READY_SOLVER"
		and StringName(standing_center_pose.get("arm_owner", &"")) == &"WEAPON_SOCKETS",
		"standing Aim Idle has one explicit weapon-and-socket owner"
	)
	var standing_center_weapon_position: Vector3 = standing_center_pose.get(
		"weapon_world_position",
		Vector3.ZERO
	)
	var standing_center_root_yaw := player.global_rotation.y
	rig.call("set_aim_angles", deg_to_rad(28.0), deg_to_rad(-12.0), true)
	await _steps(30)
	_check_pose("standing lateral/down", driver, rig)
	var standing_turned_pose: Dictionary = driver.call(
		"get_animation_debug_state"
	).get("weapon_pose", {})
	var standing_turned_weapon_position: Vector3 = standing_turned_pose.get(
		"weapon_world_position",
		Vector3.ZERO
	)
	var standing_turn_travel := standing_center_weapon_position.distance_to(
		standing_turned_weapon_position
	)
	print("STANDING_TORSO_ANCHOR_METRIC root_turn=%.3f weapon_travel=%.4f frame=%s" % [
		rad_to_deg(angle_difference(standing_center_root_yaw, player.global_rotation.y)),
		standing_turn_travel,
		str(standing_turned_pose.get("gun_placement_frame_bone", &"")),
	])
	_expect(
		StringName(standing_turned_pose.get("gun_placement_frame_bone", &""))
		== &"mixamorig_Spine2",
		"standing rifle placement is attached to the upper-chest frame"
	)
	_expect(
		standing_turn_travel >= 0.02,
		"planted torso turn carries the rifle instead of leaving it world-pinned"
	)

	# A locomotion clip is allowed to move the rendered chest, but the saved
	# Gunsmith line used to leave the rifle fixed in the player's root space.
	# Sample one gait cycle and require a small, bounded visual carry instead of
	# the stretched-arm/world-pinned result. Gameplay aim remains checked below.
	# Audit gait carry on an unobstructed long sightline. The centered Training
	# Range ray hits a wall only 2.85 m ahead; running toward that fixed point
	# rotates the rifle sharply upward and is target tracking, not gait bob.
	rig.call("set_aim_angles", 0.0, deg_to_rad(18.0), true)
	await _steps(24)
	var locomotion_start_position := player.global_position
	var minimum_relative_weapon_y := INF
	var maximum_relative_weapon_y := -INF
	var maximum_locomotion_carry := 0.0
	var maximum_vertical_weapon_carry := 0.0
	var maximum_horizontal_weapon_carry := 0.0
	var locomotion_solver_active_observed := false
	var minimum_upper_ready_blend := INF
	var observed_locomotion_clips: Dictionary = {}
	var maximum_support_grip_rotation_error_deg := 0.0
	var support_grip_locked_during_locomotion := true
	Input.action_press(&"move_forward")
	# Let the start/turn transition settle before measuring the repeating gait.
	# Transition travel is validated separately above; this block audits bob.
	await _steps(24)
	var neutral_pose: Dictionary = driver.call(
		"get_animation_debug_state"
	).get("weapon_pose", {})
	var neutral_weapon_local := player.to_local(
		Vector3(neutral_pose.get("trigger_hand_position", Vector3.ZERO))
	)
	for _frame in range(72):
		await physics_frame
		# Character motion is authoritative in physics; the visual rifle follows in
		# the subsequent presentation frame. Sample after both have completed.
		await process_frame
		var moving_snapshot: Dictionary = driver.call("get_animation_debug_state")
		var moving_pose: Dictionary = moving_snapshot.get("weapon_pose", {})
		if not bool(moving_snapshot.get("locomotion_active", false)):
			continue
		locomotion_solver_active_observed = (
			locomotion_solver_active_observed
			or bool(moving_pose.get("gun_placement_locomotion_active", false))
		)
		minimum_upper_ready_blend = minf(
			minimum_upper_ready_blend,
			float(moving_snapshot.get("upper_body_ready_blend", -1.0))
		)
		observed_locomotion_clips[String(moving_snapshot.get("logical_clip", ""))] = true
		var moving_weapon_world: Vector3 = moving_pose.get(
			"trigger_hand_position",
			Vector3.ZERO
		)
		var moving_weapon_local := player.to_local(moving_weapon_world)
		minimum_relative_weapon_y = minf(minimum_relative_weapon_y, moving_weapon_local.y)
		maximum_relative_weapon_y = maxf(maximum_relative_weapon_y, moving_weapon_local.y)
		var locomotion_carry := moving_weapon_local - neutral_weapon_local
		maximum_locomotion_carry = maxf(
			maximum_locomotion_carry,
			locomotion_carry.length()
		)
		maximum_vertical_weapon_carry = maxf(
			maximum_vertical_weapon_carry,
			absf(locomotion_carry.y)
		)
		maximum_horizontal_weapon_carry = maxf(
			maximum_horizontal_weapon_carry,
			Vector2(locomotion_carry.x, locomotion_carry.z).length()
		)
		maximum_support_grip_rotation_error_deg = maxf(
			maximum_support_grip_rotation_error_deg,
			float(moving_pose.get("support_hand_grip_rotation_error_deg", 180.0))
		)
		support_grip_locked_during_locomotion = (
			support_grip_locked_during_locomotion
			and bool(moving_pose.get("support_hand_grip_locked", false))
		)
	Input.action_release(&"move_forward")
	player.global_position = locomotion_start_position
	player.velocity = Vector3.ZERO
	rig.call("set_aim_angles", deg_to_rad(28.0), deg_to_rad(-12.0), true)
	await _steps(24)
	var locomotion_weapon_travel := maximum_relative_weapon_y - minimum_relative_weapon_y
	print("STANDING_LOCOMOTION_WEAPON_CARRY_METRIC weapon_y_travel=%.4f max_carry=%.4f vertical=%.4f horizontal=%.4f solver_active=%s upper_ready=%.3f clips=%s" % [
		locomotion_weapon_travel,
		maximum_locomotion_carry,
		maximum_vertical_weapon_carry,
		maximum_horizontal_weapon_carry,
		str(locomotion_solver_active_observed),
		minimum_upper_ready_blend,
		str(observed_locomotion_clips.keys()),
	])
	_expect(
		locomotion_weapon_travel >= 0.003,
		"standing locomotion carries the rifle with the animated chest"
	)
	_expect(
		maximum_locomotion_carry >= 0.001,
		"standing locomotion produces measurable shoulder-driven rifle travel"
	)
	_expect(
		maximum_locomotion_carry <= 0.07,
		"standing locomotion rifle carry remains visually bounded"
	)
	_expect(
		maximum_vertical_weapon_carry >= 0.001
		and maximum_vertical_weapon_carry <= 0.060,
		"shouldered standing rifle follows bounded vertical shoulder travel"
	)
	_expect(
		maximum_horizontal_weapon_carry <= 0.030,
		"standing rifle bob does not become broad lateral sway"
	)
	_expect(
		support_grip_locked_during_locomotion
		and maximum_support_grip_rotation_error_deg <= 0.5,
		"standing support hand stays locked to the rifle grip during locomotion"
	)
	await _tap(&"crouch")
	driver.set("requested_weapon_ready_weight", 1.0)
	driver.set("weapon_ready_weight", 1.0)
	await _steps(30)
	_check_pose("crouched lateral/down", driver, rig)

	await _hold(&"crouch", 16)
	_expect(
		StringName(player.call("get_posture_name")) == &"PRONE",
		"hold-to-stance enters the real prone posture"
	)
	driver.set("requested_weapon_ready_weight", 1.0)
	driver.set("weapon_ready_weight", 1.0)
	await _steps(45)
	_check_pose("prone lateral/down", driver, rig)

	var solver = driver.get("weapon_pose_solver")
	_expect(solver != null, "weapon-pose solver is installed")
	if solver != null:
		var initial_pose: Dictionary = solver.call("get_debug_state")
		_expect(
			bool(initial_pose.get("socket_contract_active", false)),
			"production rifle exposes trigger, support, and muzzle sockets"
		)
		var before_position := player.global_position
		var before_velocity := player.velocity
		var before_target: Vector3 = rig.get("weapon_aim_point")
		# Isolate the presentation consumer from the live camera update. Waiting
		# several scene frames here lets the camera legitimately reacquire a new
		# world hit point and falsely attributes that movement to the arm solver.
		driver.set_process(false)
		solver.call(
			"apply",
			float(rig.get("aim_yaw")),
			float(rig.get("aim_pitch")),
			&"PRONE",
			&"LOCOMOTION",
			1.0,
			0.0,
			&"",
			false,
			before_target,
			player,
			1.0 / 60.0
		)
		_expect(
			player.global_position.distance_to(before_position) < 0.001,
			"visual arm solver never moves the authoritative player"
		)
		_expect(
			player.velocity.distance_to(before_velocity) < 0.001,
			"visual arm solver never changes authoritative velocity"
		)
		_expect(
			Vector3(rig.get("weapon_aim_point")).distance_to(before_target) < 0.01,
			"visual arm solver never rewrites shared aim authority"
		)

		# Force the visual solver into a close-cover pose without changing the
		# gameplay target. This isolates the obstruction contract from whichever
		# lab wall the centered camera ray currently selected.
		solver.call(
			"apply",
			0.0,
			float(rig.get("aim_pitch")),
			&"STANDING",
			&"AIRBORNE",
			1.0,
			0.0,
			&"",
			false,
			before_target,
			player,
			1.0 / 60.0
		)
		var airborne_pose: Dictionary = solver.call("get_debug_state")
		_expect(
			bool(airborne_pose.get("active", false))
			and not bool(airborne_pose.get("action_weapon_follow_active", true))
			and StringName(airborne_pose.get("weapon_owner", &"")) == &"READY_SOLVER",
			"jump keeps the reticle/Gunsmith weapon solver in control"
		)
		for _frame in range(8):
			solver.call(
				"apply",
				0.0,
				float(rig.get("aim_pitch")),
				&"STANDING",
				&"DIVING",
				1.0,
				0.0,
				&"",
				false,
				before_target,
				player,
				1.0 / 60.0
			)
		var dive_follow_pose: Dictionary = solver.call("get_debug_state")
		print("DIVE_CARRY_METRIC active=%s follow=%s chest=%s owner=%s arm=%s support=%s support_lock=%s trigger_error=%.5f swing=%.3f" % [
			str(dive_follow_pose.get("active", true)),
			str(dive_follow_pose.get("action_weapon_follow_active", false)),
			str(dive_follow_pose.get("action_weapon_chest_owned", false)),
			String(dive_follow_pose.get("weapon_owner", &"")),
			String(dive_follow_pose.get("arm_owner", &"")),
			String(dive_follow_pose.get("support_hand_mode", &"")),
			str(dive_follow_pose.get("support_hand_grip_locked", false)),
			float(dive_follow_pose.get("action_trigger_contact_error_m", 1.0)),
			float(dive_follow_pose.get("action_weapon_swing_deg", 180.0)),
		])
		_expect(
			not bool(dive_follow_pose.get("active", true))
			and bool(dive_follow_pose.get("action_weapon_follow_active", false))
			and bool(dive_follow_pose.get("action_weapon_chest_owned", false))
			and StringName(dive_follow_pose.get("weapon_owner", &""))
				== &"MOBILITY_CHEST_CARRY"
				and StringName(dive_follow_pose.get("arm_owner", &"")) == &"WEAPON_SOCKETS"
				and StringName(dive_follow_pose.get("support_hand_mode", &""))
				== &"IK_TO_WEAPON"
				and bool(dive_follow_pose.get("support_hand_grip_locked", false))
			# This isolated solver check intentionally leaves the skeleton in the
			# preceding prone sample. The real gameplay dive regression enforces the
			# stricter 1.5 cm socket contact across the sampled action.
			and float(dive_follow_pose.get("action_trigger_contact_error_m", 1.0))
			<= 0.10
			and float(dive_follow_pose.get("action_weapon_swing_deg", 180.0)) <= 95.0,
			"dive keeps the full-body take while chest-owned rifle sockets drive both palms"
		)
		for _frame in range(24):
			solver.call(
				"apply",
				0.0,
				float(rig.get("aim_pitch")),
				&"STANDING",
				&"LOCOMOTION",
				1.0,
				0.0,
				&"",
				false,
				before_target,
				player,
				1.0 / 60.0
			)
		var dive_recovered_pose: Dictionary = solver.call("get_debug_state")
		print("DIVE_RECOVERY_METRIC owner=%s line_error=%.4f solver_owned=%s parent_mount=%s" % [
			str(dive_recovered_pose.get("weapon_owner", &"")),
			float(dive_recovered_pose.get("gun_placement_error_m", 0.0)),
			str(dive_recovered_pose.get("weapon_solver_owned", false)),
			str(dive_recovered_pose.get("weapon_parent_is_animation_mount", false)),
		])
		_expect(
			not bool(dive_recovered_pose.get("action_weapon_follow_active", true))
			and float(dive_recovered_pose.get("gun_placement_error_m", 1.0)) <= 0.001
			and StringName(dive_recovered_pose.get("weapon_owner", &"")) == &"READY_SOLVER",
			"dive recovery returns to the exact saved Gunsmith placement"
		)
		var clearance_muzzle := solver.get("muzzle_socket") as Node3D
		for _frame in range(18):
			solver.call(
				"apply",
				0.0,
				float(rig.get("aim_pitch")),
				&"CROUCHED",
				&"CROUCHED",
				1.0,
				0.0,
				&"",
				false,
				before_target,
				player,
				1.0 / 60.0,
				false
			)
		var clearance_muzzle_before_y := (
			clearance_muzzle.global_position.y if clearance_muzzle != null else 0.0
		)
		for _frame in range(18):
			solver.call(
				"apply",
				1.0,
				float(rig.get("aim_pitch")),
				&"CROUCHED",
				&"CROUCHED",
				1.0,
				0.0,
				&"",
				false,
				before_target,
				player,
				1.0 / 60.0,
				false
			)
		var clearance_pose: Dictionary = solver.call("get_debug_state")
		var clearance_muzzle_lift := (
			clearance_muzzle.global_position.y - clearance_muzzle_before_y
			if clearance_muzzle != null
			else 0.0
		)
		print("CROUCHED_OBSTRUCTION_HEIGHT_METRIC muzzle_lift=%.3f" % [
			clearance_muzzle_lift,
		])
		_expect(
			absf(clearance_muzzle_lift) <= 0.03,
			"crouched obstruction never lifts the rifle or arms toward cover"
		)
		_expect(
			Vector3(clearance_pose.get("aim_target", Vector3.ZERO)).distance_to(before_target)
			<= 0.001,
			"crouched obstruction keeps the blue line on the unchanged reticle target"
		)
		_expect(
			player.global_position.distance_to(before_position) <= 0.001,
			"crouched obstruction never changes authoritative player position"
		)
		var clear_render_direction: Vector3 = dive_recovered_pose.get(
			"last_unobstructed_render_direction",
			Vector3.FORWARD
		)
		var solver_muzzle := solver.get("muzzle_socket") as Node3D
		var pathological_wall_target := (
			solver_muzzle.global_position - clear_render_direction * 0.25
			if solver_muzzle != null
			else player.global_position - clear_render_direction * 0.25
		)
		# Let the bounded low-ready transition start, then measure only successive
		# obstructed frames. The clear-to-blocked pose change is intentional; a
		# near-180-degree reversal between blocked frames is the regression.
		solver.call(
			"apply",
			0.0,
			float(rig.get("aim_pitch")),
			&"STANDING",
			&"LOCOMOTION",
			1.0,
			1.0,
			&"",
			false,
			pathological_wall_target,
			player,
			1.0 / 60.0
		)
		var first_wall_pose: Dictionary = solver.call("get_debug_state")
		var previous_blocked_direction: Vector3 = first_wall_pose.get(
			"gun_placement_direction",
			clear_render_direction
		)
		var maximum_blocked_direction_step_deg := 0.0
		for _frame in range(24):
			solver.call(
				"apply",
				0.0,
				float(rig.get("aim_pitch")),
				&"STANDING",
				&"LOCOMOTION",
				1.0,
				1.0,
				&"",
				false,
				pathological_wall_target,
				player,
				1.0 / 60.0
			)
			var wall_pose: Dictionary = solver.call("get_debug_state")
			var blocked_direction: Vector3 = wall_pose.get(
				"gun_placement_direction",
				previous_blocked_direction
			)
			if (
				blocked_direction.length_squared() > 0.50
				and previous_blocked_direction.length_squared() > 0.50
			):
				maximum_blocked_direction_step_deg = maxf(
					maximum_blocked_direction_step_deg,
					rad_to_deg(previous_blocked_direction.angle_to(blocked_direction))
				)
			previous_blocked_direction = blocked_direction
		var wall_hold_pose: Dictionary = solver.call("get_debug_state")
		print("WALL_HOLD_METRIC owner=%s weight=%.3f ready=%.3f line_active=%s" % [
			str(wall_hold_pose.get("weapon_owner", &"")),
			float(wall_hold_pose.get("weight", 0.0)),
			float(wall_hold_pose.get("desired_weight", 0.0)),
			str(wall_hold_pose.get("gun_placement_line_active", false)),
		])
		_expect(
			not bool(wall_hold_pose.get("obstruction_direction_hold_active", true)),
			"close wall cannot take control of the visual aim direction"
		)
		_expect(
			StringName(wall_hold_pose.get("weapon_owner", &"")) == &"READY_SOLVER",
			"close wall keeps the ready solver as the only weapon owner"
		)
		_expect(
			maximum_blocked_direction_step_deg <= 6.0,
			"close-wall rifle direction cannot flip or spin chaotically"
		)
		for _frame in range(24):
			solver.call(
				"apply",
				0.0,
				float(rig.get("aim_pitch")),
				&"PRONE",
				&"PRONE",
				1.0,
				1.0,
				&"",
				false,
				before_target,
				player,
				1.0 / 60.0
			)
		var blocked_pose: Dictionary = solver.call("get_debug_state")
		_expect(
			not bool(blocked_pose.get("shot_blocked", true)),
			"close cover does not create a presentation-owned blocked state"
		)
		_expect(
			StringName(blocked_pose.get("cover_pose_name", &"")) == &"CLEAR",
			"prone close cover leaves the authored pose clear"
		)
		_expect(
			float(blocked_pose.get("weapon_aim_error_deg", 180.0)) <= 0.10,
			"cover detection cannot redirect the rifle away from shared aim"
		)
		_expect(
			Vector3(blocked_pose.get("aim_target", Vector3.ZERO)).distance_to(before_target) < 0.001,
			"cover pose preserves the shared reticle target"
		)
		_expect(
			player.global_position.distance_to(before_position) < 0.001,
			"cover pose never pushes the authoritative player"
		)
		for _frame in range(36):
			solver.call(
				"apply",
				0.0,
				float(rig.get("aim_pitch")),
				&"PRONE",
				&"PRONE",
				1.0,
				0.0,
				&"",
				false,
				before_target,
				player,
				1.0 / 60.0
			)
		var recovered_pose: Dictionary = solver.call("get_debug_state")
		_expect(not bool(recovered_pose.get("shot_blocked", true)), "weapon recovers from cover without a stuck state")
		_expect(
			float(recovered_pose.get("weapon_aim_error_deg", 180.0)) <= 0.10,
			"clear weapon returns to the shared reticle ray"
		)
		driver.set_process(true)

	await _tap(&"crouch")
	await _steps(30)
	_expect(
		StringName(player.call("get_posture_name")) == &"CROUCHED",
		"reload anatomy check returns from prone to crouched"
	)
	await _check_crouched_reload_anatomy(driver)

	scene.queue_free()
	_finish()


func _check_weapon_ownership_contract() -> void:
	_expect(
		WeaponOwnershipContract.resolve(&"STANDING", &"", 1.0, false)
		== WeaponOwnershipContract.READY_SOLVER,
		"ownership contract gives Aim Idle to the ready solver"
	)
	_expect(
		WeaponOwnershipContract.resolve(&"DIVING", &"reload_standing", 1.0, false)
		== WeaponOwnershipContract.RELOAD_RIGHT_HAND,
		"reload right hand has deterministic priority over movement state"
	)
	_expect(
		WeaponOwnershipContract.resolve(&"STANDING", &"grenade_throw", 1.0, false)
		== WeaponOwnershipContract.GRENADE_ACTION,
		"grenade take owns its arms without inheriting rifle IK"
	)
	_expect(
		WeaponOwnershipContract.resolve(&"ROLLING", &"", 1.0, false)
			== WeaponOwnershipContract.MOBILITY_CHEST_CARRY,
		"dive and roll give the authored take one stable chest rifle owner"
	)
	_expect(
		WeaponOwnershipContract.resolve(&"STANDING", &"", 1.0, true)
		== WeaponOwnershipContract.RECOVERY_TO_READY,
		"action exit enters recovery before Aim Idle retakes ownership"
	)
	_expect(
		WeaponOwnershipContract.support_hand_owner(
			WeaponOwnershipContract.MOBILITY_CHEST_CARRY,
			false
		) == WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON,
		"mobility solves the support palm to the chest-owned rifle"
	)


func _check_pose(label: String, driver: Node, rig: Node) -> void:
	var snapshot: Dictionary = driver.call("get_animation_debug_state")
	var pose: Dictionary = snapshot.get("weapon_pose", {})
	if label.begins_with("standing"):
		print("STANDING_GUN_PLACEMENT_METRIC label=%s right_angle=%.2f left_angle=%.2f trigger_error=%.4f support_error=%.4f aim_error=%.2f hip_roll=%.2f hip_input=%.2f hip_trim=%.2f line_error=%.4f trigger=(%s) trigger_target=(%s) support=(%s) support_target=(%s)" % [
			label,
			float(pose.get("right_elbow_angle_deg", 0.0)),
			float(pose.get("left_elbow_angle_deg", 0.0)),
			float(pose.get("trigger_hand_error_m", 0.0)),
			float(pose.get("support_hand_error_m", 0.0)),
			float(pose.get("weapon_aim_error_deg", 0.0)),
			float(snapshot.get("default_hip_roll_output_deg", 0.0)),
			float(snapshot.get("default_hip_roll_input_deg", 0.0)),
			float(snapshot.get("default_hip_roll_trim_deg", 0.0)),
			float(pose.get("gun_placement_error_m", 0.0)),
			str(pose.get("trigger_hand_position", Vector3.ZERO)),
			str(pose.get("trigger_hand_target", Vector3.ZERO)),
			str(pose.get("support_hand_position", Vector3.ZERO)),
			str(pose.get("support_hand_target", Vector3.ZERO)),
		])
	if label.begins_with("prone"):
		var right_elbow: Vector3 = pose.get("right_elbow_position", Vector3.ZERO)
		var left_elbow: Vector3 = pose.get("left_elbow_position", Vector3.ZERO)
		var head: Vector3 = pose.get("head_position", Vector3.ZERO)
		print(
			"PRONE_ARM_METRIC right_angle=%.2f left_angle=%.2f right_elbow=(%s) left_elbow=(%s) head=(%s) trigger=(%s) support=(%s) floor_lift=%.3f"
			% [
				float(pose.get("right_elbow_angle_deg", 0.0)),
				float(pose.get("left_elbow_angle_deg", 0.0)),
				str(pose.get("right_elbow_position", Vector3.ZERO)),
				str(pose.get("left_elbow_position", Vector3.ZERO)),
				str(pose.get("head_position", Vector3.ZERO)),
				str(pose.get("trigger_hand_position", Vector3.ZERO)),
				str(pose.get("support_hand_position", Vector3.ZERO)),
				float(pose.get("prone_floor_lift_m", 0.0)),
			]
		)
		_expect(
			absf(right_elbow.x - head.x) >= 0.12,
			"%s firing elbow stays outside the head silhouette" % label
		)
		_expect(
			absf(left_elbow.x - head.x) >= 0.20,
			"%s support elbow stays outside the head silhouette" % label
		)
		_expect(
			float(pose.get("left_elbow_angle_deg", 180.0)) <= 145.0,
			"%s support arm keeps a natural bend" % label
		)
	_expect(bool(pose.get("active", false)), "%s weapon pose is active" % label)
	_expect(
		float(pose.get("trigger_hand_error_m", 1.0)) <= 0.005,
		"%s trigger hand reaches within 0.5 cm" % label
	)
	var support_error := float(pose.get("support_hand_error_m", 1.0))
	_expect(
		support_error <= 0.005,
		"%s support hand reaches within 0.5 cm (%.2f cm)" % [
			label,
			support_error * 100.0,
		]
	)
	_expect(
		float(pose.get("weapon_aim_error_deg", 180.0)) <= 0.10,
		"%s rendered rifle follows the shared reticle ray" % label
	)
	_expect(
		float(snapshot.get("shoulder_square_error_deg", 180.0)) <= 10.0,
		"%s shoulder bar remains square to authoritative aim" % label
	)
	_expect(
		float(snapshot.get("shoulder_level_error_cm", 100.0)) <= 4.0,
		"%s shoulder bar remains level within 4 cm" % label
	)
	if label.begins_with("standing"):
		_expect(
			absf(float(snapshot.get("default_hip_roll_output_deg", 180.0))) <= 0.10,
			"%s idle hips return to the square reference" % label
		)
	if bool(pose.get("gun_placement_line_active", false)):
		_expect(
			bool(pose.get("gun_placement_baseline_active", false)),
			"%s starts live aim from the saved Gunsmith ready rotation" % label
		)
		_expect(
			float(pose.get("gun_placement_error_m", 1.0)) <= 0.001,
			"%s optic stays on the exact saved Gunsmith placement" % label
		)
		_expect(
			float(pose.get("gun_placement_roll_error_deg", 180.0)) <= 0.10,
			"%s weapon rail stays upright instead of rolling sideways" % label
		)
	for key in [&"right_elbow_angle_deg", &"left_elbow_angle_deg"]:
		var angle := float(pose.get(key, 0.0))
		var minimum_angle := (
			30.0
			if bool(pose.get("gun_placement_line_active", false))
			else 40.0
		)
		_expect(
			angle >= minimum_angle and angle <= 152.0,
			"%s %s remains inside the anatomical envelope" % [label, key]
		)
	_expect(
		float(pose.get("wrist_correction_deg", 180.0)) <= 72.1,
		"%s wrist correction remains bounded" % label
	)
	var visual_target: Vector3 = pose.get("aim_target", Vector3.ZERO)
	var shared_target: Vector3 = rig.get("weapon_aim_point")
	_expect(
		visual_target.distance_to(shared_target) <= 0.01,
		"%s animation consumes the camera's shared target" % label
	)
	var target_node := rig.get("target") as Node
	var mannequin: Node = target_node.get_node_or_null("Mannequin") if target_node != null else null
	if mannequin != null and mannequin.has_method("get_active_muzzle_marker"):
		var active_muzzle: Node3D = mannequin.get_active_muzzle_marker()
		_expect(active_muzzle != null, "%s active weapon exposes a muzzle socket" % label)
		if active_muzzle == null:
			return
		_expect(
			active_muzzle != mannequin.muzzle_marker,
			"%s production muzzle replaces the hidden proxy muzzle" % label
		)
		var muzzle: Vector3 = active_muzzle.global_position
		var ballistic_direction := (shared_target - muzzle).normalized()
		var viewport_size: Vector2 = rig.get_viewport().get_visible_rect().size
		var reticle: Vector2 = rig.get("reticle_screen_normalized")
		var reticle_pixels := Vector2(
			reticle.x * viewport_size.x,
			reticle.y * viewport_size.y
		)
		var view_direction: Vector3 = rig.get("camera").project_ray_normal(
			reticle_pixels
		).normalized()
		var convergence_angle := rad_to_deg(view_direction.angle_to(ballistic_direction))
		_expect(
			(
				Vector3(rig.get("weapon_aim_point")).distance_to(
					Vector3(rig.get("view_aim_point"))
				) <= 0.05
				if bool(rig.get("aim_hit"))
				else convergence_angle <= float(
					rig.get("profile").maximum_convergence_angle_deg
				) + 0.15
			),
			"%s acquired sight point owns muzzle convergence" % label
		)
	var projected_target: Vector2 = rig.get("camera").unproject_position(shared_target)
	var expected_pixels := Vector2(
		float(rig.get("reticle_screen_normalized").x) * rig.get_viewport().get_visible_rect().size.x,
		float(rig.get("reticle_screen_normalized").y) * rig.get_viewport().get_visible_rect().size.y
	)
	_expect(
		projected_target.distance_to(expected_pixels) <= 2.0,
		"%s stabilized ballistic target remains on the centered reticle ray" % label
	)


func _check_crouched_reload_anatomy(driver: Node) -> void:
	_expect(
		driver.call("play_semantic_action", &"reload", 0.12),
		"crouched reload starts for the anatomy check"
	)
	var maximum_right_elbow := 0.0
	var maximum_left_elbow := 0.0
	var maximum_trigger_contact_error := 0.0
	var reload_owner_was_stable := true
	var reload_support_released_before_regrip := false
	var sampled_frames := 0
	for _frame in range(210):
		await physics_frame
		if "reload" not in String(driver.get("requested_action")).to_lower():
			if sampled_frames > 0:
				break
			continue
		var pose: Dictionary = driver.call(
			"get_animation_debug_state"
		).get("weapon_pose", {})
		maximum_right_elbow = maxf(
			maximum_right_elbow,
			float(pose.get("right_elbow_angle_deg", 0.0))
		)
		maximum_left_elbow = maxf(
			maximum_left_elbow,
			float(pose.get("left_elbow_angle_deg", 0.0))
		)
		maximum_trigger_contact_error = maxf(
			maximum_trigger_contact_error,
			float(pose.get("action_trigger_contact_error_m", 1.0))
		)
		reload_owner_was_stable = (
			reload_owner_was_stable
			and StringName(pose.get("weapon_owner", &"")) == &"RELOAD_RIGHT_HAND"
			and StringName(pose.get("arm_owner", &"")) == &"ACTION_CLIP"
		)
		reload_support_released_before_regrip = (
			reload_support_released_before_regrip
			or StringName(pose.get("support_hand_mode", &"")) == &"ANIMATION_FREE"
		)
		sampled_frames += 1
	print("CROUCHED_RELOAD_ANATOMY_METRIC samples=%d right_max=%.2f left_max=%.2f trigger_contact_max=%.4f" % [
		sampled_frames,
		maximum_right_elbow,
		maximum_left_elbow,
		maximum_trigger_contact_error,
	])
	_expect(
		sampled_frames >= 180,
		"crouched reload anatomy check covers the complete take"
	)
	_expect(
		maximum_right_elbow <= 152.0 and maximum_left_elbow <= 152.0,
		"crouched reload keeps both elbows inside the anatomical envelope"
	)
	_expect(
		maximum_trigger_contact_error <= 0.003,
		"crouched reload keeps the rifle trigger attached to the right palm"
	)
	_expect(
		reload_owner_was_stable and reload_support_released_before_regrip,
		"reload has one right-hand owner and releases support-hand IK during the take"
	)


func _check_authored_animation_mount(
	player: CharacterBody3D,
	rig: Node,
	driver: Node
) -> void:
	var asset_runtime = driver.get("asset_runtime")
	var attachment := asset_runtime.weapon_attachment as BoneAttachment3D
	var weapon := driver.get("weapon_node") as Node3D
	var skeleton := driver.get("skeleton") as Skeleton3D
	var pose: Dictionary = driver.call(
		"get_animation_debug_state"
	).get("weapon_pose", {})
	_expect(
		attachment != null and attachment.bone_name == &"ik_hand_gun",
		"authored M4 uses the native AGLS gun mount bone"
	)
	_expect(
		weapon != null and weapon.get_parent() == attachment,
		"authored M4 has one animation-bone parent"
	)
	_expect(
		weapon != null and weapon.transform.is_equal_approx(Transform3D.IDENTITY),
		"authored M4 has no guessed hand-placement offset"
	)
	_expect(
		StringName(pose.get("weapon_owner", &""))
		== WeaponOwnershipContract.AUTHORED_ANIMATION_MOUNT,
		"authored AGLS animation is the only visual weapon owner"
	)
	_expect(
		StringName(pose.get("arm_owner", &""))
		== WeaponOwnershipContract.ARMS_BASE_ANIMATION
		and StringName(pose.get("support_hand_mode", &""))
		== WeaponOwnershipContract.SUPPORT_ANIMATION_FREE,
		"both arms and hands remain animation-owned"
	)
	_expect(
		not bool(pose.get("hand_socket_ik_enabled", true))
		and not bool(pose.get("weapon_solver_owned", true)),
		"procedural hand IK and weapon placement remain disabled"
	)
	if skeleton != null and attachment != null:
		var gun_index := skeleton.find_bone(&"ik_hand_gun")
		var left_index := skeleton.find_bone(&"mixamorig_LeftHand")
		var right_index := skeleton.find_bone(&"mixamorig_RightHand")
		_expect(gun_index >= 0, "live AGLS skeleton preserves ik_hand_gun")
		if gun_index >= 0:
			skeleton.force_update_all_bone_transforms()
			var gun_world := skeleton.global_transform * skeleton.get_bone_global_pose(
				gun_index
			)
			_expect(
				attachment.global_position.distance_to(gun_world.origin) <= 0.002,
				"weapon attachment follows the animated AGLS gun bone"
			)
		if left_index >= 0 and right_index >= 0:
			var hand_distance := skeleton.get_bone_global_pose(left_index).origin.distance_to(
				skeleton.get_bone_global_pose(right_index).origin
			)
			_expect(
				hand_distance >= 0.15 and hand_distance <= 0.45,
				"authored AGLS two-hand rifle pose stays human-sized"
			)
	var mannequin := player.get_node_or_null("Mannequin")
	var muzzle := mannequin.call("get_active_muzzle_marker") as Marker3D
	var barrel := mannequin.call("get_active_barrel_base_marker") as Marker3D
	_expect(
		muzzle != null and barrel != null
		and muzzle.global_position.distance_to(barrel.global_position) > 0.15,
		"authored M4 keeps gameplay-facing barrel markers"
	)
	var player_position := player.global_position
	var player_velocity := player.velocity
	rig.call("set_aim_angles", deg_to_rad(24.0), deg_to_rad(-8.0), true)
	driver.set("requested_weapon_ready_weight", 1.0)
	driver.set("weapon_ready_weight", 1.0)
	await _steps(12)
	pose = driver.call("get_animation_debug_state").get("weapon_pose", {})
	_expect(
		StringName(pose.get("weapon_owner", &""))
		== WeaponOwnershipContract.AUTHORED_ANIMATION_MOUNT
		and not bool(pose.get("weapon_solver_owned", true)),
		"camera aim cannot take weapon ownership from the AGLS animation"
	)
	_expect(
		player.global_position.distance_to(player_position) <= 0.001
		and player.velocity.distance_to(player_velocity) <= 0.001,
		"authored weapon presentation never moves the CharacterBody"
	)
	_expect(bool(driver.call("notify_fired")), "authored M4 accepts the fire presentation event")
	await _steps(3)
	pose = driver.call("get_animation_debug_state").get("weapon_pose", {})
	_expect(
		StringName(pose.get("weapon_owner", &""))
		== WeaponOwnershipContract.AUTHORED_ANIMATION_MOUNT,
		"fire recoil keeps the AGLS animation mount owner"
	)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame


func _hold(action: StringName, frame_count: int) -> void:
	Input.action_press(action)
	for _frame in range(frame_count):
		await physics_frame
	Input.action_release(action)
	await physics_frame


func _steps(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("WEAPON_POSE_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("WEAPON_POSE_CHECK FAIL %s" % label)


func _finish() -> void:
	for action in [&"crouch"]:
		Input.action_release(action)
	if failures.is_empty():
		print("OPERATOR_WEAPON_POSE_REGRESSION PASS")
		quit(0)
	else:
		print("OPERATOR_WEAPON_POSE_REGRESSION FAIL ", failures)
		quit(1)
