extends SceneTree


func _init() -> void:
	var posture_source := _read("res://scripts/player/operator_posture_layer.gd")
	if "_apply_square_shoulders(world_aim_target)" in posture_source:
		push_error("Live posture still overwrites Animation Studio shoulders")
		quit(1)
		return
	var file := FileAccess.open(
		"res://config/operator_procedural_pose_profile.json",
		FileAccess.READ
	)
	var document: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not document is Dictionary:
		push_error("Procedural pose profile did not load")
		quit(1)
		return
	var standing: Dictionary = (document as Dictionary).get("postures", {}).get("STANDING", {})
	for bone_name: String in standing:
		var rotation: Dictionary = standing.get(bone_name, {})
		if not Vector3(
			float(rotation.get("pitch", 0.0)),
			float(rotation.get("yaw", 0.0)),
			float(rotation.get("roll", 0.0))
		).is_zero_approx():
			push_error("Standing still contains hidden global correction: %s" % bone_name)
			quit(1)
			return
	if "posture_layer.apply(" not in _read("res://scripts/player/operator_animation_driver.gd"):
		push_error("Runtime lost its bounded post-animation aim layer")
		quit(1)
		return
	print("OPERATOR_AUTHORED_POSE_REGRESSION PASS")
	quit(0)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""
