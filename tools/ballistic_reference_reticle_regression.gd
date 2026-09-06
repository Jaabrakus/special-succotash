extends SceneTree

const DynamicReticle := preload("res://scripts/ui/socom_dynamic_reticle.gd")

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/ui/socom_dynamic_reticle.gd"
	)
	_expect(source.find("draw_circle(center, CENTER_DOT_RADIUS") >= 0, "combat reticle draws a fixed center point")
	_expect(
		source.find("draw_circle(center, CENTER_DISC_RADIUS") >= 0
		and source.find("draw_arc(") < 0,
		"combat reticle has a faint disc instead of the old U-shaped arc"
	)
	var reticle := DynamicReticle.new()
	root.add_child(reticle)
	reticle.size = Vector2(1920.0, 1080.0)
	reticle.apply_profile({
		"base_gap_px": 5.1,
		"max_gap_px": 41.6,
		"maximum_movement_tick_extension_px": 16.0,
		"reference_arc_padding_px": 5.0,
		"lead_reference_length_px": 14.0,
		"drop_reference_length_px": 14.0,
	})
	var aim_center := Vector2(960.0, 540.0)
	reticle.update_reticle_state(0.0, false, aim_center, false, 0.0)
	reticle._process(0.5)
	var geometry: Dictionary = reticle.get_combat_reference_geometry()
	_check_geometry(reticle, geometry, aim_center, 14.0)

	reticle.update_reticle_state(0.75, false, aim_center, false, 1.0)
	reticle._process(0.5)
	var moving_geometry: Dictionary = reticle.get_combat_reference_geometry()
	_check_geometry(reticle, moving_geometry, aim_center, 14.0)
	_expect(
		float(moving_geometry.radius) > float(geometry.radius)
		and is_equal_approx(float(moving_geometry.disc_radius), float(geometry.disc_radius)),
		"spread opens ticks without inflating the central backing disc"
	)
	reticle.update_reticle_state(0.0, true, aim_center, false, 0.0)
	reticle._process(0.5)
	_expect(absf(float(reticle.get_combat_reference_geometry().radius) - float(geometry.radius)) < 0.01,
		"ticks recover to the original gap")
	_expect(reticle.is_target_acquired, "target acquisition feedback remains available")
	reticle.notify_hit()
	_expect(reticle.hit_marker_timer > 0.0, "hit confirmation remains available")
	reticle.update_reticle_state(0.0, false, aim_center, true)
	_expect(reticle.current_mode == DynamicReticle.ReticleMode.INTERACT, "interaction brackets remain available")
	reticle.update_reticle_state(0.0, false, aim_center)
	_expect(reticle.current_mode == DynamicReticle.ReticleMode.COMBAT, "combat returns after interaction")
	reticle.size = Vector2(1440.0, 1080.0)
	reticle.update_reticle_state(0.0, false)
	_check_geometry(reticle, reticle.get_combat_reference_geometry(), Vector2(720.0, 540.0), 14.0)
	reticle.apply_profile({"base_gap_px": 12.0, "max_gap_px": 55.0})
	reticle.update_reticle_state(1.0, false, aim_center)
	reticle._process(0.5)
	_expect(absf(reticle.current_gap - 55.0) < 0.01, "weapon switch consumes the next saved profile")

	reticle.maximum_shot_kick_pixels = 20.0
	reticle.shot_kick_pixels = 12.0
	reticle.notify_shot(1, 1.0)
	reticle.shot_bounce_age = reticle.shot_bounce_duration * 0.5
	var authority_before_bounce := reticle.get_authoritative_center()
	var bounced_geometry: Dictionary = reticle.get_combat_reference_geometry()
	_expect(
		reticle.get_visual_center().y < authority_before_bounce.y,
		"reference silhouette keeps the short cosmetic shot bounce"
	)
	_expect(
		reticle.get_authoritative_center().is_equal_approx(authority_before_bounce),
		"cosmetic reticle feedback cannot move canonical aim authority"
	)
	_expect(
		is_equal_approx(
			float(bounced_geometry.center.x),
			reticle.get_visual_center().x
		),
		"ticks remain horizontally centered during cosmetic feedback"
	)
	_expect((bounced_geometry.disc_center as Vector2).is_equal_approx(authority_before_bounce),
		"center point and backing remain fixed during cosmetic feedback")

	reticle.queue_free()
	await process_frame
	if failures.is_empty():
		print("BALLISTIC_REFERENCE_RETICLE_REGRESSION PASS")
		quit(0)
	else:
		print("BALLISTIC_REFERENCE_RETICLE_REGRESSION FAIL ", failures)
		quit(1)


func _check_geometry(
	reticle: Control,
	geometry: Dictionary,
	aim_center: Vector2,
	expected_lead_length: float
) -> void:
	var arc_center: Vector2 = geometry.center
	var left_inner: Vector2 = geometry.left_inner
	var left_outer: Vector2 = geometry.left_outer
	var right_inner: Vector2 = geometry.right_inner
	var right_outer: Vector2 = geometry.right_outer
	var drop_inner: Vector2 = geometry.drop_inner
	var drop_outer: Vector2 = geometry.drop_outer
	_expect(
		reticle.get_authoritative_center().is_equal_approx(aim_center),
		"center reference consumes the canonical camera aim point"
	)
	_expect(
		is_equal_approx(arc_center.x - left_inner.x, right_inner.x - arc_center.x),
		"ticks are symmetric around the center reference"
	)
	_expect(
		is_equal_approx(left_outer.distance_to(left_inner), expected_lead_length)
		and is_equal_approx(right_outer.distance_to(right_inner), expected_lead_length)
		and left_outer.x < left_inner.x
		and right_outer.x > right_inner.x,
		"left and right lead bars are horizontal, outward, and equally sized"
	)
	_expect(
		is_equal_approx(drop_inner.x, arc_center.x)
		and is_equal_approx(drop_outer.x, arc_center.x)
		and drop_outer.y > drop_inner.y,
		"drop reference is one centered lower vertical stem"
	)
	_expect(
		(geometry.ticks as PackedVector2Array).size() == 8
		and (geometry.top_inner as Vector2).is_equal_approx(arc_center - Vector2(0.0, float(geometry.radius)))
		and (geometry.top_outer as Vector2).is_equal_approx(arc_center * 2.0 - drop_outer),
		"four cardinal ticks include a symmetric upper tick"
	)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("RETICLE_REFERENCE_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("RETICLE_REFERENCE_CHECK FAIL %s" % label)
