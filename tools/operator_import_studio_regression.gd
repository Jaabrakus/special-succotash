extends SceneTree

const Validator := preload("res://scripts/labs/operator_import/operator_import_validator.gd")
const VisualProfile := preload("res://scripts/characters/operator_visual_profile.gd")
const Normalizer := preload("res://scripts/characters/operator_model_normalizer.gd")
const MODEL_PATH := "res://source/CS PHISYIC MODEL.fbx"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var report := Validator.validate(MODEL_PATH)
	_expect(bool(report.get("compatible", false)), "the imported character passes core compatibility")
	_expect(int(report.get("bone_count", 0)) == 118, "the 118-bone source skeleton is detected")
	_expect(int(report.get("skinned_mesh_count", 0)) >= 1, "the source contains a skinned mesh")
	_expect((report.get("material_slots", []) as Array).size() >= 2, "material slots are available for texture overrides")
	_expect(int(report.get("animation_count", 0)) == 11, "embedded source animation clips are reported")
	var bone_map: Dictionary = report.get("bone_map", {})
	_expect(String(bone_map.get("hips", "")) == "pelvis", "pelvis maps to operator hips")
	_expect(String(bone_map.get("right_hand", "")) == "hand_R", "right hand maps to the operator weapon hand")
	_expect(bool(report.get("requires_canonical_conversion", false)), "the foreign rig is held behind the conversion gate")
	var normalization: Dictionary = report.get("normalization", {})
	_expect(bool(normalization.get("ok", false)), "skeleton landmarks produce a normalized operator transform")
	_expect(
		is_equal_approx(float(normalization.get("target_rig_height", 0.0)), Normalizer.TARGET_RIG_HEIGHT_M),
		"operator normalization uses the shared 1.70 metre rig contract"
	)
	_expect(
		float(normalization.get("scale_factor", 1.0)) > 0.02
		and float(normalization.get("scale_factor", 1.0)) < 0.03,
		"source centimetre-scale transforms are converted without a manual model offset"
	)
	var profile := VisualProfile.from_validation(MODEL_PATH, report)
	_expect(String(profile.get("skeleton_contract", "")) == VisualProfile.SKELETON_CONTRACT, "approved data targets the versioned skeleton contract")
	_expect(String(profile.get("status", "")) == "APPROVED_FOR_CONVERSION", "approval cannot silently replace the live operator")
	_expect(
		String((profile.get("normalization", {}) as Dictionary).get("contract", "")) == "SOCOM_OPERATOR_SPACE_V1",
		"approved profiles persist the normalized operator-space contract"
	)
	var studio := load("res://operator_import_studio.tscn") as PackedScene
	_expect(studio != null, "Operator Import Studio scene loads")
	if studio != null:
		var studio_instance := studio.instantiate()
		root.add_child(studio_instance)
		await process_frame
		studio_instance.call("_set_reference_visible", true)
		await process_frame
		_expect(
			studio_instance.get("canonical_reference") != null,
			"the transparent PS1 alignment overlay can be displayed"
		)
		var preview_model := studio_instance.get("preview_model") as Node3D
		var reference_model := studio_instance.get("canonical_reference") as Node3D
		if preview_model != null and reference_model != null:
			var preview_bounds := Normalizer.model_bounds(preview_model)
			var reference_bounds := Normalizer.model_bounds(reference_model)
			_expect(preview_bounds.size.y < 2.2, "the imported operator is framed in normalized human space")
			_expect(
				absf(preview_bounds.size.y - reference_bounds.size.y) < 0.15,
				"candidate and PS1 reference heights align without per-model scale math"
			)
		studio_instance.queue_free()
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("OPERATOR_IMPORT_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("OPERATOR_IMPORT_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("OPERATOR_IMPORT_STUDIO_REGRESSION PASS")
		quit(0)
	else:
		print("OPERATOR_IMPORT_STUDIO_REGRESSION FAIL ", failures)
		quit(1)
