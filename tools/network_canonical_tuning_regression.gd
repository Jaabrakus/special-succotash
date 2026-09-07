extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var solo := load("res://main.tscn").instantiate() as Node3D
	root.add_child(solo)
	await process_frame
	var solo_player: Node = solo.get_node("Player")
	var solo_driver: Node = solo_player.get_node("Mannequin").production_animation
	var expected := _snapshot(solo_player, solo_driver, solo.camera_rig)
	solo.queue_free()
	await process_frame
	# Online must also work when it boots directly, without a preceding lab.
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	ProjectSettings.set_setting("socom/session/tournament_mode", false)
	var online := load("res://multiplayer_slice.tscn").instantiate() as Node3D
	root.add_child(online)
	await process_frame
	online._spawn_operator_local(1, 0, Vector3(0, 8, 0))
	online.local_operator.set_physics_process(false)
	await process_frame
	await process_frame
	var actual := _snapshot(online.local_operator, online.local_operator.mannequin.production_animation, online.local_camera)
	_check(expected.size() >= 29 and actual.size() >= 29, "both real runtimes initialized for parity comparison")
	for key: String in expected:
		_check(actual.get(key) == expected[key], "%s: solo=%s online=%s" % [key, expected[key], actual.get(key)])
	online.queue_free()
	await process_frame
	print("NETWORK_CANONICAL_TUNING ", "PASS" if failures.is_empty() else "FAIL", " comparisons=", expected.size(), " ", failures)
	quit(0 if failures.is_empty() else 1)

func _snapshot(player: Node, driver: Node, camera: Node) -> Dictionary:
	var result := {}
	if player == null or driver == null or camera == null or driver.animation_player == null:
		_check(false, "runtime failed to initialize its player, driver or camera")
		return result
	for field: String in ["move_speed", "strafe_speed", "instant_strafe_response", "crouch_speed", "prone_speed", "acceleration", "braking_acceleration", "reversal_acceleration", "strafe_burst_frames", "strafe_burst_multiplier", "strafe_burst_decay_seconds", "strafe_chain_window_seconds", "full_gait_input_threshold", "torso_turn_in_place_limit_deg", "max_health", "jump_velocity", "gravity", "dive_speed", "dive_duration", "roll_speed", "roll_duration"]:
		result["player." + field] = player.get(field)
	for field: String in ["trooper_scale", "transition_blend_seconds", "dive_roll_trim_duration", "roll_trim_duration", "fire_ready_hold_seconds"]:
		result["animation." + field] = driver.get(field)
	result["animation.clips"] = driver.animation_player.get_animation_list()
	for field: Dictionary in camera.profile.get_property_list():
		if int(field.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(field.usage) & PROPERTY_USAGE_STORAGE:
			result["camera." + String(field.name)] = camera.profile.get(field.name)
	result["model.scale"] = driver.model_root.scale.abs()
	result["scene.traversal_probes"] = player.has_node("TraversalProbes/FloorProbe") and player.has_node("TraversalProbes/StepProbe") and player.has_node("TraversalProbes/WallProbe")
	var collider: CollisionShape3D = player.get_node("CollisionShape3D")
	result["scene.collider_radius"] = collider.shape.radius
	result["scene.collider_height"] = collider.shape.height
	for mesh: MeshInstance3D in driver.model_root.find_children("*", "MeshInstance3D", true, false):
		var material := mesh.get_surface_override_material(0) as ShaderMaterial
		if material != null and material.shader == preload("res://assets/shaders/operator_team_cloth.gdshader"):
			result["model.local_color"] = material.get_shader_parameter("team_color")
			break
	return result

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
