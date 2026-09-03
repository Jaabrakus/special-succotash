extends SceneTree

const EXPECTED_RECOIL := &"combat_fire"
const POSTURES: Array[Dictionary] = [
	{"index": 0, "name": &"STANDING", "fire": &"combat_fire", "reload": &"reload_m4a1"},
	{"index": 1, "name": &"CROUCHED", "fire": &"crouch_fire", "reload": &"reload_m4a1"},
	{"index": 2, "name": &"PRONE", "fire": &"prone_fire", "reload": &"reload_m4a1"},
]

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _steps(45)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var driver := (
		player.get_node_or_null("Mannequin/ProductionAnimation")
		if player != null
		else null
	)
	_expect(player != null and driver != null, "live player animation route exists")
	if player == null or driver == null:
		_finish()
		return

	var clip_paths: Dictionary = driver.get("clip_paths")
	_expect(
		String(clip_paths.get(&"aim_idle_m4a1", "")).ends_with(
			"/weapon_hold/ALS_Props_Rifle_M4A1_Poses.scn"
		),
		"ready aim uses the native AGLS M4 two-hand hold source"
	)
	var animation_player := driver.get("animation_player") as AnimationPlayer
	var aim_idle := animation_player.get_animation(&"aim_idle_m4a1") if animation_player != null else null
	var combat_fire := animation_player.get_animation(&"combat_fire") if animation_player != null else null
	print(
		"AGLS_WEAPON_ACTION_INFO combat_fire_length=%.4f"
		% (combat_fire.length if combat_fire != null else -1.0)
	)
	_expect(
		combat_fire != null
		and is_equal_approx(
			float(combat_fire.get_meta("socom_fire_source_duration_seconds", 0.0)),
			0.233333
		)
		and is_equal_approx(combat_fire.length, 0.353333),
		"rifle fire adds a 0.12 second terminal-pose hold without stretching recoil"
	)
	_expect(aim_idle != null and is_equal_approx(aim_idle.length, 1.0), "rifle hold is a stable one-second loop")
	if aim_idle != null:
		var maximum_keys := 0
		for track in range(aim_idle.get_track_count()):
			maximum_keys = maxi(maximum_keys, aim_idle.track_get_key_count(track))
		_expect(maximum_keys <= 1, "rifle hold freezes the equip action's terminal pose")
	var graph_debug: Dictionary = driver.call("get_animation_debug_state")
	var asset_runtime = driver.get("asset_runtime")
	var attachment := asset_runtime.weapon_attachment as BoneAttachment3D
	var weapon_node := driver.get("weapon_node") as Node3D
	_expect(
		attachment != null and attachment.bone_name == &"ik_hand_gun",
		"M4 is attached to the authored AGLS gun mount bone"
	)
	_expect(
		weapon_node != null
		and weapon_node.position.is_zero_approx()
		and weapon_node.rotation_degrees.is_equal_approx(Vector3(17.7957, -69.83958, 3.188394)),
		"M4 uses the measured AGLS-to-Godot barrel-axis adapter with no position guess"
	)
	var initial_weapon_pose: Dictionary = graph_debug.get("weapon_pose", {})
	_expect(
		bool(initial_weapon_pose.get("authored_animation_owns_weapon_mount", false)),
		"AGLS animation owns the M4 and both hands"
	)
	_expect(
		not bool(initial_weapon_pose.get("hand_socket_ik_enabled", true))
		and not bool(initial_weapon_pose.get("weapon_solver_owned", true)),
		"procedural hand placement and weapon movement are disabled"
	)
	_expect(
		bool(graph_debug.get("rifle_carry_layer_available", false)),
		"authored rifle-carry arm layer exists"
	)
	Input.action_press(&"move_forward")
	await _steps(12)
	graph_debug = driver.call("get_animation_debug_state")
	_expect(
		String(driver.get("current_clip")).begins_with("run_"),
		"standing movement keeps the AGLS locomotion clip"
	)
	_expect(
		is_equal_approx(float(graph_debug.get("rifle_carry_weight", 0.0)), 1.0),
		"running keeps the authored rifle pose on both arms"
	)
	Input.action_release(&"move_forward")
	await _steps(2)
	for posture_case in POSTURES:
		var fire_slot := StringName(posture_case["fire"])
		var reload_slot := StringName(posture_case["reload"])
		_expect(
			String(clip_paths.get(fire_slot, "")).contains("/weapon_recoil/"),
			"%s fire uses an AGLS recoil asset" % posture_case["name"]
		)
		_expect(
			String(clip_paths.get(reload_slot, "")).contains("/weapon_reload/"),
			"%s reload uses an AGLS reload asset" % posture_case["name"]
		)

	for posture_case in POSTURES:
		var posture_name := StringName(posture_case["name"])
		_expect(
			bool(player.call("_try_set_posture", int(posture_case["index"]))),
			"player enters %s" % posture_name
		)
		await _steps(4)
		var before: Dictionary = driver.call("get_animation_debug_state")
		var before_fire_count := int(before.get("fire_trigger_count", 0))
		_expect(bool(driver.call("notify_fired")), "%s accepted fire is presented" % posture_name)
		var fired: Dictionary = driver.call("get_animation_debug_state")
		_expect(
			int(fired.get("fire_trigger_count", 0)) == before_fire_count + 1,
			"%s fire triggers one recoil overlay" % posture_name
		)
		_expect(
			StringName(fired.get("active_fire_clip", &"")) == StringName(posture_case["fire"]),
			"%s fire resolves its posture-specific state" % posture_name
		)
		if posture_name == &"STANDING":
			await _steps(16)
			var terminal_hold: Dictionary = driver.call("get_animation_debug_state")
			_expect(
				bool(terminal_hold.get("fire_terminal_hold_active", false)),
				"standing fire holds the recoil terminal pose before ready handoff"
			)
			await _steps(45)
			var held_ready: Dictionary = driver.call("get_animation_debug_state")
			_expect(
				StringName(driver.get("current_clip")) == &"aim_idle_m4a1",
				"accepted fire enters the AGLS combat-ready idle"
			)
			_expect(
				float(held_ready.get("fire_ready_hold_remaining", 0.0)) > 0.0
				and float(held_ready.get("weapon_ready_weight", 0.0)) >= 0.99,
				"combat-ready remains raised during the 1.2 second hold"
			)
			await _steps(75)
			var relaxed_ready: Dictionary = driver.call("get_animation_debug_state")
			_expect(
				float(relaxed_ready.get("fire_ready_hold_remaining", 1.0)) <= 0.0
				and float(relaxed_ready.get("weapon_ready_weight", 1.0)) < 0.5,
				"combat-ready releases after the timed hold"
			)
		var reload_clip: StringName = driver.call("resolve_semantic_action", &"reload")
		_expect(
			reload_clip == StringName(posture_case["reload"]),
			"%s reload resolves its posture-specific state" % posture_name
		)
		_expect(
			bool(driver.call("play_action", reload_clip)),
			"%s reload starts" % posture_name
		)
		var reloading: Dictionary = driver.call("get_animation_debug_state")
		var count_key := "%s_reload_trigger_count" % (
			"crouched" if posture_name == &"CROUCHED" else String(posture_name).to_lower()
		)
		_expect(
			int(reloading.get(count_key, 0)) >= 1,
			"%s reload uses its posture-preserving overlay" % posture_name
		)
		driver.call("cancel_reload_action")
		await _steps(2)

	var final_debug: Dictionary = driver.call("get_animation_debug_state")
	_expect(bool(final_debug.get("standing_reload_layer_available", false)), "standing reload layer exists")
	_expect(bool(final_debug.get("crouched_reload_layer_available", false)), "crouched reload layer exists")
	_expect(bool(final_debug.get("prone_reload_layer_available", false)), "prone reload layer exists")
	_expect(bool(final_debug.get("strict_authored_pose", false)), "actions run on the native AGLS pose")
	_finish()


func _steps(count: int) -> void:
	for _step in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AGLS_WEAPON_ACTION_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("AGLS_WEAPON_ACTION_CHECK FAIL %s" % label)


func _finish() -> void:
	Input.action_release(&"move_forward")
	if failures.is_empty():
		print("AGLS_WEAPON_ACTION_LIVE_REGRESSION PASS")
		quit(0)
		return
	print("AGLS_WEAPON_ACTION_LIVE_REGRESSION FAIL %s" % [failures])
	quit(1)
