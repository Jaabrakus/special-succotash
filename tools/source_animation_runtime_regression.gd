extends SceneTree

const Policy := preload("res://scripts/player/operator_source_animation_runtime.gd")
const Profile := preload("res://scripts/player/operator_animation_profile.gd")
const Driver := preload("res://scripts/player/operator_animation_driver.gd")
const Weapons := preload("res://scripts/weapons/weapon_rig_contract.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	_run.call_deferred()

func _run() -> void:
	var policy := Policy.new()
	for frame in 1001:
		var x := float(frame) / 1000.0
		_check(absf(policy.blend_curve.sample(x) - Policy.ease(x)) < 0.000001, "original quadratic curve %.3f" % x)
	var expected := {"seal_stand": 6.0, "seal_stand_alert02": 6.0, "seal_crouch": 5.0, "seal_p_stand": 5.0, "seal_p_crouch": 5.0, "seal_run": 0.63333336}
	for name in expected:
		var clip := load("res://assets/animations/seal_reference/%s.tres" % name) as Animation
		var before := clip.length
		var node := AnimationNodeAnimation.new()
		_check(policy.configure_node(node, clip), "native loop enabled: " + name)
		_check(absf(node.timeline_length - float(expected[name])) < 0.000001, "decoded native period: " + name)
		_check(node.stretch_time_scale and node.loop_mode == Animation.LOOP_LINEAR, "one stretched native cycle: " + name)
		_check(clip.length == before, "immutable source length: " + name)
	var valid := (load("res://assets/animations/seal_reference/seal_stand.tres") as Animation).duplicate() as Animation
	for key in ["source_window", "seal_held_source_time", "seal_terminal_closure_removed"]:
		valid.set_meta(key, true)
		_check(Policy.loop_period(valid) < 0.0, "bounded/held action excluded: " + key)
		valid.remove_meta(key)
	valid.loop_mode = Animation.LOOP_NONE
	_check(Policy.loop_period(valid) < 0.0, "one-shot action clock excluded")
	valid.loop_mode = Animation.LOOP_LINEAR
	valid.set_meta("seal_reference", false)
	_check(Policy.loop_period(valid) < 0.0, "nonsource clip excluded")
	_check(Policy.loop_period(null) < 0.0, "missing source excluded")
	var profile := Profile.new()
	profile.load_project_map()
	_check(bool(profile.locomotion.source_runtime_timing), "main enables source periods")
	profile.load_project_map("res://config/animation_presets/seal_pistol_hybrid.json")
	_check(not bool(profile.locomotion.source_runtime_timing), "old preset clears source period opt-in")
	_test_evaluated_timeline(policy)
	await _test_protected_graphs()
	print("SOURCE_ANIMATION_RUNTIME ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " ", failures)
	quit(0 if failures.is_empty() else 1)

func _test_evaluated_timeline(policy: RefCounted) -> void:
	var owner_node := Node3D.new()
	root.add_child(owner_node)
	var marker := Node3D.new()
	marker.name = "Marker"
	owner_node.add_child(marker)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	owner_node.add_child(player)
	var library := AnimationLibrary.new()
	var clip := Animation.new()
	clip.length = 0.5
	clip.loop_mode = Animation.LOOP_LINEAR
	clip.set_meta("seal_reference", true)
	clip.set_meta("source_name", "fixture")
	clip.set_meta("source_settings", {"anim_name": "fixture", "max_velocity": -0.1, "looped": 1.0, "playback": 6.0})
	for axis in ["x", "y"]:
		var track := clip.add_track(Animation.TYPE_VALUE)
		clip.track_set_path(track, NodePath("Marker:position:" + axis))
		clip.track_set_interpolation_loop_wrap(track, false)
		clip.track_insert_key(track, 0.0, 0.0)
		clip.track_insert_key(track, clip.length, 1.0)
	library.add_animation(&"idle", clip)
	player.add_animation_library(&"", library)
	var graph := AnimationNodeBlendTree.new()
	var node := AnimationNodeAnimation.new()
	node.animation = &"idle"
	policy.configure_node(node, clip)
	graph.add_node(&"idle", node)
	graph.connect_node(&"output", 0, &"idle")
	var tree := AnimationTree.new()
	owner_node.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.tree_root = graph
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	tree.advance(0.0)
	for frame in 719:
		tree.advance(1.0 / 60.0)
		var phase := fposmod(float(frame + 1) / 360.0, 1.0)
		var distance := absf(marker.position.x - phase)
		_check(minf(distance, 1.0 - distance) < 0.00003, "evaluated loop phase frame %d" % frame)
		_check(absf(marker.position.x - marker.position.y) < 0.000001, "body and observer channels share stretched clock")
	_check(clip.length == 0.5 and clip.track_get_key_time(0, 1) == 0.5, "timeline never mutates source keys")
	owner_node.free()

func _test_protected_graphs() -> void:
	var driver := Driver.new()
	root.add_child(driver)
	await process_frame
	driver.set_process(false)
	for weapon in ["ak-47", "m4a1", "mark_23"]:
		_check(driver.notify_weapon_equipped(Weapons.load_config("res://config/weapons/%s.json" % weapon)), "protected graph equip " + weapon)
		var graph = driver.locomotion_graph
		var tree := driver.animation_tree.tree_root as AnimationNodeBlendTree
		_check(bool(graph.profile.locomotion.source_runtime_timing), "source timing enabled during action proof " + weapon)
		for name in [&"fire_standing", &"fire_crouched", &"fire_prone", &"crouched_reload_animation", &"standing_reload_animation"]:
			_check(tree.has_node(name), "required action leaf exists %s/%s" % [weapon, name])
			if tree.has_node(name):
				var action := tree.get_node(name) as AnimationNodeAnimation
				_check(action != null and not action.use_custom_timeline, "event/action keeps existing clock %s/%s" % [weapon, name])
		var protected_count := 0
		var jump_count := 0
		for name: StringName in tree.get_node_list():
			if not (String(name).begins_with("legacy_") or String(name).begins_with("modern_state_") or name == &"jump_lower_body_animation"):
				continue
			var leaf := tree.get_node(name) as AnimationNodeAnimation
			if leaf == null: continue
			# Transition pose helpers are deliberately continuous idle/aim inputs;
			# only the exact clip leaf is the action's clock consumer.
			if name != StringName("legacy_" + String(leaf.animation)) and name != StringName("modern_state_" + String(leaf.animation)) and name != &"jump_lower_body_animation":
				continue
			if graph.source_jump_clip(leaf.animation):
				jump_count += 1
				_check(leaf.use_custom_timeline and not leaf.stretch_time_scale and leaf.loop_mode == Animation.LOOP_NONE, "physics-seek jump window retained %s/%s" % [weapon, name])
			else:
				protected_count += 1
				_check(not leaf.use_custom_timeline, "legacy/action/traversal clock retained %s/%s" % [weapon, name])
		_check(protected_count > 200 and jump_count > 0, "canonical protected leaves enumerated " + weapon)
		for name in [&"modern_idle_rifle", &"modern_idle_crouch", &"modern_idle_prone"]:
			var idle := tree.get_node(name) as AnimationNodeAnimation
			_check(idle != null and idle.use_custom_timeline and idle.stretch_time_scale, "continuous idle still consumes source period %s/%s" % [weapon, name])
		# The same native loop may serve a continuous pose and an action event.
		# Action context wins even when a held/static source resource is eligible.
		for clip in [&"seal_pfp_stand", &"idle_prone"]:
			var protected := graph._animation_node(clip, false) as AnimationNodeAnimation
			_check(not protected.use_custom_timeline, "source/static asset cannot override action context %s/%s" % [weapon, clip])
		print("SOURCE_ANIMATION_PROTECTED weapon=", weapon, " action_leaves=", protected_count, " jump_leaves=", jump_count)
	driver.queue_free()
	await process_frame

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok and not failures.has(label): failures.append(label)
