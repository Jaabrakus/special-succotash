extends "res://tools/main_source_motion_proof.gd"

const Profile := preload("res://scripts/player/operator_animation_profile.gd")
const Graph := preload("res://scripts/player/operator_locomotion_blend_tree.gd")
var checks := 0
var checked_movement_frames := 0
var source_candidate := false


func _initialize() -> void:
	output_prefix = "/private/tmp/source-prone-backward-main"
	super._initialize()


func _run() -> void:
	if "--automated-test" in OS.get_cmdline_user_args():
		_check(false, "omit --automated-test; real player commands are required")
		_finish()
		return
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	ProjectSettings.set_setting("socom/session/public_training", true)
	_check_offline_routes()
	source_candidate = "--source-prone-candidate" in OS.get_cmdline_user_args()
	if source_candidate:
		# Explicit isolated candidate only: saved canonical activation was rejected
		# by native floor-contact inspection. Never persist this bundle to disk.
		var collector := root.get_node("PlaytestStateCollector")
		var collected: Dictionary = collector.call("collect_saved_state")
		_check(bool(collected.get("ok", false)), "collect process-local source candidate")
		if collected.get("ok", false):
			var bundle: Dictionary = collector.get("active_bundle").duplicate(true)
			bundle.states.animation_map.locomotion.source_prone_backward = true
			bundle.states.animation_map.clips.prone_backward = bundle.states.animation_map.clips.prone_forward
			collector.set("active_bundle", bundle)
			ProjectSettings.set_setting("socom/playtest/active_bundle", bundle)
			ProjectSettings.set_setting("socom/playtest/use_active_bundle", true)
	if not failures.is_empty():
		_finish()
		return
	scene = load("res://main.tscn").instantiate()
	scene.get_node("IndependentCameraRig").capture_mouse_on_ready = false
	root.add_child(scene)
	player = scene.get_node("Player")
	player.set_local_input_enabled(false)
	scene.get_node("IndependentCameraRig").orbit_input_enabled = false
	# Same canonical aim owner, explicit level test input. The inherited fixture's
	# default downward aim intersects its own floor when the player is prone.
	scene.get_node("IndependentCameraRig").pitch = 0.0
	scene.get_node("IndependentCameraRig").aim_pitch = 0.0
	await _frames(50)
	controller = scene.get_node("WeaponController")
	controller.set_input_enabled(false)
	driver = player.get_node("Mannequin/ProductionAnimation")
	_install_fixture()
	feeder = HeldCommandFeeder.new()
	feeder.actor = player
	feeder.process_physics_priority = -100
	scene.add_child(feeder)
	await _frames(30)
	for gun: String in ["m4a1", "mark_23"]:
		weapon_id = gun
		_check(controller.apply_authorized_weapon_pickup("res://config/weapons/" + gun + ".json"), "canonical equip " + gun)
		_check(player.call("_try_set_posture", 2), "canonical prone posture " + gun)
		await _frames(45)
		var graph: AnimationNodeBlendTree = driver.animation_tree.tree_root
		var space: AnimationNodeBlendSpace1D = graph.get_node(&"prone_space")
		var back: AnimationNodeAnimation = space.get_blend_point_node(0)
		var forward: AnimationNodeAnimation = space.get_blend_point_node(1)
		if source_candidate:
			_check(back.animation == forward.animation and back.animation == &"prone_forward", "candidate same actual source node pair " + gun)
			_check(back.play_mode == AnimationNodeAnimation.PLAY_MODE_BACKWARD, "candidate actual backward mode " + gun)
		else:
			_check(back.animation == &"prone_backward", "canonical prior backward route retained " + gun)
			_check(back.play_mode == AnimationNodeAnimation.PLAY_MODE_FORWARD, "canonical reverse activation stays disabled " + gun)
		_check(forward.play_mode == AnimationNodeAnimation.PLAY_MODE_FORWARD, "forward stays forward " + gun)
		var clip: Animation = driver.animation_player.get_animation(forward.animation)
		_check(clip.get_meta("source_name", "") == "seal_prone_crawl", "actual built clip source " + gun)
		var logical: Animation = driver.animation_player.get_animation(&"prone_backward")
		_check((logical.get_meta("source_name", "") == "seal_prone_crawl") == source_candidate, "logical backward provenance matches selected route " + gun)
		_check(clip.loop_mode == Animation.LOOP_LINEAR, "crawl remains looping " + gun)
		for direction: Vector2 in [Vector2.UP, Vector2.DOWN]:
			var label := gun + ("_forward" if direction == Vector2.UP else "_backward")
			for frame in 20:
				await _command(direction)
			var start := player.global_position
			for frame in 48:
				await _command(direction)
				checked_movement_frames += 1
				_check(player.is_on_floor(), label + " body grounded " + str(frame))
				_check(player.get("posture") == 2, label + " stays prone")
				_check(player.global_transform.is_finite() and player.velocity.is_finite(), label + " finite body")
				_check(driver.skeleton.get_bone_count() == 65, label + " current rig preserved")
				for bone in driver.skeleton.get_bone_count():
					_check(driver.skeleton.get_bone_global_pose(bone).is_finite(), label + " finite bone " + str(bone))
				if frame in [1, 24, 47]:
					await _sample(label + "_move_" + str(frame))
			var displacement := player.global_position - start
			_check(Vector2(displacement.x, displacement.z).length() > .4, label + " actual input moved body")
			_check(Vector2(player.velocity.x, player.velocity.z).length() > .8, label + " existing prone speed remains active")
			var wanted_blend := 1.0 if direction == Vector2.UP else -1.0
			_check(absf(driver.locomotion_graph.prone_travel_blend - wanted_blend) < .025, label + " evaluated direction settles")
			if direction == Vector2.DOWN and _request_shot():
				for frame in 12:
					await _command(direction)
				_check(driver.locomotion_graph.current_state == &"prone", label + " shot preserves prone locomotion")
				await _sample(label + "_fire")
			for frame in 45:
				await _command(Vector2.ZERO)
			_check(Vector2(player.velocity.x, player.velocity.z).length() < .01, label + " release stops body")
			_check(driver.locomotion_graph.current_state == &"idle_prone", label + " releases to idle prone")
	print("SOURCE_PRONE_BACKWARD_MAIN ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " movement_frames=", checked_movement_frames, " source_candidate=", source_candidate, " visual_acceptance=not_claimed")
	_finish()


func _check_offline_routes() -> void:
	var profile := Profile.new()
	profile.load_project_map()
	_check(profile.locomotion.get("source_prone_backward", true) == false, "visually rejected source candidate stays off in saved main")
	var graph := Graph.new()
	graph.profile = profile
	graph.modern_enabled = true
	for policy: Variant in [true, false, "true", 1]:
		profile.locomotion.source_prone_backward = policy
		var space := graph._prone_direction_space(profile.clip_paths)
		var back: AnimationNodeAnimation = space.get_blend_point_node(0)
		var expected_reverse: bool = policy is bool and policy
		_check((back.play_mode == AnimationNodeAnimation.PLAY_MODE_BACKWARD) == expected_reverse, "strict bool opt-in " + str(policy))
		_check(back.animation == (&"prone_forward" if expected_reverse else &"prone_backward"), "off/malformed preserves legacy node " + str(policy))
	profile.locomotion.source_prone_backward = true
	profile.clip_paths[&"prone_forward"] = profile.clip_paths[&"idle_rifle"]
	var invalid := graph._prone_direction_space(profile.clip_paths)
	_check((invalid.get_blend_point_node(0) as AnimationNodeAnimation).play_mode == AnimationNodeAnimation.PLAY_MODE_FORWARD, "non-crawl provenance cannot reverse")
	_check(Profile.new().locomotion.get("source_prone_backward", true) == false, "older profiles default off")
	profile.load_project_map()
	profile.locomotion.source_prone_backward = true
	_check(profile.locomotion.get("source_prone_backward", false) == true, "test prior opt-in enabled before older preset reload")
	profile.load_project_map("res://config/animation_presets/seal_pistol_hybrid.json")
	_check(profile.locomotion.get("source_prone_backward", true) == false, "same profile older preset clears source opt-in")
	var older := graph._prone_direction_space(profile.clip_paths)
	var older_back := older.get_blend_point_node(0) as AnimationNodeAnimation
	_check(older_back.animation == &"prone_backward" and older_back.play_mode == AnimationNodeAnimation.PLAY_MODE_FORWARD, "same profile older preset restores its backward node")


func _sample(state: String) -> void:
	await super._sample(state)
	if not samples.is_empty():
		samples.back()["source_prone_candidate"] = source_candidate
		samples.back()["visual_acceptance"] = "not_claimed; source candidate rejected for knee/floor penetration"


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("SOURCE_PRONE_BACKWARD_FAIL " + label)
