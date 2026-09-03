extends SceneTree

const SCENE := preload("res://gun_calibration_lab_2.tscn")
const CONTRACT := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd"
)
const WEAPON_CONTRACT := preload("res://scripts/weapons/weapon_rig_contract.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lab = SCENE.instantiate()
	root.add_child(lab)
	for _frame in range(12):
		await process_frame
	var workspace := lab.find_child("GunsLab2Workspace", true, false) as Control
	_expect(workspace != null, "Guns Lab 2.0 builds its focused workspace")
	_expect(
		lab.overlay != null and not lab.overlay.visible,
		"legacy all-purpose Gunsmith controls stay hidden"
	)
	_expect(
		lab.find_child("VisualOnlyContractNotice", true, false) != null,
		"workspace states its visual-only authority boundary"
	)
	_expect(
		lab.find_child("GunsLab2WeaponPicker", true, false) != null,
		"workspace selects a read-only weapon identity"
	)
	_expect(
		lab.find_child("GunsLab2SocketPicker", true, false) != null,
		"workspace exposes focused socket calibration"
	)
	_expect(
		lab.find_child("SaveVisualRigDraft", true, false) != null
		and lab.find_child("PublishGoldenVisualRig", true, false) != null
		and lab.find_child("AssignVisualRigToWeapon", true, false) != null,
		"workspace separates draft, publish, and assignment actions"
	)
	_expect(
		lab.find_child("ApplyHandPoseAndPlay", true, false) != null,
		"workspace can validate, assign, and play the hand pose in one step"
	)
	_expect(
		lab.dynamic_reticle != null
		and lab.dynamic_reticle.get_parent() == workspace
		and lab.reticle_canvas != null
		and lab.reticle_canvas.get_parent() == workspace,
		"workspace reuses the canonical reticle readers instead of hiding or duplicating them"
	)
	_expect(
		lab.find_child("BulletVelocityToggleV2", true, false) != null
		and lab.find_child("BarrelAxisToggleV2", true, false) != null
		and lab.find_child("ReticleIntentToggleV2", true, false) != null
		and lab.find_child("GunPlacementLineToggleV2", true, false) != null
		and lab.find_child("LastShotToggleV2", true, false) != null,
		"workspace exposes the existing trajectory and aim-reference overlays"
	)
	_expect(
		lab.find_child("TestReticleKickButton", true, false) != null
		and lab.find_child("TestReloadHandsButton", true, false) != null,
		"workspace can preview reticle kick and reload handoff"
	)
	_expect(
		lab.current_weapon_mesh != null,
		"upper-body preview loads the selected gun mesh"
	)
	_expect(
		lab.current_weapon_mesh != null
		and not String(lab.selected_model_path).is_empty(),
		"upper-body preview renders the selected weapon visual"
	)
	var canonical_profile := WEAPON_CONTRACT.load_config(
		"res://config/weapons/%s.json" % String(lab.weapon_name).to_lower()
	)
	var preview_scale := float(lab.auto_normalized_scale) * float(
		lab.user_scale_multiplier
	)
	_expect(
		not canonical_profile.is_empty()
		and is_equal_approx(
			preview_scale,
			float(canonical_profile.get("normalized_scale", -1.0))
		),
		"instantiated Guns Lab mesh uses the canonical final normalized scale once"
	)
	_expect(
		lab.skeleton != null
		and lab.left_hand_idx >= 0
		and lab.right_hand_idx >= 0,
		"upper-body preview includes both complete arm chains"
	)
	_expect(
		lab.cam_distance >= 1.10 and lab.cam_distance <= 1.25,
		"workspace starts with both arm chains and the gun inside the review frame"
	)
	_expect(
		lab.find_child("HandPoseSideView", true, false) != null
		and lab.find_child("HandPoseTopView", true, false) != null,
		"workspace exposes side and top hand-target views"
	)
	_expect(
		lab.find_child("HandPoseRotationWheel", true, false) != null
		and lab.find_child("HandPoseExactValues", true, false) != null,
		"workspace exposes rotation wheels and exact pose values"
	)
	var edited_support := Vector3(0.031, 0.142, 0.288)
	lab.call("_on_hand_pose_target_changed", &"support_hand", edited_support)
	var palm_roll_before := float(lab.palm_roll)
	lab.call("_on_hand_pose_rotation_delta", &"roll", 17.0)
	var expected_palm_roll := wrapf(palm_roll_before + 17.0, -180.0, 180.0)
	var edited_pole := Vector3(-0.08, 0.04, 0.12)
	lab.call("_on_hand_pose_target_changed", &"support_elbow", edited_pole)
	var source: Dictionary = lab.call("_current_visual_source_profile")
	var sockets: Dictionary = source.get("weapon_sockets", {})
	var support_socket: Dictionary = sockets.get("left_hand_ik_target", {})
	_expect(
		is_equal_approx(float(support_socket.get("x", 0.0)), edited_support.x)
		and is_equal_approx(float(support_socket.get("y", 0.0)), edited_support.y)
		and is_equal_approx(float(support_socket.get("z", 0.0)), edited_support.z),
		"2D support-hand edits enter the shared weapon socket contract"
	)
	var support_pose: Dictionary = source.get("support_hand_pose", {})
	_expect(
		is_equal_approx(
			float(support_pose.get("palm_roll_deg", 0.0)),
			expected_palm_roll
		),
		"rotation wheel edits enter the shared support-palm contract"
	)
	var elbow_poles: Dictionary = source.get("elbow_poles", {})
	var by_stance: Dictionary = elbow_poles.get("by_stance", {})
	var standing_poles: Dictionary = by_stance.get("STANDING", {})
	var saved_left_pole: Dictionary = standing_poles.get("left", {})
	_expect(
		is_equal_approx(float(saved_left_pole.get("x", 0.0)), edited_pole.x)
		and is_equal_approx(float(saved_left_pole.get("y", 0.0)), edited_pole.y)
		and is_equal_approx(float(saved_left_pole.get("z", 0.0)), edited_pole.z),
		"2D elbow edits enter the per-stance pole contract"
	)
	var document := CONTRACT.extract(source, "scene_check", 1, "draft")
	var validation := CONTRACT.validate(document, false)
	_expect(bool(validation.get("ok", false)), "live preview produces a publishable visual contract")
	var visual: Dictionary = document.get("visual", {})
	_expect(not visual.has("ballistics"), "scene snapshot cannot include ballistics")
	_expect(not visual.has("fire_modes"), "scene snapshot cannot include fire modes")
	lab.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("GUNS_LAB_2_SCENE_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("GUNS_LAB_2_SCENE_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("GUNS_LAB_2_SCENE_REGRESSION PASS")
		quit(0)
	else:
		print("GUNS_LAB_2_SCENE_REGRESSION FAIL ", failures)
		quit(1)
