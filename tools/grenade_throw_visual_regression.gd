extends SceneTree

const MAIN_SCENE := preload("res://main.tscn")
const GrenadeTimeline := preload(
	"res://scripts/tactical/grenade_animation_release_timeline.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	for _frame in 16:
		await physics_frame
		await process_frame
	var player := main.get("player") as CharacterBody3D
	var mannequin := player.get_node_or_null("Mannequin") as Node if player else null
	var driver: Node = mannequin.get("production_animation") as Node if mannequin else null
	var skeleton := driver.get("skeleton") as Skeleton3D if driver else null
	var animation_player := driver.get("animation_player") as AnimationPlayer if driver else null
	_expect(driver != null and skeleton != null and animation_player != null, "production throw animation stack is live")
	if driver == null or skeleton == null or animation_player == null:
		_finish(main)
		return
	var hand_index := skeleton.find_bone(&"mixamorig_RightHand")
	_expect(hand_index >= 0, "rendered rig exposes the throwing hand")
	_expect(bool(main.call("_equip_or_cycle_grenade")), "grenade equips")
	var grenade_runtime := main.get("grenade_runtime") as Node
	var held_grenade := grenade_runtime.get("held_grenade_mesh") as Node3D if grenade_runtime else null
	var held_attachment := grenade_runtime.get("held_grenade_attachment") as BoneAttachment3D if grenade_runtime else null
	_expect(
		held_grenade != null
		and held_grenade.visible
		and held_grenade.get_node_or_null("TypeVisual") != null,
		"equipped grenade model is attached visibly to the throwing hand"
	)
	if held_attachment != null and held_grenade != null:
		var attachment_scale := held_attachment.global_basis.get_scale()
		var holder_scale := held_grenade.global_basis.get_scale()
		print(
			"GRENADE_HAND_SCALE_METRIC attachment=%s holder=%s"
			% [
				held_attachment.global_basis.get_scale(),
				held_grenade.global_basis.get_scale(),
			]
		)
		_expect(
			attachment_scale.x > 10.0
			and holder_scale.distance_to(Vector3.ONE) <= 0.05,
			"hand attachment cancels the imported rig's oversized bone scale"
		)
	main.call("_begin_grenade_aim")
	main.call("_update_grenade_aim", 0.50)
	var hand_start := skeleton.get_bone_global_pose(hand_index)
	main.call("_release_grenade_aim")
	var requested := StringName(driver.get("requested_action"))
	var animation_tree := driver.get("animation_tree") as AnimationTree
	var graph = driver.get("locomotion_graph")
	var action_duration := float(driver.get("requested_action_total_duration"))
	var action_speed := float(driver.get("requested_action_playback_speed"))
	_expect("grenade" in String(requested).to_lower(), "release requests a grenade clip")
	_expect(StringName(driver.get("current_clip")) == requested, "grenade clip owns the rendered base animation")
	_expect(
		graph != null and StringName(graph.current_state) == requested,
		"modern animation graph enters the requested grenade take"
	)
	await process_frame
	await physics_frame
	_expect(
		animation_tree != null
		and StringName(animation_tree.get("parameters/modern_transition/current_state")) == requested,
		"rendered transition node selects the grenade take"
	)
	var graph_scale_path := StringName(graph.modern_clip_time_scale_paths.get(requested, &"")) if graph != null else &""
	_expect(
		graph_scale_path != &""
		and is_equal_approx(float(animation_tree.get(graph_scale_path)), action_speed)
		and is_equal_approx(animation_player.speed_scale, 1.0),
		"rendered grenade take and gameplay timer use one playback speed"
	)

	var maximum_hand_travel := 0.0
	var maximum_hand_rotation_deg := 0.0
	var elapsed := 0.0
	var release_elapsed := -1.0
	var completion_elapsed := -1.0
	var visible_before_release := held_grenade != null and held_grenade.visible
	for _frame in 240:
		await physics_frame
		await process_frame
		elapsed += 1.0 / 60.0
		var hand_pose := skeleton.get_bone_global_pose(hand_index)
		maximum_hand_travel = maxf(
			maximum_hand_travel,
			hand_start.origin.distance_to(hand_pose.origin)
		)
		maximum_hand_rotation_deg = maxf(
			maximum_hand_rotation_deg,
			rad_to_deg(
				hand_start.basis.get_rotation_quaternion().angle_to(
					hand_pose.basis.get_rotation_quaternion()
				)
			)
		)
		if not bool(main.get("grenade_throw_released")):
			visible_before_release = visible_before_release and held_grenade != null and held_grenade.visible
		elif release_elapsed < 0.0:
			release_elapsed = elapsed
			_expect(
				held_grenade != null and not held_grenade.visible,
				"grenade detaches from the hand on the physical release cue"
			)
		if not bool(main.get("grenade_throw_in_progress")):
			completion_elapsed = elapsed
			break
	print(
		"GRENADE_THROW_VISUAL_METRIC clip=%s speed=%.3f duration=%.3f release=%.3f completion=%.3f hand_travel=%.4f hand_rotation_deg=%.2f"
		% [
			requested,
			action_speed,
			action_duration,
			release_elapsed,
			completion_elapsed,
			maximum_hand_travel,
			maximum_hand_rotation_deg,
		]
	)
	_expect(visible_before_release, "grenade remains in the hand for the full pre-release swing")
	_expect(
		maximum_hand_travel > 0.04 or maximum_hand_rotation_deg > 12.0,
		"rendered throwing hand performs visible authored motion"
	)
	var expected_release := action_duration * GrenadeTimeline.release_fraction(requested)
	_expect(
		release_elapsed >= 0.0 and absf(release_elapsed - expected_release) <= 0.10,
		"physical release matches the authored animation fraction"
	)
	_expect(
		completion_elapsed >= 0.0 and absf(completion_elapsed - action_duration) <= 0.10,
		"throw finishes on the final animation frame"
	)
	_expect(
		is_equal_approx(float(animation_tree.get(graph_scale_path)), 1.0),
		"grenade playback speed resets after the final frame"
	)
	_finish(main)


func _finish(main: Node) -> void:
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("GRENADE_THROW_VISUAL_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("GRENADE_THROW_VISUAL_REGRESSION: %s" % failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("GRENADE_THROW_VISUAL_CHECK PASS ", label)
	else:
		failures.append(label)
