extends SceneTree

## Read-only evidence: native retarget -> canonical library -> pistol graph mask.
## No saved profile or animation asset is modified by this diagnostic.
const Driver = preload("res://scripts/player/operator_animation_driver.gd")
const Weapons = preload("res://scripts/weapons/weapon_rig_contract.gd")
var failures: Array[String] = []

func _initialize() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	_run.call_deferred()

func _run() -> void:
	var driver := Driver.new()
	root.add_child(driver)
	await process_frame
	driver.set_process(false)
	driver.animation_tree.active = false
	var report := {"scope": "base asset/library/graph only, not rendered parity", "library": [], "legacy_upper": [], "candidate": {}}
	for clip_name: StringName in [&"run_forward", &"pistol_run_forward", &"pistol_run_left", &"pistol_run_right", &"pistol_crouch_forward"]:
		var disk := load(String(driver.clip_paths[clip_name])) as Animation
		var runtime: Animation = driver.animation_player.get_animation(clip_name)
		var comparison := compare(disk, runtime, [])
		comparison["clip"] = String(clip_name)
		comparison["path"] = String(driver.clip_paths[clip_name])
		comparison["source_name"] = String(disk.get_meta("source_name", ""))
		comparison["source_duration"] = disk.length
		comparison["runtime_duration"] = runtime.length
		check(is_equal_approx(disk.length, runtime.length), "library preserves duration " + String(clip_name))
		report.library.append(comparison)
	check(driver.notify_weapon_equipped(Weapons.load_config("res://config/weapons/mark_23.json")), "pistol equips")
	driver.animation_tree.active = false
	var graph = driver.locomotion_graph
	var active_legacy: bool = graph.PistolUpperLayer.enabled(graph)
	report["canonical_legacy_enabled"] = active_legacy
	if active_legacy:
		graph.PistolUpperLayer.update(graph, &"STANDING", 0.0, true, 0.2)
		report["legacy_upper_weight_after_200ms"] = driver.animation_tree.get("parameters/legacy_pistol_upper/blend_amount")
		var mask: AnimationNodeBlend2 = driver.animation_tree.tree_root.get_node(&"legacy_pistol_upper")
		check(mask.is_path_filtered(NodePath(".:mixamorig_RightArm")), "legacy mask covers trigger arm")
		check(not mask.is_path_filtered(NodePath(".:mixamorig_Hips")), "legacy mask does not replace hips")
	for pair in [["pistol_run_forward", "legacy_pistol_idle_standing"], ["pistol_run_left", "legacy_pistol_idle_standing"], ["pistol_run_right", "legacy_pistol_idle_standing"], ["pistol_crouch_forward", "legacy_pistol_idle_crouched"], ["seal_pfp_run", "legacy_pistol_ready_standing"], ["seal_pfp_crouchwalk", "legacy_pistol_ready_crouched"]]:
		var source: Animation = driver.animation_player.get_animation(StringName(pair[0]))
		var overlay: Animation = driver.animation_player.get_animation(StringName(pair[1]))
		var comparison := compare(source, overlay, graph.UPPER_BODY_BONES)
		comparison["native"] = pair[0]
		comparison["override"] = pair[1]
		report.legacy_upper.append(comparison)
	# Candidate lives only in this diagnostic's driver instance.
	driver.animation_profile.locomotion["legacy_pistol_upper_body"] = false
	var slots: Dictionary = driver.animation_profile.family_animation_slots["TWO_HAND_PISTOL"]
	for slot in ["ready_standing", "ready_standing_moving"]:
		slots[slot] = "seal_pfp_stand"
	for slot in ["ready_crouched", "ready_crouched_moving"]:
		slots[slot] = "seal_pfp_crouch"
	var fire: Dictionary = driver.animation_profile.event_routes.FIRE_ACCEPTED.family_states.TWO_HAND_PISTOL.posture_states
	fire.STANDING = "seal_pfp_stand"
	fire.CROUCHED = "seal_pfp_crouch"
	check(driver.notify_weapon_equipped(Weapons.load_config("res://config/weapons/mark_23.json")), "candidate re-equips")
	driver.animation_tree.active = false
	graph = driver.locomotion_graph
	check(not driver.animation_tree.tree_root.has_node(&"legacy_pistol_upper"), "candidate removes fallback mask")
	for posture in ["standing", "crouched"]:
		var resolved: StringName = driver._equipped_action_clip("ready_" + posture, &"aim_idle")
		report.candidate["ready_" + posture] = String(resolved)
		check(resolved == (&"seal_pfp_stand" if posture == "standing" else &"seal_pfp_crouch"), "candidate source ready " + posture)
	var rate: float = driver.animation_profile.playback_rate(6.5, &"STANDING", 1.0)
	report["forward_6_5mps_playback_rate"] = rate
	report["forward_source_vs_wallclock_seconds"] = {"rifle": driver.animation_player.get_animation(&"run_forward").length / rate, "pistol": driver.animation_player.get_animation(&"pistol_run_forward").length / rate}
	print("SOURCE_POSE_AUDIT ", JSON.stringify(report))
	driver.queue_free()
	await process_frame
	print("SOURCE_POSE_AUDIT ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func compare(first: Animation, second: Animation, selected_bones: Array) -> Dictionary:
	var maximum := 0.0
	var maximum_bone := ""
	var sum := 0.0
	var count := 0
	var lower_max := 0.0
	var upper_max := 0.0
	var hip_max_m := 0.0
	for track in first.get_track_count():
		var bone := String(first.track_get_path(track)).get_slice(":", 1)
		if not selected_bones.is_empty() and StringName(bone) not in selected_bones:
			continue
		var other := second.find_track(first.track_get_path(track), first.track_get_type(track))
		if other < 0:
			continue
		for frame in 61:
			var phase := float(frame) / 61.0
			if first.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				var a := first.rotation_track_interpolate(track, phase * first.length)
				var b := second.rotation_track_interpolate(other, phase * second.length)
				var relative := a.normalized().inverse() * b.normalized()
				# atan2 avoids acos magnifying float32 dot noise for equal keys.
				var angle := rad_to_deg(2.0 * atan2(Vector3(relative.x, relative.y, relative.z).length(), absf(relative.w)))
				if angle > maximum:
					maximum = angle
					maximum_bone = bone
				var lower := "Leg" in bone or "Foot" in bone or "Toe" in bone or "Hips" in bone
				if lower:
					lower_max = maxf(lower_max, angle)
				else:
					upper_max = maxf(upper_max, angle)
				sum += angle
				count += 1
			elif first.track_get_type(track) == Animation.TYPE_POSITION_3D and bone == "mixamorig_Hips":
				hip_max_m = maxf(hip_max_m, first.position_track_interpolate(track, phase * first.length).distance_to(second.position_track_interpolate(other, phase * second.length)) * 62.0)
	return {"samples": count, "maximum_local_rotation_degrees": maximum, "maximum_bone": maximum_bone, "mean_local_rotation_degrees": sum / maxf(count, 1.0), "lower_max_degrees": lower_max, "upper_max_degrees": upper_max, "hip_max_displacement_m": hip_max_m}

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
