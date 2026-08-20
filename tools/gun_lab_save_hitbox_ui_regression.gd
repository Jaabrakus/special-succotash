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

	# Duplicate creates another live, selectable physics shape. It keeps the
	# source bone anchor while its independent damage paint can change.
	lab.call("_select_hurtbox_region", &"left_upper_arm")
	var scales: Dictionary = lab.get("shared_hurtbox_scales")
	var geometry: Dictionary = lab.get("shared_hurtbox_geometry")
	scales[&"left_upper_arm"] = 0.73
	HurtboxProfile.set_geometry_length_scale(geometry, &"left_upper_arm", 0.62)
	HurtboxProfile.set_geometry_offset(
		geometry,
		&"left_upper_arm",
		Vector3(0.03, -0.02, 0.01)
	)
	var custom_before_count: int = (lab.get("shared_custom_hitboxes") as Array).size()
	lab.call("_duplicate_selected_hitbox")
	var custom_after: Array[Dictionary] = lab.get("shared_custom_hitboxes")
	var duplicate_id := StringName(lab.get("selected_hurtbox_region"))
	_expect(
		custom_after.size() == custom_before_count + 1,
		"Duplicate creates an additional physical hitbox entry"
	)
	_expect(
		duplicate_id not in HurtboxProfile.REGION_KEYS,
		"Duplicate becomes the selected independent shape"
	)
	var preview_dummy := lab.get("composure_preview_dummy") as Node
	var rig := preview_dummy.call("get_hurtbox_rig") as Node3D if preview_dummy else null
	_expect(
		rig != null and rig.call("get_editor_hitbox_area", duplicate_id) != null,
		"Duplicate creates a live physics area in the preview rig"
	)
	lab.call("_set_selected_hurtbox_damage_type", &"NECK")
	custom_after = lab.get("shared_custom_hitboxes")
	var duplicate_index := int(lab.call("_custom_hitbox_index", duplicate_id))
	_expect(
		duplicate_index >= 0 and StringName(custom_after[duplicate_index].get("damage_region")) == &"NECK",
		"Paint changes the duplicate damage identity"
	)
	lab.call("_snap_selected_hurtbox_to_rig")
	var snapped_offset: Vector3 = lab.call("_hitbox_offset", duplicate_id)
	_expect(
		snapped_offset.is_zero_approx(),
		"Snap restores duplicate to its source bone center"
	)
	_expect(
		is_equal_approx(float(lab.call("_hitbox_width", duplicate_id)), 0.73),
		"Snap preserves authored width"
	)
	lab.call("_delete_selected_hitbox")
	var custom_deleted: Array[Dictionary] = lab.get("shared_custom_hitboxes")
	_expect(custom_deleted.size() == custom_before_count, "Delete removes only the duplicate")

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
