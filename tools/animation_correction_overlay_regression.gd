extends SceneTree

const Overlay := preload("res://scripts/labs/animation_correction_overlay.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_expect(
		Overlay.joint_name_for_bone("mixamorig_LeftUpLeg") == "left_upper_leg",
		"left thigh maps to the shared animation correction schema"
	)
	_expect(
		Overlay.joint_name_for_bone("mixamorig_RightToeBase") == "right_toe",
		"right toe maps to the shared animation correction schema"
	)
	var entry := {
		"name": &"rifle_forward_preview",
		"key": &"rifle_forward_preview",
		"path": "res://animations/rifle_forward.fbx",
	}
	var slots := {
		"run_forward": "res://animations/rifle_forward.fbx",
		"run_forward_alt": "res://animations/rifle_forward.fbx",
	}
	_expect(
		Overlay.resolve_clip_key(entry, slots, "run_forward") == "run_forward",
		"mapped gameplay state is the correction owner"
	)
	var keys: Dictionary = {}
	keys = Overlay.store_key(keys, "run_forward", 0, {
		"joint_rotations": {"right_upper_arm": {"x": 0.0, "y": 0.0, "z": 0.0}},
		"right_elbow_pole": {"x": 0.0, "y": -0.1, "z": 0.0},
		"left_hand_target": {"x": 0.0, "y": 0.1, "z": 0.2},
		"left_hand_rotation_correction_deg": {"x": 0.0, "y": 0.0, "z": 0.0},
		"weapon_hand_rotation_correction_deg": {"x": 0.0, "y": 0.0, "z": 0.0},
	})
	keys = Overlay.store_key(keys, "run_forward", 30, {
		"joint_rotations": {"right_upper_arm": {"x": 20.0, "y": 10.0, "z": -4.0}},
		"right_elbow_pole": {"x": 0.2, "y": 0.1, "z": -0.2},
		"left_hand_target": {"x": 0.2, "y": 0.3, "z": 0.4},
		"left_hand_rotation_correction_deg": {"x": 10.0, "y": -20.0, "z": 30.0},
		"weapon_hand_rotation_correction_deg": {"x": 12.0, "y": 8.0, "z": 2.0},
	})
	var middle := Overlay.sample(keys, "run_forward", 15)
	var arm: Dictionary = middle.get("joint_rotations", {}).get("right_upper_arm", {})
	var hand := Overlay.vector_from(middle.get("left_hand_target", {}))
	var weapon_rotation := Overlay.vector_from(
		middle.get("weapon_hand_rotation_correction_deg", {})
	)
	var elbow := Overlay.vector_from(middle.get("right_elbow_pole", {}))
	var palm_rotation := Overlay.vector_from(
		middle.get("left_hand_rotation_correction_deg", {})
	)
	_expect(absf(float(arm.get("x", -1.0)) - 10.0) < 0.001, "joint pitch interpolates")
	_expect(hand.is_equal_approx(Vector3(0.1, 0.2, 0.3)), "hand position interpolates")
	_expect(elbow.is_equal_approx(Vector3(0.1, 0.0, -0.1)), "elbow pole interpolates")
	_expect(
		palm_rotation.is_equal_approx(Vector3(5.0, -10.0, 15.0)),
		"palm pitch yaw and roll interpolate"
	)
	_expect(
		weapon_rotation.is_equal_approx(Vector3(6.0, 4.0, 1.0)),
		"weapon pitch yaw and roll interpolate"
	)
	var held := Overlay.sample(keys, "run_forward", 90)
	_expect(
		Overlay.vector_from(held.get("left_hand_target", {})).is_equal_approx(
			Vector3(0.2, 0.3, 0.4)
		),
		"last correction key holds through the rest of the animation"
	)
	keys = Overlay.delete_key(keys, "run_forward", 30)
	_expect(
		(keys.get("run_forward", {}) as Dictionary).size() == 1,
		"one correction key can be deleted without touching the clip"
	)
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("ANIMATION_CORRECTION_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("ANIMATION_CORRECTION_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("ANIMATION_CORRECTION_OVERLAY_REGRESSION PASS")
		quit(0)
	else:
		push_error("ANIMATION_CORRECTION_OVERLAY_REGRESSION FAIL %s" % str(failures))
		quit(1)
