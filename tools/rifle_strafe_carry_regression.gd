extends SceneTree

## Scoped regression for docs/AK_M4_STRAFE_CARRY_TRANSLATION.md.
## Canonical drivers and profiles; only the test's visual-input mirror is held
## while deterministic inputs exercise the same runtime graph and contact solve.

const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const CARRY_KEY := "locomotion_ready_carry_weight"
const SELECTED := ["ak-47", "m4a1"]
const DIRECTIONS := [Vector2.LEFT, Vector2.RIGHT, Vector2(-0.7071, 0.7071), Vector2(0.7071, 0.7071)]

var failures: Array[String] = []
var scene: Node3D
var player: CharacterBody3D
var controller: Node
var driver: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_scope()
	scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await _frames(50)
	player = scene.get_node_or_null("Player") as CharacterBody3D
	controller = scene.get_node_or_null("WeaponController")
	var mannequin := player.get_node_or_null("Mannequin") if player else null
	driver = mannequin.get_node_or_null("ProductionAnimation") if mannequin else null
	var runtime_ready := player != null and controller != null and driver != null and driver.has_method("get_animation_debug_state") and driver.has_method("set_visual_inputs")
	_check(runtime_ready, "canonical runtime owners exist and compiled")
	if not runtime_ready:
		_finish()
		return
	player.set_physics_process(false)
	mannequin.set_process(false)
	for weapon: String in ["ak-47", "m4a1", "m16a2", "mark_23"]:
		var path := "res://config/weapons/%s.json" % weapon
		var equipped := bool(controller.call("apply_authorized_weapon_pickup", path))
		_check(equipped, weapon + " canonical equip")
		if not equipped:
			continue
		await _frames(20)
		_check_graph_weights(weapon)
		if weapon in SELECTED:
			for posture: StringName in [&"STANDING", &"CROUCHED"]:
				await _check_contacts_and_phase(weapon, posture)
	_finish()


func _check_scope() -> void:
	var opted_in: Array[String] = []
	for name: String in DirAccess.get_files_at("res://config/weapons"):
		if not name.ends_with(".json"):
			continue
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/" + name))
		if not raw is Dictionary:
			continue
		var handling: Dictionary = raw.get("handling_profile", {})
		var dynamic: Dictionary = handling.get("dynamic_hold", {})
		var weight := float(dynamic.get(CARRY_KEY, 0.0))
		var strafe: Dictionary = dynamic.get("strafe_carry", {})
		if weight > 0.0:
			opted_in.append(name.trim_suffix(".json"))
		if name.trim_suffix(".json") in SELECTED:
			_check(is_equal_approx(weight, 1.0), name + " enables stable relaxed carry")
			_check(strafe == {"right_hip_follow_weight": 1.0, "left_elbow_flare_degrees": 12.0, "right_stock_release_m": 0.33, "right_stock_release_frame": "chest_forward"}, name + " opts into full rightward body carry with saved stock release")
		else:
			_check(is_zero_approx(weight), name + " retains default carry")
			_check(is_zero_approx(float(strafe.get("right_hip_follow_weight", 0.0))) and is_zero_approx(float(strafe.get("left_elbow_flare_degrees", 0.0))), name + " retains default directional carry")
			_check(is_zero_approx(float(strafe.get("right_stock_release_m", 0.0))), name + " retains default zero stock release")
	opted_in.sort()
	_check(opted_in == ["ak-47", "m4a1"], "only AK/M4 opt in")


