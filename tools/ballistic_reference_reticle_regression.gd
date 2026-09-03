extends SceneTree

const DynamicReticle := preload("res://scripts/ui/socom_dynamic_reticle.gd")

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/ui/socom_dynamic_reticle.gd"
	)
	_expect(source.find("draw_circle(") < 0, "combat reticle draws no center dot")
	_expect(
		source.find("draw_arc(center, current_gap") < 0,
		"combat reticle draws no separate grey bloom circle"
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
	_check_geometry(reticle, moving_geometry, aim_center, 30.0)
	_expect(
		float(moving_geometry.arc_radius) > float(geometry.arc_radius),
		"spread expands the open reference arc"
	)

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
			float(bounced_geometry.arc_center.x),
			reticle.get_visual_center().x
		),
		"open arc remains horizontally centered on its invisible aim point"
	)

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
	var arc_center: Vector2 = geometry.arc_center
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
		"open arc is symmetric around the center reference"
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
		float(geometry.arc_start) > 0.0
		and float(geometry.arc_end) < PI,
		"reference arc is open above the invisible aim center"
	)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("RETICLE_REFERENCE_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("RETICLE_REFERENCE_CHECK FAIL %s" % label)
