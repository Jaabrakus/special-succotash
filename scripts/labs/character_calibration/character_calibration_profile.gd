class_name SocomCharacterCalibrationProfile
extends RefCounted

## Loads and validates versioned, visual-only character retarget calibration.
## Profiles describe anatomical axes and safety limits. They never own gameplay.

const SCHEMA_VERSION := 1
const SIDES := ["left", "right"]
const REQUIRED_ARM_LANDMARKS := [
	"shoulder",
	"upper_arm",
	"forearm",
	"hand",
	"index_knuckle",
	"middle_knuckle",
	"pinky_knuckle",
]
const REQUIRED_LEG_LANDMARKS := [
	"upper_leg",
	"lower_leg",
	"foot",
	"toe",
]


static func load_profile(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


static func save_profile(path: String, profile: Dictionary) -> Error:
	var failures := validate(profile)
	if not failures.is_empty():
		return ERR_INVALID_DATA
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(profile, "  ", false) + "\n")
	file.close()
	return OK


static func validate(profile: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	if int(profile.get("schema_version", -1)) != SCHEMA_VERSION:
		failures.append("schema_version must be %d" % SCHEMA_VERSION)
	for key in ["profile_id", "character_id", "reference_rig"]:
		if String(profile.get(key, "")).strip_edges().is_empty():
			failures.append("%s must be a non-empty string" % key)
	if int(profile.get("version", 0)) < 1:
		failures.append("version must be at least 1")

	var anatomy = profile.get("anatomy", {})
	if not anatomy is Dictionary:
		failures.append("anatomy must be a dictionary")
	else:
		for side in SIDES:
			_validate_landmarks(
				anatomy as Dictionary,
				"%s_arm" % side,
				REQUIRED_ARM_LANDMARKS,
				failures
			)
			_validate_landmarks(
				anatomy as Dictionary,
				"%s_leg" % side,
				REQUIRED_LEG_LANDMARKS,
				failures
			)

	var twist = profile.get("twist", {})
	if not twist is Dictionary:
		failures.append("twist must be a dictionary")
	else:
		for side in SIDES:
			_validate_twist_side(twist as Dictionary, side, failures)

	var joint_limits = profile.get("joint_limits_degrees", {})
	if not joint_limits is Dictionary:
		failures.append("joint_limits_degrees must be a dictionary")
	else:
		for side in SIDES:
			_validate_range(joint_limits as Dictionary, "%s_elbow" % side, failures)
			_validate_range(joint_limits as Dictionary, "%s_wrist_twist" % side, failures)
			_validate_range(joint_limits as Dictionary, "%s_ankle_pitch" % side, failures)
			_validate_range(joint_limits as Dictionary, "%s_foot_yaw" % side, failures)

	var quality = profile.get("quality_limits", {})
	if not quality is Dictionary:
		failures.append("quality_limits must be a dictionary")
	else:
		for key in [
			"palm_forward_error_degrees",
			"palm_normal_error_degrees",
			"foot_forward_error_degrees",
			"sole_normal_error_degrees",
			"hand_socket_error_m",
			"foot_ground_error_m",
		]:
			if float((quality as Dictionary).get(key, 0.0)) <= 0.0:
				failures.append("quality_limits.%s must be positive" % key)

	var preview_actions = profile.get("preview_actions", [])
	if not preview_actions is Array or (preview_actions as Array).size() < 6:
		failures.append("preview_actions must contain at least six actions")
	return failures


static func set_forearm_twist_share(
	profile: Dictionary,
	side: String,
	forearm_share: float
) -> void:
	if not side in SIDES:
		return
	var twist := profile.get_or_add("twist", {}) as Dictionary
	var side_twist := twist.get_or_add(side, {}) as Dictionary
	var bounded := clampf(forearm_share, 0.0, 1.0)
	side_twist["forearm_share"] = bounded
	side_twist["hand_share"] = 1.0 - bounded


static func get_forearm_twist_share(profile: Dictionary, side: String) -> float:
	var twist = profile.get("twist", {})
	if not twist is Dictionary:
		return 0.0
	var side_twist = (twist as Dictionary).get(side, {})
	return float((side_twist as Dictionary).get("forearm_share", 0.0)) if side_twist is Dictionary else 0.0


static func _validate_landmarks(
	anatomy: Dictionary,
	chain_name: String,
	required: Array,
	failures: Array[String]
) -> void:
	var chain = anatomy.get(chain_name, {})
	if not chain is Dictionary:
		failures.append("anatomy.%s must be a dictionary" % chain_name)
		return
	for landmark in required:
		if String((chain as Dictionary).get(String(landmark), "")).is_empty():
			failures.append("anatomy.%s.%s is required" % [chain_name, landmark])


static func _validate_twist_side(
	twist: Dictionary,
	side: String,
	failures: Array[String]
) -> void:
	var values = twist.get(side, {})
	if not values is Dictionary:
		failures.append("twist.%s must be a dictionary" % side)
		return
	var forearm_share := float((values as Dictionary).get("forearm_share", -1.0))
	var hand_share := float((values as Dictionary).get("hand_share", -1.0))
	if forearm_share < 0.0 or hand_share < 0.0:
		failures.append("twist.%s shares must be non-negative" % side)
	elif absf(forearm_share + hand_share - 1.0) > 0.0001:
		failures.append("twist.%s shares must total 1.0" % side)
	var soft_limit := float((values as Dictionary).get("soft_limit_degrees", 0.0))
	var hard_limit := float((values as Dictionary).get("hard_limit_degrees", 0.0))
	if soft_limit <= 0.0 or hard_limit < soft_limit:
		failures.append("twist.%s limits must be positive and ordered" % side)


static func _validate_range(
	joint_limits: Dictionary,
	joint_name: String,
	failures: Array[String]
) -> void:
	var values = joint_limits.get(joint_name, {})
	if not values is Dictionary:
		failures.append("joint_limits_degrees.%s must be a dictionary" % joint_name)
		return
	var minimum := float((values as Dictionary).get("minimum", 0.0))
	var maximum := float((values as Dictionary).get("maximum", 0.0))
	if minimum >= maximum:
		failures.append("joint_limits_degrees.%s minimum must be below maximum" % joint_name)
