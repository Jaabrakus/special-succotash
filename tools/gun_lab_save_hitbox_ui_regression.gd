extends SceneTree

const GUN_LAB_SCENE := preload("res://gun_calibration_lab.tscn")
const HurtboxProfile := preload("res://scripts/combat/socom_hurtbox_profile.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab := GUN_LAB_SCENE.instantiate()
	root.add_child(lab)
	for _frame in 12:
		await process_frame

	var save_button := lab.get("save_rig_button") as Button
	_expect(save_button != null, "Save Everything button exists")
	if save_button:
		_expect(
			lab.call("_pointer_over_editor_ui", save_button.get_global_rect().get_center()),
			"sidebar owns the Save Everything click area"
		)
		_expect(
			not save_button.pressed.get_connections().is_empty(),
			"Save Everything button has an active save callback"
		)

	# Copy transfers a full local shape to another named region. Snap keeps its
	# width but restores the target region's bone-centered layout.
	lab.call("_select_hurtbox_region", &"left_upper_arm")
	var scales: Dictionary = lab.get("shared_hurtbox_scales")
	var geometry: Dictionary = lab.get("shared_hurtbox_geometry")
	scales[&"left_upper_arm"] = 0.73
	HurtboxProfile.set_geometry_length_scale(geometry, &"left_upper_arm", 1.22)
	HurtboxProfile.set_geometry_offset(
		geometry,
		&"left_upper_arm",
		Vector3(0.03, -0.02, 0.01)
	)
	lab.call("_copy_selected_hurtbox")
	lab.call("_select_hurtbox_region", &"right_upper_arm")
	lab.call("_paste_selected_hurtbox")
	_expect(
		is_equal_approx(float(scales[&"right_upper_arm"]), 0.73),
		"Paste transfers hitbox width"
	)
	_expect(
		is_equal_approx(
			HurtboxProfile.geometry_length_scale(geometry, &"right_upper_arm"),
			1.22
		),
		"Paste transfers hitbox length"
	)
	_expect(
		HurtboxProfile.geometry_offset(geometry, &"right_upper_arm").is_equal_approx(
			Vector3(0.03, -0.02, 0.01)
		),
		"Paste transfers hitbox center"
	)
	lab.call("_snap_selected_hurtbox_to_rig")
	geometry = lab.get("shared_hurtbox_geometry")
	_expect(
		HurtboxProfile.geometry_offset(geometry, &"right_upper_arm").is_zero_approx(),
		"Snap restores target bone center"
	)
	_expect(
		is_equal_approx(float(scales[&"right_upper_arm"]), 0.73),
		"Snap preserves authored width"
	)

	lab.queue_free()
	await process_frame
	if failures.is_empty():
		print("GUN_LAB_SAVE_HITBOX_UI_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("GUN_LAB_SAVE_HITBOX_UI_REGRESSION: %s" % failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
