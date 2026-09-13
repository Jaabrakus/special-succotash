extends SceneTree

const DRIVER = preload("res://scripts/player/operator_animation_driver.gd")
const WEAPON_CONTRACT = preload("res://scripts/weapons/weapon_rig_contract.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/animation_presets/seal_gameplay_candidate.json"))
	ProjectSettings.set_setting("socom/playtest/active_bundle", {"states": {"animation_map": map}})
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", true)
	_run.call_deferred()

func _run() -> void:
	var driver = DRIVER.new()
	root.add_child(driver)
	await process_frame
	var guns: Array[String] = ["ak-47"]
	for file in DirAccess.get_files_at("res://config/weapons"):
		if not file.ends_with(".json"):
			continue
		var config: Dictionary = WEAPON_CONTRACT.load_config("res://config/weapons/" + file)
		if config.get("handling_profile", {}).get("family", "") == "TWO_HAND_PISTOL":
			guns.append(file.get_basename())
	check(guns.has("mark_23") and guns.has("m9") and guns.has("de__50"), "normalized pistol catalog includes sparse M9 and DE profiles")
	for gun in guns:
		var weapon: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/" + gun + ".json"))
		check(driver.notify_weapon_equipped(weapon), gun + " equipped")
		var pistol: bool = gun != "ak-47"
		var graph = driver.locomotion_graph
		graph._publish_ready_mask(&"STANDING", 1.0, 0.0)
		check(is_zero_approx(graph.upper_body_ready_blend) and is_zero_approx(graph.locomotion_carry_weight), gun + " relaxed source locomotion has no carry overlay")
		graph._publish_ready_mask(&"STANDING", 1.0, 1.0)
		check(is_zero_approx(graph.upper_body_ready_blend), gun + " firing gait has no stationary torso overwrite")
		check(is_equal_approx(float(driver.animation_tree.get("parameters/standing_source_ready/blend_amount")), 1.0), gun + " source firing gait fully selected")
		check(graph.jump_lower_body_clip == &"", gun + " no replacement jump-leg layer")
		var tree: AnimationNodeBlendTree = driver.animation_tree.tree_root
		for prefix: String in ["walk", "run", "crouch"]:
			var ready_space: AnimationNodeBlendSpace2D = tree.get_node("firing_" + prefix + "_space")
			check(ready_space.get_blend_point_count() == (5 if prefix == "crouch" else 4), gun + " firing cardinal sources")
			for point in ready_space.get_blend_point_count():
				var name: StringName = (ready_space.get_blend_point_node(point) as AnimationNodeAnimation).animation
				var clip: Animation = driver.animation_player.get_animation(name)
				check(clip != null and clip.get_meta("seal_reference", false), gun + " firing source provenance " + str(name))
				check(clip != null and clip.loop_mode == Animation.LOOP_LINEAR, gun + " firing gait loops " + str(name))
				if ready_space.get_blend_point_name(point) in [&"forward", &"backward", &"center"]:
					check(String(name).begins_with("seal_pfp_" if pistol else "seal_fp_"), gun + " uses actual firing family")
				if prefix == "run" and ready_space.get_blend_point_name(point) == &"left":
					check(name == (&"seal_p_lstrafe_fast" if pistol else &"seal_lstrafe_fast"), gun + " authored fast left strafe, no right-side mirror")
		for prefix: String in ["walk", "run", "crouch"]:
			var space: AnimationNodeBlendSpace2D = tree.get_node({"walk": "walk_space", "run": "full_space", "crouch": "crouch_space"}[prefix])
			check(space.get_blend_point_count() == (5 if prefix == "crouch" else 4), gun + " " + prefix + " only native cardinal points")
			for point in space.get_blend_point_count():
				var name: StringName = (space.get_blend_point_node(point) as AnimationNodeAnimation).animation
				check(String(driver.clip_paths.get(name, "")).begins_with("res://assets/animations/seal_gameplay/"), gun + " " + str(name) + " source locomotion")
				if pistol and prefix == "crouch":
					check(String(name).begins_with("pistol_crouch_"), gun + " actual pistol crouch take")
		driver.movement_state = &"AIRBORNE"
		driver._locomotion_active = true
		for vertical: float in [3.0, 0.0, -3.0]:
			driver.vertical_speed = vertical
			var expected_jump := &"pistol_jump" if pistol else &"jump_up"
			check(driver._select_visual_clip() == (expected_jump if vertical > 1.0 else &"jump_loop"), gun + " jump phase " + str(vertical))
		driver.movement_state = &"LANDING"
		check(driver._select_visual_clip() == (&"pistol_jump_down" if pistol else &"jump_down"), gun + " source landing")
		driver.movement_state = &"LOCOMOTION"
		driver._locomotion_active = false
		check(driver._equipped_action_clip("idle_prone", &"idle_prone") == graph._weapon_action_clip("idle_prone", &"idle_prone", driver.available_clips), gun + " driver and graph share family contract")
		for ready_node in ["modern_aim_idle", "crouch_idle_aim_idle", "standing_upper_aim_idle", "crouch_upper_aim_idle"]:
			var ready_clip: StringName = (tree.get_node(ready_node) as AnimationNodeAnimation).animation
			var animation: Animation = driver.animation_player.get_animation(ready_clip)
			check(animation != null and animation.get_meta("seal_firing_pose", false), gun + " " + ready_node + " actual source firing stance")
		var expected := {"modern_idle_rifle": "pistol_compressed_idle_standing" if pistol else "idle_rifle", "modern_idle_crouch": "pistol_compressed_idle_crouched" if pistol else "idle_crouch", "modern_idle_prone": "pistol_idle_prone" if pistol else "idle_prone"}
		# Rifle idle is now selected by the saved equipped-weapon contract, not
		# the historical fallback name. Keep provenance checks below intact.
		if not pistol:
			expected["modern_idle_rifle"] = String(graph._weapon_action_clip("idle_standing", &"idle_rifle", driver.available_clips))
		for node_name: String in expected:
			var selected: String = str((tree.get_node(node_name) as AnimationNodeAnimation).animation)
			check(selected == expected[node_name], gun + " " + node_name + " selects " + expected[node_name])
			check(str(driver.clip_paths.get(StringName(selected), "")).begins_with("res://assets/animations/seal_gameplay/"), selected + " native SEAL source")
		var fire := {"STANDING": "pistol_fire" if pistol else "combat_fire", "CROUCHED": "pistol_fire" if pistol else "crouch_fire", "PRONE": "pistol_prone_fire" if pistol else "prone_fire"}
		for stance: String in fire:
			driver.posture = StringName(stance)
			var selected: StringName = driver.animation_profile.resolve_animation_event(&"FIRE_ACCEPTED", driver.posture, driver.equipped_weapon_family)
			check(str(selected) == fire[stance], gun + " " + stance + " event route")
			check(not driver._fire_uses_aim_idle(selected), gun + " " + stance + " legacy ready override bypassed")
			var count: int = graph.fire_trigger_count
			check(driver.notify_fired(), gun + " " + stance + " accepted visual event")
			var pose = driver.weapon_pose_solver
			pose.fire_recoil.advance(pose.fire_recoil.attack)
			pose.seal_source_pose_active = true
			check(is_zero_approx(pose._elbow_presentation_angle(driver.posture, &"LOCOMOTION", 1.0, &"", true, -1.0)), gun + " " + stance + " no duplicate source elbow kick")
			pose.seal_source_pose_active = false
			check(pose._elbow_presentation_angle(driver.posture, &"LOCOMOTION", 1.0, &"", false, 0.0) > 0.0, gun + " " + stance + " legacy recoil preserved")
			pose.seal_source_pose_active = true
			check(graph.fire_trigger_count == count + 1 and graph.active_fire_clip == selected, gun + " " + stance + " actual one-shot fired")
			var clip: Animation = driver.animation_player.get_animation(selected)
			check(clip != null and clip.loop_mode == Animation.LOOP_NONE, str(selected) + " one-shot source")
			check(graph.fire_layer_node.filter_enabled, str(selected) + " upper-body layer retains stance legs")
			if stance == "PRONE":
				for bone in ["RightArm", "RightForeArm", "LeftArm", "LeftForeArm"]:
					check(not graph.fire_layer_node.is_path_filtered(NodePath(".:mixamorig_" + bone)), gun + " prone shot retains planted " + bone)
			if clip != null:
				driver.animation_tree.advance(clip.length + 0.1)
	driver.queue_free()
	await process_frame
	for failure: String in failures:
		push_error(failure)
	print("SEAL_COMBAT_POSE ", "PASS" if failures.is_empty() else "FAIL", " pistols=", guns.size() - 1, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
