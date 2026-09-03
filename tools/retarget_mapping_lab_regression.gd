extends SceneTree

const LAB_SCENE := preload("res://retarget_mapping_lab.tscn")
const CAPTURE_PATH := "/private/tmp/socom-retarget-mapping-lab.png"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var lab := LAB_SCENE.instantiate() as SocomRetargetMappingLab
	root.add_child(lab)
	await process_frame
	await process_frame
	_expect(lab.target_skeleton != null, "PS1 target skeleton loads")
	_expect(lab.source_skeleton != null, "tactical suit source skeleton loads")
	_expect(lab.target_skeleton != null and lab.target_skeleton.get_bone_count() == 65, "target keeps the canonical 65-bone contract")
	_expect(lab.source_skeleton != null and lab.source_skeleton.get_bone_count() == 88, "source exposes all 88 authored joints")
	_expect(lab.target_root.position.x > 0.0 and lab.source_root.position.x < 0.0, "rigs render side by side")
	_expect(lab.mapping_count() == 22, "profile loads 20 core mappings plus two weighted toe bases")
	_expect(lab.calibration_count() == 0, "offline-bound suit needs no runtime arm calibration")
	_expect(lab.arm_alignment_error_degrees() <= 0.25, "bound suit rest arms form a horizontal T-pose")
	_expect(lab.bone_buttons.size() == 153, "all target and source bones receive clickable controls")
	_expect(lab.calibration_profile_error_count() == 0, "versioned calibration profile is valid")
	_expect(lab.calibration_profile_version() == 1, "calibration profile version is explicit")
	_expect(is_equal_approx(lab.forearm_twist_share("left"), 0.72), "left forearm twist distribution loads")
	_expect(is_equal_approx(lab.forearm_twist_share("right"), 0.72), "right forearm twist distribution loads")
	_expect(lab.calibration_report_status() in ["pass", "needs_calibration"], "anatomical calibration report completes")
	_expect(lab.find_child("AnalyzeCalibration", true, false) != null, "no-code analyze control is visible")
	_expect(lab.find_child("SaveCalibrationProfile", true, false) != null, "no-code profile save control is visible")
	print("RETARGET_MAPPING_CALIBRATION_REPORT %s" % str(lab.calibration_report))
	_test_foot_chains(lab)
	var original_source := String(lab.mapping.get("mixamorig_RightHand", ""))
	_expect(lab.assign_mapping("mixamorig_RightHand", original_source), "a clicked target/source pair can be assigned")
	_expect(not String(lab.mapping.get("mixamorig_RightHand", "")).is_empty(), "assigned pair remains explicit")
	if DisplayServer.get_name() == "headless":
		print("RETARGET_MAPPING_LAB_CAPTURE SKIP display=headless")
	else:
		RenderingServer.force_draw()
		await process_frame
		var image := root.get_texture().get_image()
		_expect(image != null and not image.is_empty(), "mapping lab renders a review frame")
		if image != null and not image.is_empty():
			_expect(image.save_png(CAPTURE_PATH) == OK, "review capture saves")
	if failures.is_empty():
		print("RETARGET_MAPPING_LAB_REGRESSION PASS %s" % CAPTURE_PATH)
		quit(0)
		return
	print("RETARGET_MAPPING_LAB_REGRESSION FAIL %s" % str(failures))
	quit(1)


func _test_foot_chains(lab: SocomRetargetMappingLab) -> void:
	for side in ["Left", "Right"]:
		var target_leg := "mixamorig_%sLeg" % side
		var target_foot := "mixamorig_%sFoot" % side
		var target_toe := "mixamorig_%sToeBase" % side
		var source_leg := String(lab.mapping.get(target_leg, ""))
		var source_foot := String(lab.mapping.get(target_foot, ""))
		_expect(not source_leg.is_empty() and side in source_leg, "%s lower-leg mapping preserves side" % side)
		_expect(not source_foot.is_empty() and side in source_foot, "%s foot mapping preserves side" % side)
		var source_toe := String(lab.mapping.get(target_toe, ""))
		_expect(not source_toe.is_empty() and side in source_toe, "%s weighted toe base preserves side" % side)
		_expect(not lab.mapping.has("mixamorig_%sToe_End" % side), "%s non-deforming toe end stays unmapped" % side)
		var source_leg_index := lab.call("_find_compatible_source_bone", source_leg) as int
		var source_foot_index := lab.call("_find_compatible_source_bone", source_foot) as int
		var source_toe_index := lab.call("_find_compatible_source_bone", "mixamorig:%sToeBase" % side) as int
		_expect(lab.source_skeleton.get_bone_parent(source_foot_index) == source_leg_index, "%s foot is parented to the same-side lower leg" % side)
		_expect(lab.source_skeleton.get_bone_parent(source_toe_index) == source_foot_index, "%s mapped toe base belongs to the same-side foot" % side)
		var hips_index := lab.call("_find_compatible_source_bone", String(lab.mapping.get("mixamorig_Hips", ""))) as int
		var hips_x := lab.source_skeleton.get_bone_global_rest(hips_index).origin.x
		var foot_position := lab.source_skeleton.get_bone_global_rest(source_foot_index).origin
		var toe_position := lab.source_skeleton.get_bone_global_rest(source_toe_index).origin
		print("RETARGET_MAPPING_FOOT_METRIC side=%s source_foot_x_from_hips=%.6f toe_delta=%s" % [
			side,
			foot_position.x - hips_x,
			str(toe_position - foot_position),
		])


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("RETARGET_MAPPING_LAB_CHECK PASS: %s" % message)
	else:
		failures.append(message)
		push_error("RETARGET_MAPPING_LAB_CHECK FAIL: %s" % message)
