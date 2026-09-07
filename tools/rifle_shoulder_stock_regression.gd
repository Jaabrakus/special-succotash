extends SceneTree

## Physical proof for docs/AK_M4_STRAFE_CARRY_TRANSLATION.md. The canonical
## scene/controller equip and accept shots; only visual movement inputs are
## deterministic. Native input-driven captures remain the appearance gate.
const DIRECTIONS := [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2(-0.7071, 0.7071), Vector2(0.7071, 0.7071)]
var failures: Array[String] = []
var scene: Node3D
var player: CharacterBody3D
var driver: Node
var controller: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	scene = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(50)
	player = scene.get_node("Player")
	controller = scene.get_node("WeaponController")
	driver = player.get_node("Mannequin/ProductionAnimation")
	player.set_physics_process(false)
	player.get_node("Mannequin").set_process(false)
	for weapon: String in ["ak-47", "m4a1", "m16a2", "mark_23"]:
		_check(bool(controller.call("apply_authorized_weapon_pickup", "res://config/weapons/%s.json" % weapon)), weapon + " canonical equip")
		await _frames(20)
		var solver = driver.get("weapon_pose_solver")
		var selected := weapon in ["ak-47", "m4a1", "m16a2"]
		_check(bool(solver.authored_shoulder_stock_enabled) == selected, weapon + " resolved stock opt-in has no equip leakage")
		if not selected:
			continue
		for posture: StringName in [&"STANDING", &"CROUCHED"]:
			_check(bool(player.call("_try_set_posture", 0 if posture == &"STANDING" else 1)), weapon + " canonical posture change")
			for direction: Vector2 in DIRECTIONS:
				_input(direction, posture)
				await _frames(100)
				_check(not solver.authored_shoulder_stock_active, weapon + " relaxed pose remains authored")
				var shot: Dictionary = controller.call("request_fire")
				_check(bool(shot.get("fired", false)), weapon + " canonical accepted shot")
				var worst_palm := 0.0
				var worst_bore := 0.0
				var worst_geometry: Dictionary = {}
				for frame in 32:
					await process_frame
					_check(bool(solver.authored_shoulder_stock_active), weapon + " fired pose uses scoped stock helper")
					var muzzle: Marker3D = solver.muzzle_socket
					var barrel: Marker3D = solver.barrel_base_socket
					var target: Vector3 = driver.get("visual_aim_target")
					var bore := rad_to_deg((muzzle.global_position - barrel.global_position).normalized().angle_to(muzzle.global_position.direction_to(target)))
					worst_bore = maxf(worst_bore, bore)
					var contact := maxf(float(solver.trigger_hand_error_m), float(solver.support_hand_error_m))
					if contact > worst_palm:
						worst_geometry = _arm_geometry(solver)
					worst_palm = maxf(worst_palm, contact)
					_check(contact < 0.005, "%s %s palms stay within 5mm through stock blend" % [weapon, posture])
					_check(bore < 0.5, "%s %s physical bore follows accepted aim" % [weapon, posture])
					_check(absf(bore - float(solver.weapon_aim_error_deg)) < 0.1, "bore diagnostic is measured, not a stale default")
					if float(driver.get("weapon_ready_weight")) > 0.995:
						var stock_error: float = solver.stock_constraint.measure_contact_error()
						var release: float = solver.authored_stock_release_applied_m
						if direction.x > 0.0:
							_check(release > 0.0 and absf(stock_error - release) < 0.005, "%s %s full-right stock uses only its saved forward release" % [weapon, posture])
						else:
							_check(is_zero_approx(release) and stock_error < 0.005, "%s %s settled stock is high in saved shoulder pocket" % [weapon, posture])
						_check(float(solver.right_elbow_angle_deg) >= float(solver.minimum_elbow_angle_deg) and float(solver.left_elbow_angle_deg) >= float(solver.minimum_elbow_angle_deg), "%s %s settled elbows honor the existing human minimum angle" % [weapon, posture])
				print("RIFLE_STOCK_METRIC ", weapon, " ", posture, " ", direction, " max_palm_m=", worst_palm, " max_bore_deg=", worst_bore, " stock_m=", solver.stock_constraint.measure_contact_error(), " arm_geometry=", JSON.stringify(worst_geometry))
				await _frames(115)
				_check(not solver.authored_shoulder_stock_active, weapon + " recovers to original authored route without permanent latch")
				var relaxed_palm: Transform3D = solver.call("_right_hand_grip_world_transform")
				_check(solver.trigger_socket.global_position.distance_to(relaxed_palm.origin) < 0.005, weapon + " finalized zero-ready mount follows the authored trigger palm")
	for child in root.get_children():
		if child == scene:
			child.queue_free()
	await _frames(2)
	print("RIFLE_SHOULDER_STOCK ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)


func _input(direction: Vector2, posture: StringName) -> void:
	var moving := direction.length() > 0.01
	var speed := (6.5 if posture == &"STANDING" else 2.6) if moving else 0.0
	var target := player.global_position + Vector3(0.0, 1.4 if posture == &"STANDING" else 1.0, -25.0)
	driver.call("set_visual_inputs", direction, posture, 0.0, 0.0, 0.0, false, 0.0, 1.0 if moving else 0.0, &"LOCOMOTION", 0.0, &"FULL" if posture == &"STANDING" else &"WALK", speed, target)


func _arm_geometry(solver: Node) -> Dictionary:
	var result := {"right_error_m": solver.trigger_hand_error_m, "left_error_m": solver.support_hand_error_m}
	var posture_debug: Dictionary = driver.get("posture_layer").get_debug_state()
	result["directional_shoulder_target_deg"] = posture_debug.get("directional_shoulder_target_deg", -1.0)
	result["directional_shoulder_error_deg"] = posture_debug.get("directional_shoulder_error_deg", -1.0)
	for side: String in ["Right", "Left"]:
		var shoulder: Vector3 = solver._bone_world_position(StringName("mixamorig_" + side + "Arm"))
		var elbow: Vector3 = solver._bone_world_position(StringName("mixamorig_" + side + "ForeArm"))
		var wrist: Vector3 = solver._bone_world_position(StringName("mixamorig_" + side + "Hand"))
		var target: Marker3D = solver.trigger_hand_target if side == "Right" else solver.support_hand_target
		var palm: Vector3 = solver.right_palm_anchor_local if side == "Right" else solver.left_palm_anchor_local
		var target_wrist := preload("res://scripts/player/operator_weapon_contact_solver.gd").wrist_target_for_contact(solver.skeleton, target.global_transform, palm)
		result[side] = {"upper_m": shoulder.distance_to(elbow), "lower_m": elbow.distance_to(wrist), "target_span_m": shoulder.distance_to(target_wrist.origin), "current_span_m": shoulder.distance_to(wrist), "wrist_residual_m": wrist.distance_to(target_wrist.origin)}
		if side == "Left":
			var contact: Vector3 = solver.support_socket.global_position
			var anchor := preload("res://scripts/player/operator_weapon_contact_solver.gd").scaled_palm_anchor(solver.skeleton, palm)
			var raw_pose: Dictionary = solver.weapon_node.get_meta("support_hand_pose", {})
			var rotation := Vector3(float(raw_pose.get("palm_pitch_deg", 0.0)), float(raw_pose.get("palm_yaw_deg", 0.0)), float(raw_pose.get("palm_roll_deg", 0.0))) * PI / 180.0
			var calibrated := Transform3D((solver.support_socket.global_basis.orthonormalized() * Basis.from_euler(rotation, EULER_ORDER_YXZ)).orthonormalized(), contact)
			var calibrated_wrist := preload("res://scripts/player/operator_weapon_contact_solver.gd").wrist_target_for_contact(solver.skeleton, calibrated, palm)
			result[side]["calibrated_wrist_span_m"] = shoulder.distance_to(calibrated_wrist.origin)
			result[side]["palm_span_m"] = shoulder.distance_to(contact)
			result[side]["wrist_palm_offset_m"] = anchor.length()
			result[side]["maximum_span_any_wrist_rotation_m"] = shoulder.distance_to(contact) + anchor.length()
	return result


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
		push_error("RIFLE_SHOULDER_STOCK " + message)
