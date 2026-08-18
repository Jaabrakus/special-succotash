extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://gun_calibration_lab.tscn") as PackedScene
	_expect(packed != null, "gun calibration lab scene loads")
	if packed == null:
		_finish()
		return

	var lab := packed.instantiate()
	root.add_child(lab)
	for _frame in range(20):
		await process_frame

	var entries: Array = lab.get("all_animation_entries")
	var picker := lab.get("all_animation_select") as OptionButton
	_expect(lab.get("hand_gizmo_world") != null, "the evolved support-hand gizmo is live")
	_expect(lab.get("weapon_gizmo_world") != null, "the evolved weapon-mount gizmo is live")
	_expect(
		lab.get("handling_family_select") != null,
		"the evolved weapon-family animation mapper is present"
	)
	_expect(
		lab.get("animation_quality_results") != null,
		"the evolved animation compatibility audit is present"
	)
	_expect(entries.size() >= 200, "the lab catalogs every imported operator animation")
	_expect(
		picker != null and picker.item_count == entries.size(),
		"every cataloged animation is exposed in the inspector picker"
	)
	if entries.is_empty() or picker == null:
		lab.queue_free()
		_finish()
		return

	var selected_index := _find_representative_clip(entries)
	picker.select(selected_index)
	var entry: Dictionary = entries[selected_index]
	var clip_key := StringName(entry.get("key", &""))
	var resource_path := String(entry.get("path", ""))
	_expect(
		bool(lab.call("_ensure_preview_clip", clip_key)),
		"a catalog animation retargets onto the live gunsmith skeleton"
	)
	lab.set("selected_animation_key", clip_key)

	var expected_grip := Vector3(0.173, -0.041, 0.026)
	var expected_trigger := Vector3(-0.019, 0.012, 0.031)
	var expected_mount := Vector3(-0.014, 0.022, 0.009)
	lab.set("left_grip_local_pos", expected_grip)
	lab.set("right_grip_local_pos", expected_trigger)
	lab.set("grip_offset_pos", expected_mount)
	lab.call("_save_selected_animation_hand_map")
	var hand_maps: Dictionary = lab.get("animation_hand_maps")
	_expect(hand_maps.has(resource_path), "the selected clip receives its own hand map")

	lab.set("left_grip_local_pos", Vector3.ZERO)
	lab.set("right_grip_local_pos", Vector3.ZERO)
	lab.set("grip_offset_pos", Vector3.ZERO)
	lab.call("_apply_animation_hand_map", clip_key)
	_expect(
		(lab.get("left_grip_local_pos") as Vector3).is_equal_approx(expected_grip),
		"support-hand placement restores per animation"
	)
	_expect(
		(lab.get("right_grip_local_pos") as Vector3).is_equal_approx(expected_trigger),
		"trigger-hand grip restores per animation"
	)
	_expect(
		(lab.get("grip_offset_pos") as Vector3).is_equal_approx(expected_mount),
		"trigger-hand weapon mount restores per animation"
	)

	lab.queue_free()
	await process_frame
	_finish()


func _find_representative_clip(entries: Array) -> int:
	for index in range(entries.size()):
		var path := String((entries[index] as Dictionary).get("path", "")).to_lower()
		if "rifle" in path and "idle" in path:
			return index
	return 0


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("GUN_LAB_ANIMATION_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("GUN_LAB_ANIMATION_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("GUN_LAB_ANIMATION_CATALOG_REGRESSION PASS")
		quit(0)
	else:
		print("GUN_LAB_ANIMATION_CATALOG_REGRESSION FAIL ", failures)
		quit(1)
