extends SceneTree

const MAIN_SCENE := preload("res://main.tscn")
const GrenadeReleaseTimeline := preload(
	"res://scripts/tactical/grenade_animation_release_timeline.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	for _frame in 12:
		await process_frame

	_expect(_action_has_key(&"reload_weapon", KEY_R), "R belongs to weapon reload")
	_expect(not _action_has_key(&"reset_camera", KEY_R), "R no longer resets the camera")
	_expect(_action_has_key(&"reset_camera", KEY_HOME), "Home owns manual camera reset")
	_expect(
		InputMap.has_action(&"equip_grenade")
		and not InputMap.action_get_events(&"equip_grenade").is_empty(),
		"the saved gameplay binding owns grenade equip and cycling"
	)
	_expect(
		not InputMap.has_action(&"throw_grenade") and not InputMap.has_action(&"cycle_grenade"),
		"separate grenade throw and cycle actions are removed"
	)
	var camera_rig: Node3D = main.get("camera_rig") as Node3D
	var yaw_before := float(camera_rig.get("yaw")) if camera_rig else 0.0
	var mannequin := main.get("player").get_node_or_null("Mannequin") as Node
	var driver: Node = mannequin.get("production_animation") as Node if mannequin else null
	var weapon_controller: Node = main.get("weapon_controller") as Node
	weapon_controller.set("rounds_in_magazine", 5)
	weapon_controller.set("reserve_rounds", 20)
	var test_reload_pose := {
		"joint_rotations": {
			"spine2": {"x": 6.0, "y": -3.0, "z": 1.0},
		},
		"weapon_hand_position_correction": {"x": 0.0, "y": 0.0, "z": 0.0},
		"weapon_hand_rotation_correction_deg": {"x": 12.0, "y": -8.0, "z": 2.0},
	}
	if driver != null and driver.get("animation_frame_pose_runtime") != null:
		driver.get("animation_frame_pose_runtime").configure({
			"reload": {
				"0": test_reload_pose,
				"999": test_reload_pose,
			},
		})
	_expect(bool(main.call("_request_weapon_reload")), "reload input starts the equipped reload action")
	_expect(
		int(weapon_controller.get("rounds_in_magazine")) == 5,
		"reload does not refill ammunition before the animation completes"
	)
	_expect(
		driver != null and "reload" in String(driver.get("requested_action")).to_lower(),
		"reload uses the posture-aware equipped animation"
	)
	_expect(
		camera_rig != null and is_equal_approx(float(camera_rig.get("yaw")), yaw_before),
		"reload does not move camera yaw"
	)
	for _frame in 12:
		await process_frame
	var reload_pose: Dictionary = (
		driver.get("weapon_pose_solver").call("get_debug_state")
		if driver != null and driver.get("weapon_pose_solver") != null
		else {}
	)
	_expect(
		bool(reload_pose.get("action_weapon_follow_active", false)),
		"reload transfers visual rifle ownership to the authored right hand"
	)
	_expect(
		float(reload_pose.get("action_trigger_contact_error_m", 1.0)) <= 0.003,
		"gameplay reload keeps the Gunsmith trigger socket on the palm"
	)
	_expect(
		Vector3(reload_pose.get(
			"animation_frame_weapon_rotation_correction_deg",
			Vector3.ZERO
		)).is_equal_approx(Vector3(12.0, -8.0, 2.0)),
		"gameplay reload consumes the Gunsmith frame-local weapon pitch and yaw"
	)
	_expect(
		StringName(reload_pose.get("support_hand_mode", &"")) == &"ANIMATION_FREE",
		"reload releases only the left foregrip IK before the saved regrip frame"
	)
	_expect(
		(reload_pose.get("ownership_conflicts", []) as Array).is_empty(),
		"reload has one rifle owner and one owner for each arm region"
	)
	var reload_snapshot: Dictionary = driver.call("get_animation_debug_state") if driver != null else {}
	var sampled_frame_pose: Dictionary = reload_snapshot.get("animation_frame_pose", {})
	_expect(
		String(sampled_frame_pose.get("resolved_clip_key", "")) == "reload"
		and bool(sampled_frame_pose.get("pose_active", false))
		and int(reload_snapshot.get("animation_frame_rotation_override_count", 0)) > 0,
		"gameplay reload consumes the Gunsmith torso correction layer"
	)
	driver.call("_update_requested_action", float(driver.get("requested_action_remaining")) + 0.01)
	_expect(
		int(weapon_controller.get("rounds_in_magazine")) > 5
		and not bool(main.get("reload_commit_pending")),
		"reload refills ammunition exactly when the animation completes"
	)

	_expect(bool(main.call("_equip_or_cycle_grenade")), "G equips the first available grenade")
	var grenade_driver: Node = mannequin.get("production_animation") as Node if mannequin else null
	_expect(
		grenade_driver != null
		and "grenade" not in String(grenade_driver.get("requested_action")).to_lower()
		and not bool((grenade_driver.get("weapon_node") as Node3D).visible),
		"equipping a grenade holsters the rifle without playing the throw animation"
	)
	var inventory_before: Dictionary = (main.get("grenade_inventory") as Dictionary).duplicate(true)
	main.call("_begin_grenade_aim")
	_expect(bool(main.get("grenade_aim_active")), "grenade input enters hold-to-aim instead of throwing immediately")
	main.call("_update_grenade_aim", 0.50)
	var arc_preview := main.get("grenade_arc_preview") as MeshInstance3D
	var charge_panel := main.get("grenade_charge_panel") as PanelContainer
	var charge_bar := main.get("grenade_charge_bar") as ProgressBar
	var predicted_launch_velocity := Vector3(arc_preview.get_meta(
		"predicted_launch_velocity",
		Vector3.INF
	)) if arc_preview != null else Vector3.INF
	_expect(
		arc_preview != null
		and arc_preview.visible
		and arc_preview.mesh != null
		and arc_preview.mesh.get_surface_count() >= 2
		and int(arc_preview.get_meta("predicted_path_point_count", 0)) > 2
		and int(arc_preview.get_meta("predicted_bounce_count", 0)) >= 1
		and Vector3(arc_preview.get_meta(
			"predicted_landing_position",
			Vector3.INF
		)).is_finite(),
		"holding grenade input draws impact, bounce, and final landing prediction"
	)
	var arc_origin: Vector3 = main.call("_grenade_arc_origin")
	var right_shoulder: Vector3 = main.call(
		"_operator_bone_world_position",
		&"mixamorig_RightArm"
	)
	var player_body := main.get("player") as Node3D
	_expect(
		arc_origin.is_finite()
		and right_shoulder.is_finite()
		and (arc_origin - right_shoulder).dot(player_body.global_basis.z) > 0.10,
		"grenade arc begins behind the animated right shoulder"
	)
	_expect(
		charge_panel != null and charge_panel.visible and charge_bar != null and charge_bar.value > 0.0,
		"holding grenade input displays human-limited throw strength"
	)
	main.call("_release_grenade_aim")
	_expect(
		not bool(main.get("grenade_aim_active"))
		and bool(main.get("grenade_equipped"))
		and bool(main.get("grenade_throw_in_progress"))
		and arc_preview.visible
		and not charge_panel.visible,
		"releasing fire keeps the arc visible through the authored wind-up"
	)
	_expect(
		grenade_driver != null
		and "grenade" in String(grenade_driver.get("requested_action")).to_lower()
		and is_equal_approx(
			(grenade_driver.get("animation_player") as AnimationPlayer).speed_scale,
			1.0
		)
		and float((grenade_driver.get("animation_tree") as AnimationTree).get(
			(grenade_driver.get("locomotion_graph")).modern_clip_time_scale_paths[
				StringName(grenade_driver.get("requested_action"))
			]
		)) > 1.0
		and not bool(player_body.get("local_input_enabled"))
		and not bool((grenade_driver.get("weapon_node") as Node3D).visible),
		"short gameplay release accelerates the rendered take, locks movement, and hides the rifle"
	)
	var grenade_clip := StringName(grenade_driver.get("requested_action"))
	var grenade_animation_duration := float(
		grenade_driver.get("requested_action_total_duration")
	)
	var release_fraction := GrenadeReleaseTimeline.release_fraction(grenade_clip)
	grenade_driver.call(
		"_update_requested_action",
		grenade_animation_duration * (release_fraction - 0.02)
	)
	var inventory_before_release_cue: Dictionary = main.get("grenade_inventory") as Dictionary
	_expect(
		int(inventory_before_release_cue.get("frag", 0)) == int(inventory_before.get("frag", 0))
		and bool(main.get("grenade_throw_in_progress"))
		and not bool(player_body.get("local_input_enabled")),
		"grenade stays in hand and movement stays locked before the authored release motion"
	)
	grenade_driver.call(
		"_update_requested_action",
		grenade_animation_duration * 0.04
	)
	var inventory_at_release_cue: Dictionary = main.get("grenade_inventory") as Dictionary
	_expect(
		int(inventory_at_release_cue.get("frag", 0)) == int(inventory_before.get("frag", 0)) - 1
		and bool(main.get("grenade_throw_in_progress"))
		and not bool(player_body.get("local_input_enabled")),
		"the authored throw motion launches one grenade before the animation ends"
	)
	var launched_grenades := main.get_tree().get_nodes_in_group("tactical_grenades")
	var launched_grenade := (
		launched_grenades.back() as TacticalGrenadeBase
		if not launched_grenades.is_empty()
		else null
	)
	var release_cue_origin := Vector3(arc_preview.get_meta(
		"predicted_launch_origin",
		Vector3.INF
	))
	var release_cue_velocity := Vector3(arc_preview.get_meta(
		"predicted_launch_velocity",
		Vector3.INF
	))
	_expect(
		launched_grenade != null
		and Vector3(launched_grenade.get_meta(
			"authoritative_launch_origin",
			Vector3.INF
		)).distance_to(release_cue_origin) <= 0.001
		and Vector3(launched_grenade.get_meta(
			"authoritative_launch_velocity",
			Vector3.INF
		)).distance_to(release_cue_velocity) <= 0.001
		and release_cue_velocity.distance_to(predicted_launch_velocity) <= 0.001
		and not arc_preview.visible,
		"the release cue launches from the animated hand with the arc's saved velocity"
	)
	_expect(
		launched_grenade != null and launched_grenade.continuous_cd,
		"the live grenade enables continuous collision detection"
	)
	grenade_driver.call(
		"_update_requested_action",
		maxf(float(grenade_driver.get("requested_action_remaining")) - 0.01, 0.0)
	)
	_expect(
		bool(main.get("grenade_throw_in_progress"))
		and not bool(player_body.get("local_input_enabled"))
		and "grenade" in String(grenade_driver.get("current_clip")).to_lower(),
		"the grenade take owns the rendered body through its final animation frame"
	)
	grenade_driver.call(
		"_update_requested_action",
		float(grenade_driver.get("requested_action_remaining")) + 0.01
	)
	_expect(
		not bool(main.get("grenade_throw_in_progress"))
		and bool(player_body.get("local_input_enabled"))
		and not bool((grenade_driver.get("weapon_node") as Node3D).visible),
		"movement unlocks after the throw while the equipped grenade keeps the rifle holstered"
	)

	main.call("_begin_grenade_aim")
	main.call("_update_grenade_aim", 0.25)
	var inventory_before_jump: Dictionary = (main.get("grenade_inventory") as Dictionary).duplicate(true)
	main.call("_release_grenade_aim")
	main.call("_cancel_grenade_for_jump")
	await create_timer(0.45).timeout
	var inventory_after_jump: Dictionary = main.get("grenade_inventory") as Dictionary
	_expect(
		not bool(main.get("grenade_equipped"))
		and not bool(main.get("grenade_throw_in_progress"))
		and int(inventory_after_jump.get("frag", 0)) == int(inventory_before_jump.get("frag", 0))
		and "grenade" not in String(grenade_driver.get("requested_action")).to_lower()
		and bool(player_body.get("local_input_enabled"))
		and bool((grenade_driver.get("weapon_node") as Node3D).visible),
		"Jump cancels the pending throw, consumes nothing, and restores the rifle"
	)

	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("RELOAD_INPUT_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("RELOAD_INPUT_REGRESSION: %s" % failure)
	quit(1)


func _action_has_key(action: StringName, keycode: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			var mapped_code: Key = (
				key_event.physical_keycode
				if key_event.physical_keycode != 0
				else key_event.keycode
			)
			if mapped_code == keycode:
				return true
	return false


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
