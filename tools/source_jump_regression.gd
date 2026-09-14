extends SceneTree

const Timeline = preload("res://scripts/player/operator_source_jump_timeline.gd")
const Driver = preload("res://scripts/player/operator_animation_driver.gd")
const Weapons = preload("res://scripts/weapons/weapon_rig_contract.gd")
const AnimationCache = preload("res://scripts/player/operator_animation_library_cache.gd")
var failures: Array[String] = []
var saved_map_hash := ""

func _initialize() -> void:
	saved_map_hash = FileAccess.get_sha256("res://config/operator_animation_map.json")
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	if "--without-source-runtime-timing" in OS.get_cmdline_user_args():
		var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_animation_map.json"))
		map.locomotion.source_runtime_timing = false
		ProjectSettings.set_setting("socom/playtest/active_bundle", {"states": {"animation_map": map}})
		ProjectSettings.set_setting("socom/playtest/use_active_bundle", true)
	_run.call_deferred()

func _run() -> void:
	for fps: int in [30, 60, 144]:
		var timeline := Timeline.new()
		for frame in int(0.46 * fps):
			var velocity := 5.0 - 22.0 * float(frame) / fps
			var state: Dictionary = timeline.sample(&"AIRBORNE", velocity, frame == 0, 5.0, 0.0, 0.18)
			check(state.slot == (&"jump_up" if velocity > 0 else &"jump_running_air"), "latch takeoff despite steering @" + str(fps))
			check(is_equal_approx(float(state.progress), clampf(1.0 - velocity / 5.0 if velocity > 0 else -velocity / 5.0, 0.0, 1.0)), "physics phase @" + str(fps))
		check(timeline.sample(&"AIRBORNE", 0.2, false, 5, 0, 0.18).slot == &"jump_running_air", "cannot restart after apex")
		check(timeline.sample(&"LANDING", 0, false, 5, 0.18, 0.18).progress == 1.0, "landing reaches end before recovery finishes")
		check(timeline.sample(&"STANDING", 0, false, 5, 0, 0).is_empty(), "clears on exit")
		check(timeline.sample(&"AIRBORNE", -1, true, 5, 0, 0).slot == &"jump_running_air", "ledge does not launch")
	var driver := Driver.new()
	root.add_child(driver)
	await process_frame
	driver.set_process(false)
	var timing_enabled := bool(driver.animation_profile.locomotion.source_runtime_timing)
	check(timing_enabled == not ("--without-source-runtime-timing" in OS.get_cmdline_user_args()), "process-local timing selection")
	print("SOURCE_JUMP_TIMING source_runtime_timing=", timing_enabled)
	var build_anchor := _build_time_jump_anchor(driver)
	var hybrid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/animation_presets/seal_pistol_hybrid.json"))
	check(driver.animation_profile.source_jump == hybrid.source_jump, "main/preset timing parity")
	var running: Animation = driver.animation_player.get_animation(&"jump_up")
	var standing: Animation = driver.animation_player.get_animation(&"jump_up_standing")
	check(String(running.get_meta("source_asset", "")).ends_with("/jump_up.tres"), "moving jump copies running source")
	check(String(standing.get_meta("source_asset", "")).ends_with("/jump_up_standing.tres"), "stationary jump retains standing source")
	var running_air: Animation = driver.animation_player.get_animation(&"jump_running_air")
	check(String(running_air.get_meta("source_asset", "")).ends_with("/jump_loop.tres"), "running air copies running source")
	var copied: Animation = load("res://assets/animations/seal_gameplay/jump_coherent_run.tres")
	var original: Animation = load("res://assets/animations/seal_gameplay/jump_up.tres")
	for track in copied.get_track_count():
		if copied.track_get_type(track) != Animation.TYPE_ROTATION_3D: continue
		var source_track := original.find_track(copied.track_get_path(track), Animation.TYPE_ROTATION_3D)
		check(source_track >= 0, "running source bone exists")
		if source_track < 0: continue
		for key in copied.track_get_key_count(track):
			var time := copied.track_get_key_time(track, key)
			var actual: Quaternion = copied.track_get_key_value(track, key)
			var expected := original.rotation_track_interpolate(source_track, time * 0.8)
			check(actual.normalized().angle_to(expected.normalized()) < 0.002, "full running launch rotation copied " + str(copied.track_get_path(track)) + " at " + str(time))
	for gun: String in ["ak-47", "m4a1", "mark_23"]:
		driver.weapon_pose_solver.grounded_support_wrist_valid = true
		check(driver.notify_weapon_equipped(Weapons.load_config("res://config/weapons/" + gun + ".json")), "equip " + gun)
		check(not driver.weapon_pose_solver.grounded_support_wrist_valid, "equip clears previous gun grasp")
		var graph = driver.locomotion_graph
		var tree: AnimationNodeBlendTree = driver.animation_tree.tree_root
		for clip_name: String in driver.animation_profile.source_jump.clips:
			var clip := StringName(clip_name)
			check(graph.source_jump_seek_paths.has(clip), clip_name + " canonical seek")
			check(not graph._uses_upper_body_ready_layer(clip), clip_name + " native jump owns torso/arms")
			var node := tree.get_node(StringName("modern_state_" + clip_name)) as AnimationNodeAnimation
			check(node.use_custom_timeline and node.loop_mode == Animation.LOOP_NONE and not node.stretch_time_scale, clip_name + " bounded source timeline")
			var source: Animation = driver.animation_player.get_animation(clip)
			var window: Dictionary = driver.animation_profile.source_jump.clips[clip_name]
			check(float(window.get("start_seconds",0.0)) < node.timeline_length and node.timeline_length < source.length, clip_name + " bounded window excludes closing frame")
			var hip_track := source.find_track(NodePath(".:mixamorig_Hips"),Animation.TYPE_POSITION_3D)
			check(hip_track>=0, clip_name + " has anchored hip track")
			if hip_track>=0:
				for key in source.track_get_key_count(hip_track):
					check(source.track_get_key_value(hip_track,key).is_equal_approx(build_anchor),clip_name + " no duplicate jump translation")
			check(source.has_meta("source_asset"), clip_name + " copied source provenance")
		for pair in [["jump_up", "jump_running_air"], ["jump_up_standing", "jump_loop"], ["pistol_jump", "jump_running_air"], ["jump_running_air", "jump_running_land"], ["jump_loop", "jump_down"], ["jump_loop", "pistol_jump_down"]]:
			var before: Animation = driver.animation_player.get_animation(pair[0])
			var after: Animation = driver.animation_player.get_animation(pair[1])
			for track in before.get_track_count():
				if before.track_get_type(track) != Animation.TYPE_ROTATION_3D: continue
				var next := after.find_track(before.track_get_path(track), Animation.TYPE_ROTATION_3D)
				check(next >= 0, "phase seam has matching bone")
				if next >= 0:
					check(before.rotation_track_interpolate(track, 1.0).angle_to(after.rotation_track_interpolate(next, 0.0)) < 0.002, "phase seam preserves rotation " + str(pair) + " " + str(before.track_get_path(track)))
		check(not graph.source_jump_clip(&"dive_roll") and not graph.source_jump_clip(&"reload"), "other action policies unchanged")
	var other := Driver.new()
	root.add_child(other)
	await process_frame
	other.set_process(false)
	var first_jump: Animation = driver.animation_player.get_animation(&"jump_up")
	var other_jump: Animation = other.animation_player.get_animation(&"jump_up")
	check(first_jump != other_jump, "jump clips are isolated per operator")
	check(driver.animation_player.get_animation(&"run_forward") == other.animation_player.get_animation(&"run_forward"), "non-jump cache stays shared")
	var hip_track := other_jump.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
	var untouched: Vector3 = other_jump.track_get_key_value(hip_track, 0)
	var hip := driver.skeleton.find_bone("mixamorig_Hips")
	var launch: Vector3 = driver.skeleton.get_bone_pose_position(hip) + Vector3(0, -0.003, 0)
	driver.skeleton.set_bone_pose_position(hip, launch)
	driver.asset_runtime.anchor_jump_at_takeoff()
	check(first_jump.position_track_interpolate(hip_track, 0).is_equal_approx(launch), "jump translation uses takeoff pose")
	check(other_jump.track_get_key_value(hip_track, 0).is_equal_approx(untouched), "one player cannot move another player's jump")
	other.queue_free()
	driver.queue_free()
	await process_frame
	check(FileAccess.get_sha256("res://config/operator_animation_map.json") == saved_map_hash, "process-local test never changes saved profile")
	print("SOURCE_JUMP_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _build_time_jump_anchor(driver: Node3D) -> Vector3:
	# _anchor_source_jump_hips runs in the canonical library before the selected
	# rig proportions and stationary source_pose_height adapter. Mutable jumps
	# intentionally skip that later idle-height adapter; live takeoff separately
	# captures the actual evaluated hips, tested below for both player instances.
	var fingerprint := AnimationCache.new().fingerprint_for(driver.animation_profile)
	var canonical := AnimationCache.shared_libraries.get(fingerprint) as AnimationLibrary
	check(canonical != null, "canonical pre-height jump anchor library exists")
	if canonical == null: return Vector3.INF
	var reference_name := StringName(driver.animation_profile.source_jump.anchor_hips_to_clip)
	var reference := canonical.get_animation(reference_name)
	var track := reference.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
	check(track >= 0 and not reference.has_meta("source_pose_height"), "jump anchor reference precedes stationary height adaptation")
	if track < 0: return Vector3.INF
	var anchor := reference.position_track_interpolate(track, 0.0)
	var old_rests: Array = driver.skeleton.get_meta("canonical_rest_before_proportions", [])
	if not old_rests.is_empty():
		var hip: int = driver.skeleton.find_bone("mixamorig_Hips")
		var previous: Vector3 = old_rests[hip].origin
		var current: Vector3 = driver.skeleton.get_bone_rest(hip).origin
		anchor.y *= current.y / previous.y if absf(previous.y) > 0.00001 else 1.0
	var adapted: Animation = driver.animation_player.get_animation(reference_name)
	print("SOURCE_JUMP_ANCHOR build=", anchor, " final_idle=", adapted.position_track_interpolate(track, 0.0), " stationary_height_adapted=", adapted.has_meta("source_pose_height"))
	return anchor

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
