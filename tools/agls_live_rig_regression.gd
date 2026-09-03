extends SceneTree

const HurtboxRig := preload("res://scripts/combat/socom_animated_hurtbox_rig.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _steps(45)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var mannequin := player.get_node_or_null("Mannequin") if player != null else null
	var driver := mannequin.get_node_or_null("ProductionAnimation") if mannequin != null else null
	_expect(player != null and driver != null, "live player animation path exists")
	if driver == null:
		_finish()
		return
	var model_root := driver.get("model_root") as Node3D
	var skeleton := driver.get("skeleton") as Skeleton3D
	_expect(model_root != null, "live AGLS model root exists")
	_expect(
		model_root != null and model_root.name == "CanonicalAglsOperatorRig",
		"old live character is replaced by the AGLS rig"
	)
	_expect(skeleton != null, "live AGLS skeleton exists")
	if skeleton == null:
		_finish()
		return
	_expect(skeleton.get_bone_count() == 70, "live imported AGLS skeleton has 70 bones")
	_expect(
		String(skeleton.get_meta("socom_source_rig", "")) == "agls_native_69",
		"live skeleton keeps AGLS source identity"
	)
	for bone_name in [
		"mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1",
		"mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head",
		"mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand",
		"mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand",
		"mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot",
		"mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot",
	]:
		_expect(skeleton.find_bone(bone_name) >= 0, "semantic bone %s exists" % bone_name)
	skeleton.force_update_all_bone_transforms()
	var head := _bone_world_position(skeleton, &"mixamorig_Head")
	var hips := _bone_world_position(skeleton, &"mixamorig_Hips")
	var left_foot := _bone_world_position(skeleton, &"mixamorig_LeftFoot")
	var right_foot := _bone_world_position(skeleton, &"mixamorig_RightFoot")
	var feet := (left_foot + right_foot) * 0.5
	var body_height := head.distance_to(feet)
	var left_foot_index := skeleton.find_bone(&"mixamorig_LeftFoot")
	var right_foot_index := skeleton.find_bone(&"mixamorig_RightFoot")
	var rest_feet := (
		(skeleton.global_transform * skeleton.get_bone_global_rest(left_foot_index)).origin
		+ (skeleton.global_transform * skeleton.get_bone_global_rest(right_foot_index)).origin
	) * 0.5
	print("AGLS_LIVE_RIG_INFO head=%s hips=%s feet=%s body_height=%.4f" % [
		head, hips, feet, body_height,
	])
	print("AGLS_LIVE_RIG_INFO rest_feet=%s player=%s" % [rest_feet, player.global_position])
	_expect(body_height >= 1.35 and body_height <= 2.10, "live AGLS body scale is human-sized")
	_expect(head.y > hips.y and hips.y > feet.y, "live AGLS body is upright")
	_expect(
		feet.y >= player.global_position.y - 0.10
		and feet.y <= player.global_position.y + 0.40,
		"authored AGLS pelvis placement keeps the feet at ground height"
	)
	var debug_state: Dictionary = driver.call("get_animation_debug_state")
	_expect(bool(debug_state.get("strict_authored_pose", false)), "strict AGLS pose mode is active")
	_expect(not bool(driver.get("use_modern_locomotion")), "legacy layered pose graph is disabled")
	var debug_visual := skeleton.get_node_or_null("AglsSkeletonVisual") as MultiMeshInstance3D
	_expect(
		debug_visual != null and debug_visual.multimesh != null,
		"runtime AGLS skeleton visual is active"
	)
	if debug_visual != null and debug_visual.multimesh != null:
		_expect(debug_visual.multimesh.instance_count >= 40, "skeleton visual draws body segments")
	var clip_paths: Dictionary = driver.get("clip_paths")
	_expect(not clip_paths.is_empty(), "AGLS animation map is loaded")
	for clip_name in clip_paths:
		var approved_hybrid: bool = (
			clip_name == &"dive_roll"
			and String(clip_paths[clip_name])
				== "res://assets/animations/mixamo/Running Dive Roll.fbx"
		)
		_expect(
			approved_hybrid or String(clip_paths[clip_name]).begins_with(
				"res://assets/external/agls_intake/imported/"
			),
			"clip %s uses AGLS content or its approved retargeted hybrid" % String(clip_name)
		)
	var hurtbox_rig := HurtboxRig.new()
	hurtbox_rig.name = "AglsRegressionHurtboxes"
	player.add_child(hurtbox_rig)
	_expect(hurtbox_rig.bind(skeleton, player), "SOCOM hurtboxes bind to semantic AGLS bones")
	_expect(hurtbox_rig.get_hurtbox_areas().size() >= 14, "full SOCOM hurtbox set is present")
	_finish()


func _bone_world_position(skeleton: Skeleton3D, bone_name: StringName) -> Vector3:
	var bone_index := skeleton.find_bone(bone_name)
	if bone_index < 0:
		return Vector3.ZERO
	return (skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)).origin


func _steps(count: int) -> void:
	for _step in count:
		await process_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AGLS_LIVE_RIG_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("AGLS_LIVE_RIG_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("AGLS_LIVE_RIG_REGRESSION PASS")
		quit(0)
		return
	print("AGLS_LIVE_RIG_REGRESSION FAIL %s" % [failures])
	quit(1)
