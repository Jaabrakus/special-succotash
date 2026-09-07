extends "res://tools/firearm_family_transition_regression.gd"

## Real-input timing proof. Default: AK/M4. No runtime/property writes.
## --weapons=ak-47,m4a1 --output-prefix=/private/tmp/rifle-carry-timing
## Omit --automated-test, which disables canonical movement input.
class FrameObserver:
	extends Node
	var proof: SceneTree
	var before_driver := false
	func _process(delta: float) -> void:
		proof.observe_frame(delta, before_driver)

var timing_rows: Array[Dictionary] = []
var active_transition := ""
var source_frame: Dictionary = {}
var observed_tree: AnimationTree
var mixer_frame := -1
var mixer_calls := 0
var observer_nodes: Array[Node] = []
var stop_boundaries: Dictionary = {}
var stop_fade_samples: Dictionary = {}
var stop_motion_maxima: Dictionary = {}
var previous_observation: Dictionary = {}


func _initialize() -> void:
	var explicit_weapons := false
	var explicit_output := false
	for argument in OS.get_cmdline_user_args():
		explicit_weapons = explicit_weapons or argument.begins_with("--weapons=")
		explicit_output = explicit_output or argument.begins_with("--output-prefix=")
	if not explicit_weapons:
		selected_ids.assign(["ak-47", "m4a1"])
	super._initialize()
	if not explicit_output:
		output_prefix = "/private/tmp/rifle-carry-timing"


func _check_stance(stance: int) -> void:
	if observer_nodes.is_empty():
		if driver.process_priority != 100:
			_fail_once("Timing proof requires the existing priority-100 pose driver")
			return
		for priority in [99, 101]:
			var observer := FrameObserver.new()
			observer.proof = self
			observer.before_driver = priority == 99
			observer.process_priority = priority
			root.add_child(observer)
			observer_nodes.append(observer)
	await super._check_stance(stance)


func _record_transition(label: String, count: int, check_bore: bool) -> void:
	active_transition = label
	await super._record_transition(label, count, check_bore)
	active_transition = ""


func _mixer_applied() -> void:
	var frame := Engine.get_process_frames()
	if mixer_frame != frame:
		mixer_frame = frame
		mixer_calls = 0
	mixer_calls += 1


