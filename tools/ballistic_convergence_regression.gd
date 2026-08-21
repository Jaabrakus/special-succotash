extends SceneTree

const MAIN_SCENE := preload("res://main.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	for _frame in 90:
		await physics_frame

	var rig: Node3D = main.get("camera_rig") as Node3D
	_expect(rig != null, "playable range owns the shared camera aim rig")
	if rig != null:
		var profile: Resource = rig.get("profile") as Resource
		var view_target: Vector3 = rig.get("view_aim_point")
		var weapon_target: Vector3 = rig.get("weapon_aim_point")
		var shot_point: Vector3 = rig.get("shot_point")
		var mannequin: Node = main.get_node_or_null("Player/Mannequin")
		var muzzle: Vector3 = (
			mannequin.call("get_active_muzzle_position")
			if mannequin != null and mannequin.has_method("get_active_muzzle_position")
			else Vector3.ZERO
		)
		print(
			"BALLISTIC_CONVERGENCE_METRIC view_distance=%.3f target_delta=%.3f shot_delta=%.3f muzzle_to_view=%.3f collider=%s"
			% [
				rig.global_position.distance_to(view_target),
				weapon_target.distance_to(view_target),
				shot_point.distance_to(view_target),
				muzzle.distance_to(view_target),
				String(rig.get("aim_collider_name")),
			]
		)
		_expect(
			float(profile.get("minimum_ballistic_convergence_distance")) <= 12.01,
			"normal-range ballistic zero is no longer locked beyond 45 metres"
		)
		_expect(
			float(profile.get("maximum_convergence_angle_deg")) >= 5.99,
			"third-person parallax may converge within the playable range"
		)
		_expect(bool(rig.get("aim_hit")), "center reticle acquires the range target")
		_expect(
			weapon_target.distance_to(view_target) <= 0.05,
			"muzzle trajectory converges at the acquired reticle target"
		)
		_expect(
			shot_point.distance_to(view_target) <= 0.08,
			"validated shot reaches the visible reticle impact instead of landing low"
		)

		var targets: Array = main.get("target_dummies") as Array
		var weapon: Node = main.get("weapon_controller") as Node
		if not targets.is_empty() and weapon != null:
			var camera: Camera3D = rig.get("camera") as Camera3D
			var viewport_size := rig.get_viewport().get_visible_rect().size
			# Put one target on a clear center sight line before the authored map
			# wall. This separates anatomical registration from valid obstruction.
			var target: Node3D = targets[0] as Node3D
			var target_rig: Node = target.call("get_hurtbox_rig")
			var head := target_rig.call("get_region_area", &"HEAD") as Area3D
			var center_pixels := viewport_size * 0.5
			var lens_origin := camera.project_ray_origin(center_pixels)
			var sight_direction := camera.project_ray_normal(center_pixels).normalized()
			var player: Node3D = main.get_node("Player") as Node3D
			var player_depth := maxf(
				(player.global_position + Vector3.UP * 1.6 - lens_origin).dot(sight_direction),
				0.0
			)
			var desired_head := lens_origin + sight_direction * (player_depth + 2.0)
			var head_offset := head.global_position - target.global_position
			target.global_position = desired_head - head_offset
			target_rig.call("force_pose_update")
			await physics_frame
			target_rig.call("force_pose_update")
			rig.set("reticle_screen_normalized", Vector2(0.5, 0.5))
			rig.call("_update_weapon_aim_point")
			rig.call("_update_shot_validation")
			_expect(
				"Hurtbox" in String(rig.get("aim_collider_name"))
				and "Head" in String(rig.get("aim_collider_name"))
				and "Hurtbox" in String(rig.get("shot_collider_name"))
				and "Head" in String(rig.get("shot_collider_name")),
				"blue sight acquires the animated head area instead of scenery behind it"
			)
			if head != null:
				weapon.get("composure").reset()
				weapon.get("ballistics").fire_cooldown = 0.0
				weapon.get("ballistics").continuous_shot_count = 0
				weapon.set("_movement_ratio", 0.0)
				weapon.set("_turning_ratio", 0.0)
				var headshot: Dictionary = weapon.call("request_fire")
				var damage_result: Dictionary = headshot.get("damage_result", {})
				print(
					"HEAD_SHOT_METRIC region=%s damage=%.1f health=%.1f"
					% [
						String(headshot.get("hit_region", &"")),
						float(damage_result.get("damage", 0.0)),
						float(damage_result.get("remaining_health", 100.0)),
					]
				)
				_expect(
					StringName(headshot.get("hit_region", &"")) == &"HEAD",
					"settled muzzle shot aimed at the blue head sight registers HEAD"
				)
				_expect(
					bool(damage_result.get("headshot", false))
					and float(damage_result.get("remaining_health", 100.0)) <= 0.0,
					"clean rifle headshot puts the 100 HP target down"
				)

	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("BALLISTIC_CONVERGENCE_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("BALLISTIC_CONVERGENCE_REGRESSION: %s" % failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
