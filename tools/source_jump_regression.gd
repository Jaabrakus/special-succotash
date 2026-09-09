extends SceneTree

const Timeline = preload("res://scripts/player/operator_source_jump_timeline.gd")
const Driver = preload("res://scripts/player/operator_animation_driver.gd")
const Weapons = preload("res://scripts/weapons/weapon_rig_contract.gd")
var failures: Array[String] = []

func _initialize() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	_run.call_deferred()

func _run() -> void:
	for fps: int in [30, 60, 144]:
		var timeline := Timeline.new()
		for frame in int(0.46 * fps):
			var velocity := 5.0 - 22.0 * float(frame) / fps
			var state: Dictionary = timeline.sample(&"AIRBORNE", velocity, frame == 0, 5.0, 0.0, 0.18)
			check(state.slot == (&"jump_up" if velocity > 0 else &"jump_loop"), "latch takeoff despite steering @" + str(fps))
			check(is_equal_approx(float(state.progress), clampf(1.0 - velocity / 5.0 if velocity > 0 else -velocity / 5.0, 0.0, 1.0)), "physics phase @" + str(fps))
		check(timeline.sample(&"AIRBORNE", 0.2, false, 5, 0, 0.18).slot == &"jump_loop", "cannot restart after apex")
		check(timeline.sample(&"LANDING", 0, false, 5, 0.18, 0.18).progress == 1.0, "landing reaches end before recovery finishes")
		check(timeline.sample(&"STANDING", 0, false, 5, 0, 0).is_empty(), "clears on exit")
		check(timeline.sample(&"AIRBORNE", -1, true, 5, 0, 0).slot == &"jump_loop", "ledge does not launch")
	var driver := Driver.new()
	root.add_child(driver)
	await process_frame
	driver.set_process(false)
	var hybrid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/animation_presets/seal_pistol_hybrid.json"))
	check(driver.animation_profile.source_jump == hybrid.source_jump, "main/preset timing parity")
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
				var reference: Animation = driver.animation_player.get_animation(&"seal_stand_alert02")
				var ref_track := reference.find_track(NodePath(".:mixamorig_Hips"),Animation.TYPE_POSITION_3D)
				var anchor := reference.position_track_interpolate(ref_track,0)
				for key in source.track_get_key_count(hip_track):
					check(source.track_get_key_value(hip_track,key).is_equal_approx(anchor),clip_name + " no duplicate jump translation")
			# The decoded terminal sample equals frame zero; never play it for a
			# one-shot. Keep the source asset intact for provenance and previews.
			for track in source.get_track_count():
				if source.track_get_type(track) != Animation.TYPE_ROTATION_3D or source.track_get_key_count(track) < 2: continue
				var first: Quaternion = source.track_get_key_value(track, 0)
				var last: Quaternion = source.track_get_key_value(track, source.track_get_key_count(track) - 1)
				check(first.angle_to(last) < 0.002, clip_name + " verified source closing frame")
		check(not graph.source_jump_clip(&"dive_roll") and not graph.source_jump_clip(&"reload"), "other action policies unchanged")
	driver.queue_free()
	await process_frame
	print("SOURCE_JUMP_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
