extends SceneTree

const COMPOSER := preload("res://scripts/labs/animation_layer_composer.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var lower := _clip("mixamorig_Hips", Vector3(1.0, 0.0, 0.0), 2.0)
	var torso := _clip("mixamorig_Spine2", Vector3(0.0, 2.0, 0.0), 1.0)
	var left := _clip("mixamorig_LeftHand", Vector3(0.0, 0.0, 3.0), 1.0)
	var right := _clip("mixamorig_RightHand", Vector3(4.0, 0.0, 0.0), 1.0)
	var head := _clip("mixamorig_Head", Vector3(0.0, 5.0, 0.0), 1.0)
	var result: Animation = COMPOSER.new().compose({
		"lower_body": lower,
		"torso": torso,
		"left_arm": left,
		"right_arm": right,
		"head": head,
	})
	_expect(result != null, "composer produces a clip")
	if result:
		_expect(is_equal_approx(result.length, 2.0), "lower body establishes composite duration")
		_expect(result.get_track_count() == 5, "each disjoint body region contributes its bone tracks")
		_expect(_has_track(result, "mixamorig_Hips"), "lower-body track is preserved")
		_expect(_has_track(result, "mixamorig_Spine2"), "torso track is preserved")
		_expect(_has_track(result, "mixamorig_LeftHand"), "left-arm track is preserved")
		_expect(_has_track(result, "mixamorig_RightHand"), "right-arm track is preserved")
		_expect(_has_track(result, "mixamorig_Head"), "head track is preserved")
		_expect(is_equal_approx(_last_key_time(result, "mixamorig_Head"), 2.0), "short layer timing is normalized to the lower-body cycle")
	var full_body := Animation.new()
	full_body.length = 2.0
	_add_position_track(full_body, "mixamorig_Hips", Vector3(1.0, 0.0, 0.0))
	_add_position_track(full_body, "mixamorig_Spine2", Vector3(0.0, 1.0, 0.0))
	var torso_override := _clip("mixamorig_Spine2", Vector3(0.0, 9.0, 0.0), 1.0)
	var layered: Animation = COMPOSER.new().compose({
		"full_body": full_body,
		"torso": torso_override,
	})
	_expect(layered != null, "full-body sequence can act as the base lane")
	if layered:
		_expect(layered.get_track_count() == 2, "body-region override replaces rather than duplicates the base track")
		_expect(_last_key_value(layered, "mixamorig_Spine2").is_equal_approx(Vector3(0.0, 9.0, 0.0)), "highlighted torso lane overrides the full-body torso")
	var short_legs := _clip("mixamorig_Hips", Vector3(1.0, 0.0, 0.0), 0.5)
	var long_action := _clip("mixamorig_Spine2", Vector3(0.0, 3.0, 0.0), 1.25)
	var action_timed: Animation = COMPOSER.new().compose({
		"duration_reference": long_action,
		"lower_body": short_legs,
		"torso": long_action,
	})
	_expect(
		action_timed != null and is_equal_approx(action_timed.length, 1.25),
		"upper-body event preview keeps the action duration while borrowing locomotion legs"
	)
	if failures.is_empty():
		print("ANIMATION_LAYER_COMPOSER_REGRESSION PASS")
		quit(0)
	else:
		push_error("ANIMATION_LAYER_COMPOSER_REGRESSION FAIL %s" % failures)
		quit(1)

func _clip(bone_name: String, end_value: Vector3, length: float) -> Animation:
	var animation := Animation.new()
	animation.length = length
	var track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath(".:%s" % bone_name))
	animation.track_insert_key(track, 0.0, Vector3.ZERO)
	animation.track_insert_key(track, length, end_value)
	return animation

func _add_position_track(animation: Animation, bone_name: String, end_value: Vector3) -> void:
	var track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath(".:%s" % bone_name))
	animation.track_insert_key(track, 0.0, Vector3.ZERO)
	animation.track_insert_key(track, animation.length, end_value)

func _has_track(animation: Animation, bone_name: String) -> bool:
	for track in range(animation.get_track_count()):
		if String(animation.track_get_path(track)).ends_with(":" + bone_name):
			return true
	return false

func _last_key_time(animation: Animation, bone_name: String) -> float:
	for track in range(animation.get_track_count()):
		if String(animation.track_get_path(track)).ends_with(":" + bone_name):
			return animation.track_get_key_time(track, animation.track_get_key_count(track) - 1)
	return -1.0

func _last_key_value(animation: Animation, bone_name: String) -> Vector3:
	for track in range(animation.get_track_count()):
		if String(animation.track_get_path(track)).ends_with(":" + bone_name):
			return animation.track_get_key_value(track, animation.track_get_key_count(track) - 1)
	return Vector3.ZERO

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("ANIMATION_LAYER_CHECK PASS %s" % message)
	else:
		failures.append(message)
		push_error("ANIMATION_LAYER_CHECK FAIL %s" % message)