func observe_frame(delta: float, before_driver: bool) -> void:
	if not is_instance_valid(driver):
		return
	var graph: RefCounted = driver.get("locomotion_graph")
	var tree: AnimationTree = graph.get("animation_tree")
	if tree != observed_tree:
		if is_instance_valid(observed_tree):
			observed_tree.mixer_applied.disconnect(_mixer_applied)
		observed_tree = tree
		observed_tree.mixer_applied.connect(_mixer_applied)
		mixer_frame = -1
		mixer_calls = 0
	if active_transition.is_empty():
		return
	if before_driver:
		source_frame = _snapshot(delta)
		return
	var result := _snapshot(delta)
	if source_frame.is_empty() or source_frame.process_frame != result.process_frame:
		_fail_once(active_transition + " source/result process frames differ")
		return
	var solver: Node = driver.get("weapon_pose_solver")
	var layer: RefCounted = driver.get("posture_layer")
	var source_carry := float(source_frame.carry)
	var source_direction: Vector2 = source_frame.direction
	var carry_error := absf(float(graph.get("evaluated_locomotion_carry_weight")) - source_carry)
	var evaluated_direction: Vector2 = graph.get("evaluated_carry_direction")
	var direction_error := evaluated_direction.distance_to(source_direction)
	var expected_route := float(source_frame.independent_route_weight)
	var route_error := absf(float(graph.get("evaluated_locomotion_source_weight")) - expected_route)
	var dynamic: Dictionary = driver.get("equipped_weapon_handling_profile").get("dynamic_hold", {})
	var configured_carry := clampf(float(dynamic.get("locomotion_ready_carry_weight", 0.0)), 0.0, 1.0)
	var expected_stability := configured_carry * expected_route
	var expected_strafe := expected_stability * source_direction.x
	var stability_error := absf(float(driver.call("_rifle_movement_stability_weight")) - expected_stability)
	var strafe_error := absf(float(driver.call("_directional_carry_strafe")) - expected_strafe)
	var expected_idle_pelvis := 1.0 - expected_route if StringName(driver.get("_presentation_posture")) == &"STANDING" and bool(dynamic.get("standing_idle_square_pelvis", false)) else 0.0
	var pelvis_error := absf(float(driver.call("_standing_idle_pelvis_weight")) - expected_idle_pelvis)
	var expected_turn := clampf(float(layer.get("last_directional_shoulder_target_deg")) / 90.0, 0.0, 1.0) * float(layer.get("last_shoulder_square_weight"))
	var turn_error := absf(float(solver.get("authored_stock_right_turn_weight")) - expected_turn)
	var expected_phase := fposmod(float(source_frame.phase) + delta * float(result.playback_rate), 1.0)
	var phase_error := absf(float(result.phase) - expected_phase)
	phase_error = minf(phase_error, 1.0 - phase_error)
	if maxf(carry_error, direction_error) > 0.000001:
		_fail_once(active_transition + " evaluated carry differs from the source frame")
	if maxf(route_error, pelvis_error) > 0.000001:
		_fail_once(active_transition + " route carry/pelvis differs from evaluated source blend")
	if maxf(maxf(stability_error, strafe_error), turn_error) > 0.000001:
		_fail_once(active_transition + " posture/stock consumes a different carry frame")
	if source_frame.mixer_calls != 1 or result.mixer_calls != 1:
		_fail_once(active_transition + " AnimationTree must evaluate exactly once before posture")
	if source_frame.current_state != result.current_state or source_frame.previous_fade != result.previous_fade:
		_fail_once(active_transition + " source route advanced again inside the pose pass")
	if phase_error > 0.000001:
		_fail_once(active_transition + " shared gait phase did not advance exactly once")
	if active_transition.ends_with("_D_stop_recovery") and source_carry > 0.001 and float(result.carry) <= 0.001:
		stop_boundaries[active_transition] = int(stop_boundaries.get(active_transition, 0)) + 1
	if active_transition.ends_with("_D_stop_recovery") and expected_route > 0.001 and expected_route < 0.999:
		stop_fade_samples[active_transition] = int(stop_fade_samples.get(active_transition, 0)) + 1
	var physical := _measure_physical_pose()
	var ready := float(driver.get("weapon_ready_weight"))
	var left_angle := _physical_elbow_angle(&"Left")
	var right_angle := _physical_elbow_angle(&"Right")
	var motion_step := _record_stop_motion(result, left_angle, right_angle, ready)
	var authored := bool(solver.get("authored_shoulder_stock_active"))
	var contact_limit := MAX_AUTHORED_PALM_ERROR_M if authored else MAX_PALM_ERROR_M
	if physical.is_empty():
		_fail_once(active_transition + " post-driver physical measurements missing")
	elif maxf(float(physical.trigger_contact_m), float(physical.support_contact_m)) > contact_limit:
		_fail_once(active_transition + " post-driver palms exceed existing contact limits")
	if ready >= 0.98:
		for angle in [left_angle, right_angle]:
			if not is_finite(angle) or angle < float(solver.get("minimum_elbow_angle_deg")) or angle > float(solver.get("maximum_elbow_angle_deg")):
				_fail_once(active_transition + " post-driver elbow outside existing rifle bounds")
		if not physical.is_empty() and float(physical.bore_to_reticle_degrees) > (MAX_AUTHORED_BORE_ERROR_DEG if authored else MAX_BORE_ERROR_DEG):
			_fail_once(active_transition + " post-driver ready bore exceeds existing aim limit")
	timing_rows.append({
		"weapon": weapon_id, "state": active_transition, "before": source_frame, "after": result,
		"carry_error": carry_error, "direction_error": direction_error,
		"stability_error": stability_error, "strafe_error": strafe_error, "stock_turn_error": turn_error,
		"route_error": route_error, "pelvis_error": pelvis_error, "stop_motion_step": motion_step,
		"phase_error": phase_error, "physical": physical, "ready": ready,
		"left_elbow_deg": left_angle, "right_elbow_deg": right_angle,
	})


func _snapshot(delta: float) -> Dictionary:
	var graph: RefCounted = driver.get("locomotion_graph")
	var solver: Node = driver.get("weapon_pose_solver")
	var layer: RefCounted = driver.get("posture_layer")
	var skeleton: Skeleton3D = solver.get("skeleton")
	var transition: AnimationNodeTransition = graph.get("modern_transition")
	var previous_index := int(observed_tree.get("parameters/modern_transition/prev_index"))
	var previous_valid := previous_index >= 0 and previous_index < transition.input_count
	var previous_state: String = transition.get_input_name(previous_index) if previous_valid else ""
	var current_state := String(observed_tree.get("parameters/modern_transition/current_state"))
	var route_weight := float(current_state in ["standing", "crouch"])
	var previous_fade := float(observed_tree.get("parameters/modern_transition/prev_xfading"))
	# Independent observation, not a call to the runtime route-weight helper.
	if previous_valid and transition.xfade_time > 0.0:
		var previous_amount := clampf((previous_fade + absf(delta)) / transition.xfade_time, 0.0, 1.0)
		if transition.xfade_curve != null:
			previous_amount = clampf(transition.xfade_curve.sample(previous_amount), 0.0, 1.0)
		route_weight = route_weight * (1.0 - previous_amount) + float(previous_state in ["standing", "crouch"]) * previous_amount
	var right_shoulder: Vector3 = solver.call("_bone_world_position", &"mixamorig_RightArm")
	var left_shoulder: Vector3 = solver.call("_bone_world_position", &"mixamorig_LeftArm")
	var stock: Node3D = solver.get("stock_socket")
	var bones: Dictionary = {}
	for bone_name: String in ["mixamorig_Hips", "mixamorig_Spine2"]:
		var index := skeleton.find_bone(bone_name)
		var world := skeleton.global_transform * skeleton.get_bone_global_pose_no_override(index)
		bones[bone_name] = {"position": world.origin, "basis": str(world.basis)}
	return {
		"process_frame": Engine.get_process_frames(), "physics_frame": Engine.get_physics_frames(),
		"delta": delta, "mixer_calls": mixer_calls if mixer_frame == Engine.get_process_frames() else 0,
		"current_state": current_state, "previous_state": previous_state,
		"queued_state": graph.get("current_state"),
		"previous_fade": previous_fade, "fade_duration": transition.xfade_time,
		"independent_route_weight": route_weight,
		"carry": graph.get("locomotion_carry_weight"), "direction": graph.get("rendered_direction"),
		"phase": graph.get("shared_phase"), "playback_rate": graph.get("playback_rate"),
		"speed_mps": driver.get("movement_speed_mps"), "speed_normalized": driver.get("movement_speed_normalized"),
		"handoff": driver.get("pose_handoff").call("get_debug_state"),
		"idle_pelvis_weight": driver.call("_standing_idle_pelvis_weight"),
		"shoulder_square_weight": layer.get("last_shoulder_square_weight"),
		"shoulder_target_deg": layer.get("last_directional_shoulder_target_deg"),
		"stable_chest": solver.get("stable_chest_anchor_world"), "bones": bones,
		"shoulder_bar": (right_shoulder - left_shoulder).normalized(),
		"stock_relative_body": player.to_local(stock.global_position),
	}