func _check_graph_weights(weapon: String) -> void:
	var graph = driver.get("locomotion_graph")
	var handling: Dictionary = driver.get("equipped_weapon_handling_profile")
	var dynamic: Dictionary = handling.get("dynamic_hold", {})
	var relaxed := float(dynamic.get(CARRY_KEY, 0.0))
	var expected_carry := 1.0 if weapon in SELECTED else 0.0
	_check(is_equal_approx(relaxed, expected_carry), weapon + " published rig preserves canonical carry opt-in")
	var strafe: Dictionary = dynamic.get("strafe_carry", {})
	_check(is_equal_approx(float(strafe.get("right_hip_follow_weight", 0.0)), expected_carry), weapon + " published rig preserves full rightward hip follow")
	_check(is_equal_approx(float(driver.get("weapon_pose_solver").get("strafe_left_elbow_flare_degrees")), 12.0 * expected_carry), weapon + " equip-time elbow setting has no previous weapon leakage")
	var inheritance := float(dynamic.get("ready_locomotion_inheritance", 0.22))
	var ready_before := float(driver.get("weapon_ready_weight"))
	var latch_before: Dictionary = driver.get("fire_upper_body_latch").get_debug_state()
	for ready: float in [0.0, 0.5, 1.0]:
		graph.update_locomotion(Vector2.LEFT, 1.0, 6.5, &"STANDING", ready, 1.0 / 60.0)
		var weight := float(graph.animation_tree.get("parameters/standing_upper_body/blend_amount"))
		var expected := maxf(ready, expected_carry) * (1.0 - inheritance)
		_check(is_equal_approx(weight, expected), "%s ready %.1f has continuous carry blend" % [weapon, ready])
		_check(is_equal_approx(float(driver.get("weapon_ready_weight")), ready_before), "graph blend does not force readiness")
		var latch_now: Dictionary = driver.get("fire_upper_body_latch").get_debug_state()
		_check(latch_now == latch_before, "graph blend does not create a fire latch")
	graph.update_locomotion(Vector2.ZERO, 0.0, 0.0, &"STANDING", 0.0, 1.0 / 60.0)
	_check(is_zero_approx(float(graph.upper_body_ready_blend)), "stationary relaxed input retains idle route")


func _check_contacts_and_phase(weapon: String, posture: StringName) -> void:
	var stance := 0 if posture == &"STANDING" else 1
	_check(bool(player.call("_try_set_posture", stance)), "%s enters %s" % [weapon, posture])
	_input(Vector2.LEFT, posture)
	await _frames(50)
	var tree: AnimationTree = driver.get("animation_tree")
	var phase_path := "parameters/full_space" if posture == &"STANDING" else "parameters/crouch_space"
	var previous_phase := -1.0
	var travel := 0.0
	var max_contact := 0.0
	for direction: Vector2 in DIRECTIONS:
		_input(direction, posture)
		for frame in 28:
			await process_frame
			var debug: Dictionary = driver.call("get_animation_debug_state")
			var pose: Dictionary = debug.get("weapon_pose", {})
			var contact := maxf(float(pose.get("trigger_hand_error_m", INF)), float(pose.get("support_hand_error_m", INF)))
			max_contact = maxf(max_contact, contact)
			_check(contact <= 0.01, "%s %s carry contacts <=1cm" % [weapon, posture])
			_check(float(debug.get("weapon_ready_weight", 1.0)) < 0.001, "%s %s relaxed movement stays unready" % [weapon, posture])
			var latch: Dictionary = debug.get("fire_upper_body_latch", {})
			_check(not bool(latch.get("selected", true)), "%s %s relaxed carry does not select recovery" % [weapon, posture])
			var length := float(tree.get(phase_path + "/current_length"))
			var phase := float(tree.get(phase_path + "/current_position")) / maxf(length, 0.0001)
			if previous_phase >= 0.0:
				var step := fposmod(phase - previous_phase, 1.0)
				_check(step < 0.15, "%s %s direction changes do not reset gait" % [weapon, posture])
				travel += step
			previous_phase = phase
		_record_geometry(weapon, posture, direction)
		_check_directional_owner(weapon, posture)
	_check(travel > 0.10, "%s %s gait is not frozen" % [weapon, posture])
	var shot: Dictionary = controller.call("request_fire")
	_check(bool(shot.get("fired", false)), weapon + " canonical shot accepted")
	await _frames(3)
	var fire_debug: Dictionary = driver.call("get_animation_debug_state")
	var fire_latch: Dictionary = fire_debug.get("fire_upper_body_latch", {})
	_check(String(fire_latch.get("owner_state", "")) == "FIRE_RECOVERY", weapon + " accepted shot enters recovery")
	_check(is_equal_approx(float(fire_latch.get("grace_duration_seconds", 0.0)), 1.2), "recovery remains 1.2seconds")
	await _frames(120)
	var returned: Dictionary = driver.call("get_animation_debug_state")
	_check(not bool((returned.get("fire_upper_body_latch", {}) as Dictionary).get("selected", true)), weapon + " recovery ends without permanent latch")
	print("RIFLE_STRAFE_CARRY_METRIC ", weapon, " ", posture, " max_contact_m=", max_contact, " phase_travel=", travel)


