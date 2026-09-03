extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://scenes/labs/native_ik_player_lab.tscn") as PackedScene
	_expect(packed != null, "native IK player lab loads")
	if packed == null:
		_finish()
		return
	var lab := packed.instantiate()
	root.add_child(lab)
	for _frame in range(120):
		await process_frame
	var player := lab.get_node_or_null("Player")
	var skeleton := player.get_node_or_null("Model/GeneralSkeleton") as Skeleton3D
	var animation_player := player.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var animation_tree := player.get_node_or_null("AnimationTree") as AnimationTree
	var block_gun := player.get_node_or_null(
		"Model/GeneralSkeleton/RShoulderBoneAttachment3D2/WeaponHolder/Gun"
	)
	_expect(
		player is CharacterBody3D and player.has_method("play_socom_action"),
		"replacement controller owns the reference CharacterBody3D"
	)
	_expect(skeleton != null and skeleton.get_bone_count() == 68, "reference 68-bone character skeleton is live")
	_expect(block_gun != null, "reference square block gun is live")
	_expect(
		skeleton != null
		and skeleton.get_node_or_null("LHTwoBoneIK3D") is TwoBoneIK3D
		and skeleton.get_node_or_null("LHCopyTransformModifier3D2") is CopyTransformModifier3D,
		"reference procedural support-hand modifier stack is live"
	)
	var graph := animation_tree.tree_root as AnimationNodeBlendTree
	_expect(
		graph != null
		and graph.has_node(&"ReloadUpperBody")
		and graph.has_node(&"ReloadAnimation")
		and graph.has_node(&"CombatFireUpperBody")
		and graph.has_node(&"CombatFireAnimation"),
		"editor-visible AnimationTree contains reload and combat-fire layers"
	)
	_expect(bool(player.get("socom_clips_ready")), "selected old SOCOM animations retarget successfully")
	var expected := [
		&"idle_crouch", &"crouch_forward", &"idle_prone", &"prone_forward",
		&"prone_fire", &"prone_reload", &"combat_fire", &"reload",
		&"grenade_toss", &"dive_roll"
	]
	for clip_name: StringName in expected:
		_expect(
			animation_player.has_animation(&"SOCOM/" + clip_name),
			"old animation %s is present on the reference skeleton" % clip_name
		)
	var started := bool(player.call("play_socom_action", &"prone_fire"))
	await process_frame
	_expect(started, "old prone-fire state starts")
	_expect(not animation_tree.active, "old action temporarily owns presentation without a competing graph writer")
	_expect(
		StringName(player.get("active_socom_clip")) == &"prone_fire",
		"controller reports the old prone-fire state"
	)
	_expect(
		(animation_player.get_animation(&"SOCOM/prone_fire") as Animation).get_track_count() >= 20,
		"old prone-fire drives a full retargeted body pose"
	)
	player.call("_stop_socom_action")
	var fire_started := bool(player.call("notify_operator_fired"))
	for _frame in range(4):
		await process_frame
	_expect(fire_started, "accepted-fire presentation triggers CombatFireUpperBody")
	_expect(animation_tree.active, "combat fire keeps the purchased AnimationTree active")
	_expect(
		bool(animation_tree.get("parameters/CombatFireUpperBody/active")),
		"combat-fire upper-body OneShot is active"
	)
	_expect(
		is_equal_approx(float((skeleton.get_node("LHTwoBoneIK3D") as TwoBoneIK3D).influence), 1.0)
		and is_equal_approx(float((skeleton.get_node("LHCopyTransformModifier3D2") as CopyTransformModifier3D).influence), 1.0),
		"combat fire preserves purchased two-hand gun placement"
	)
	animation_tree.set(
		"parameters/CombatFireUpperBody/request",
		AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT
	)
	for _frame in range(4):
		await process_frame
	player.call("_stop_socom_action")
	Input.action_press(&"forward", 1.0)
	for _frame in range(8):
		await physics_frame
	var reload_start: Vector3 = player.global_position
	var reload_started := bool(player.call("play_socom_action", &"reload"))
	for _frame in range(4):
		await process_frame
	print(
		"NATIVE_IK_RELOAD_DEBUG request=",
		animation_tree.get("parameters/ReloadUpperBody/request"),
		" active=",
		animation_tree.get("parameters/ReloadUpperBody/active"),
		" animation=",
		(graph.get_node(&"ReloadAnimation") as AnimationNodeAnimation).animation,
		" library_has=",
		animation_player.has_animation(&"SOCOM/reload")
	)
	_expect(reload_started, "standing reload starts through the purchased AnimationTree")
	_expect(animation_tree.active, "reload keeps the locomotion AnimationTree active")
	_expect(
		bool(animation_tree.get("parameters/ReloadUpperBody/active")),
		"upper-body reload OneShot is active"
	)
	_expect(
		is_zero_approx(float((skeleton.get_node("LHTwoBoneIK3D") as TwoBoneIK3D).influence)),
		"reload releases the support-hand IK while the reload hand animates"
	)
	for _frame in range(24):
		await physics_frame
	Input.action_release(&"forward")
	_expect(
		player.global_position.distance_to(reload_start) > 0.05,
		"locomotion continues moving the body during upper-body reload"
	)
	lab.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("NATIVE_IK_SOCOM_PLAYER PASS ", label)
	else:
		failures.append(label)
		push_error("NATIVE_IK_SOCOM_PLAYER FAIL " + label)


func _finish() -> void:
	if failures.is_empty():
		print("NATIVE_IK_SOCOM_PLAYER_REGRESSION PASS")
		quit(0)
	else:
		print("NATIVE_IK_SOCOM_PLAYER_REGRESSION FAIL ", failures)
		quit(1)