func _record_stop_motion(result: Dictionary, left_angle: float, right_angle: float, ready: float) -> Dictionary:
	var step: Dictionary = {}
	if active_transition.ends_with("_D_stop_recovery") and previous_observation.get("weapon", "") == weapon_id and int(previous_observation.get("frame", -2)) + 1 == int(result.process_frame):
		var prior_bar: Vector3 = previous_observation.shoulder_bar
		var current_bar: Vector3 = result.shoulder_bar
		var prior_stock: Vector3 = previous_observation.stock_relative_body
		var current_stock: Vector3 = result.stock_relative_body
		step = {
			"shoulder_deg": rad_to_deg(prior_bar.angle_to(current_bar)),
			"stock_m": prior_stock.distance_to(current_stock),
			"left_elbow_deg": absf(left_angle - float(previous_observation.left_elbow)),
			"right_elbow_deg": absf(right_angle - float(previous_observation.right_elbow)),
		}
		for group in [active_transition, active_transition + "_fully_ready"]:
			if group.ends_with("_fully_ready") and (ready < 0.98 or float(previous_observation.ready) < 0.98):
				continue
			var maxima: Dictionary = stop_motion_maxima.get(group, {})
			for key: String in step:
				maxima[key] = maxf(float(maxima.get(key, 0.0)), float(step[key]))
			stop_motion_maxima[group] = maxima
	previous_observation = {
		"weapon": weapon_id, "frame": result.process_frame, "ready": ready,
		"shoulder_bar": result.shoulder_bar, "stock_relative_body": result.stock_relative_body,
		"left_elbow": left_angle, "right_elbow": right_angle,
	}
	return step


func _runtime_source_signatures() -> Dictionary:
	var sources := super._runtime_source_signatures()
	sources["locomotion_graph"] = FileAccess.get_sha256("res://scripts/player/operator_locomotion_blend_tree.gd")
	sources["driver_pose"] = FileAccess.get_sha256("res://scripts/player/operator_animation_driver_pose.gd")
	return sources


func _finish() -> void:
	active_transition = ""
	if not list_only:
		for id in selected_ids:
			for stance in ["standing", "crouched"]:
				if int(stop_boundaries.get("%s_%s_D_stop_recovery" % [id, stance], 0)) < 1:
					_fail_once("%s %s did not exercise a nonzero-to-zero carry boundary" % [id, stance])
				if int(stop_fade_samples.get("%s_%s_D_stop_recovery" % [id, stance], 0)) < 2:
					_fail_once("%s %s did not exercise the intermediate source fade" % [id, stance])
		if timing_rows.is_empty():
			_fail_once("No same-frame carry samples recorded")
	if _runtime_source_signatures() != runtime_sources_at_start:
		_fail_once("Runtime sources changed on disk during the timing proof")
	var output := FileAccess.open(output_prefix + ".timing.json", FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify({"pass": failures.is_empty(), "failures": failures, "rows": timing_rows, "stop_boundaries": stop_boundaries, "stop_fade_samples": stop_fade_samples, "stop_motion_maxima": stop_motion_maxima, "native_visual_approval": false}, "\t"))
		output.close()
	else:
		_fail_once("Could not save same-frame carry timing report")
	print("RIFLE_EVALUATED_CARRY_TIMING ", "PASS" if failures.is_empty() else "FAIL", " frames=", timing_rows.size(), " boundaries=", stop_boundaries)
	super._finish()