func _record_geometry(weapon: String, posture: StringName, direction: Vector2) -> void:
	var solver = driver.get("weapon_pose_solver")
	var pose: Dictionary = solver.get_debug_state()
	var muzzle: Marker3D = solver.muzzle_socket
	var barrel: Marker3D = solver.barrel_base_socket
	if muzzle == null or barrel == null:
		_check(false, weapon + " has physical muzzle and barrel markers")
		return
	var local_bore := player.global_basis.inverse() * (muzzle.global_position - barrel.global_position).normalized()
	var left: Vector3 = pose.get("left_elbow_position", Vector3.ZERO)
	var right: Vector3 = pose.get("right_elbow_position", Vector3.ZERO)
	var skeleton: Skeleton3D = driver.get("skeleton")
	var left_shoulder := _bone_world_position(skeleton, &"mixamorig_LeftArm")
	var right_shoulder := _bone_world_position(skeleton, &"mixamorig_RightArm")
	var shoulder_axis := player.global_basis.inverse() * (right_shoulder - left_shoulder).normalized()
	print("RIFLE_STRAFE_GEOMETRY ", JSON.stringify({
		"weapon": weapon,
		"posture": String(posture),
		"direction": [direction.x, direction.y],
		"muzzle_yaw_body_deg": rad_to_deg(atan2(-local_bore.x, -local_bore.z)),
		"muzzle_pitch_body_deg": rad_to_deg(atan2(local_bore.y, Vector2(local_bore.x, local_bore.z).length())),
		"elbow_span_m": left.distance_to(right),
		"right_elbow_angle_deg": pose.get("right_elbow_angle_deg", -1.0),
		"left_elbow_angle_deg": pose.get("left_elbow_angle_deg", -1.0),
		"shoulder_axis_yaw_deg": rad_to_deg(atan2(-shoulder_axis.z, shoulder_axis.x)),
		"right_hip_follow_weight": driver.call("_right_strafe_hip_follow"),
		"signed_carry_strafe": driver.call("_directional_carry_strafe"),
	}))


func _check_directional_owner(weapon: String, posture: StringName) -> void:
	var graph = driver.get("locomotion_graph")
	var signed_carry := float(graph.rendered_direction.x) * float(graph.locomotion_carry_weight)
	var hip_follow := float(driver.call("_right_strafe_hip_follow"))
	var readiness := clampf(float(driver.get("_presentation_ready_weight")), 0.0, 1.0)
	_check(is_equal_approx(hip_follow, maxf(signed_carry, 0.0) * readiness), "%s %s only ready rightward carry follows hips" % [weapon, posture])
	var solver = driver.get("weapon_pose_solver")
	var angle := float(solver.call("_elbow_presentation_angle", posture, &"LOCOMOTION", 0.0, &"", true, signed_carry))
	_check(is_equal_approx(rad_to_deg(angle), maxf(-signed_carry, 0.0) * 12.0), "%s %s only leftward carry flares the right elbow" % [weapon, posture])
	# Feed exclusions into the existing input consumer, not its internals. No
	# process frame elapses, so this tests routing without replacing a live pose.
	for blocked_state: StringName in [&"DIVING", &"ROLLING", &"AIRBORNE", &"LANDING"]:
		_input(Vector2.RIGHT, posture, blocked_state)
		_check(is_zero_approx(float(driver.call("_directional_carry_strafe"))), "directional carry is suppressed in " + String(blocked_state))
	_input(Vector2.RIGHT, &"PRONE")
	_check(is_zero_approx(float(driver.call("_directional_carry_strafe"))), "directional carry is suppressed in prone")
	_input(graph.rendered_direction, posture)


func _bone_world_position(skeleton: Skeleton3D, bone_name: StringName) -> Vector3:
	var index := skeleton.find_bone(bone_name)
	_check(index >= 0, "canonical skeleton has " + String(bone_name))
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin if index >= 0 else Vector3.ZERO


func _input(direction: Vector2, posture: StringName, movement_state: StringName = &"LOCOMOTION") -> void:
	var speed := 6.5 if posture == &"STANDING" else 2.6
	var target := player.global_position + Vector3(0.0, 1.4 if posture == &"STANDING" else 1.0, -25.0)
	driver.call("set_visual_inputs", direction, posture, 0.0, 0.0, 0.0, false, 0.0, 1.0, movement_state, 0.0, &"FULL" if posture == &"STANDING" else &"WALK", speed, target)


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition and not failures.has(label):
		failures.append(label)
		push_error("RIFLE_STRAFE_CARRY " + label)


func _finish() -> void:
	# Fixed-fps headless simulation can finish before the real-time audio mixer.
	# Release only this process's probe playback before destroying its scene.
	_stop_audio(root)
	if scene:
		scene.queue_free()
		await process_frame
		await process_frame
	print("RIFLE_STRAFE_CARRY ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)


func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		node.call("stop")
	for child in node.get_children():
		_stop_audio(child)
