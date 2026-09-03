extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var physics_ticks_before := Engine.physics_ticks_per_second
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical main scene loads")
	if packed == null:
		_finish(physics_ticks_before)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _steps(60)
	# Godot 4.6+ SkeletonModifier3D nodes evaluate in the idle callback after
	# AnimationTree sampling. Read the rendered pose, not the preceding physics
	# boundary where the base animation is intentionally still visible.
	await process_frame

	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var skeleton := scene.get_node_or_null("Player/Model/GeneralSkeleton") as Skeleton3D
	var weapon := scene.get_node_or_null("WeaponController")
	_expect(player != null and skeleton != null and weapon != null, "live AGLS player path is wired")
	if player == null or skeleton == null or weapon == null:
		scene.queue_free()
		_finish(physics_ticks_before)
		return

	var left_hand_ik: TwoBoneIK3D = skeleton.get_node_or_null("LHTwoBoneIK3D") as TwoBoneIK3D
	var left_hand_copy: CopyTransformModifier3D = skeleton.get_node_or_null("LHCopyTransformModifier3D2") as CopyTransformModifier3D
	_expect(
		left_hand_ik != null and left_hand_copy != null,
		"live AGLS skeleton contains native arm and palm modifiers"
	)
	_expect(
		left_hand_ik.active and left_hand_ik.influence > 0.0,
		"native support hand is active in the live ready/locomotion state"
	)

	var visible_muzzle: Vector3 = player.get_node("MuzzleMarker").global_position if player.has_node("MuzzleMarker") else player.global_position + Vector3(0.15, 1.25, -0.65)
	var shot: Dictionary = weapon.call("request_fire")
	_expect(bool(shot.get("fired", false)), "authoritative weapon accepts fire")
	_expect(
		Vector3(shot.get("origin", Vector3.INF)).distance_to(visible_muzzle) <= 0.20,
		"shot authority still starts at the existing visible muzzle"
	)
	await _steps(4)
	await process_frame
	_expect(
		left_hand_ik.active and left_hand_ik.influence > 0.0,
		"fire keeps the native support-hand presentation active"
	)

	var reload_started := bool(player.call("play_socom_action", &"reload"))
	_expect(reload_started, "AGLS reload state starts")
	await _steps(3)
	await process_frame
	_expect(
		left_hand_ik.influence < 0.1,
		"reload releases the native support hand for magazine animation"
	)

	_expect(
		Engine.physics_ticks_per_second == physics_ticks_before,
		"native presentation never changes the global physics tick rate"
	)

	scene.queue_free()
	await process_frame
	_finish(physics_ticks_before)


func _steps(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("NATIVE_IK_GOLD_STANDARD PASS ", label)
	else:
		failures.append(label)
		push_error("NATIVE_IK_GOLD_STANDARD FAIL " + label)


func _finish(physics_ticks_before: int) -> void:
	Engine.physics_ticks_per_second = physics_ticks_before
	if failures.is_empty():
		print("NATIVE_IK_GOLD_STANDARD_LIVE_REGRESSION PASS")
		quit(0)
	else:
		print("NATIVE_IK_GOLD_STANDARD_LIVE_REGRESSION FAIL ", failures)
		quit(1)
