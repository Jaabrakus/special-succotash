extends SceneTree

const PoseSearch := preload("res://scripts/player/motion_matching/motion_matching_pose_search.gd")


func _init() -> void:
	var matcher := PoseSearch.new()
	var schema := {
		"continuing_pose_bias": 0.18,
		"minimum_switch_improvement": 0.08,
		"weights": {
			"velocity": 2.0, "future_velocity": 3.0, "facing_delta": 1.25,
			"left_foot_position": 0.65, "right_foot_position": 0.65,
			"left_foot_velocity": 0.45, "right_foot_velocity": 0.45,
		},
	}
	var common := {
		"posture": &"STANDING", "gait": &"RUN", "weapon_family": &"TWO_HAND_RIFLE",
		"facing_delta": 0.0,
		"left_foot_position": Vector3.ZERO, "right_foot_position": Vector3.ZERO,
		"left_foot_velocity": Vector3.ZERO, "right_foot_velocity": Vector3.ZERO,
	}
	var forward := common.duplicate(true)
	forward.merge({"id": &"forward_10", "clip": &"run_forward", "time": 0.33,
		"velocity": Vector2(0.0, 1.0), "future_velocity": Vector2(0.0, 1.0)}, true)
	var left := common.duplicate(true)
	left.merge({"id": &"left_10", "clip": &"run_left", "time": 0.33,
		"velocity": Vector2(-1.0, 0.0), "future_velocity": Vector2(-1.0, 0.0)}, true)
	var crouched := left.duplicate(true)
	crouched["id"] = &"crouched_left_10"
	crouched["clip"] = &"crouch_left"
	crouched["posture"] = &"CROUCHED"
	var errors := matcher.configure(schema, [forward, left, crouched])
	_check(errors.is_empty(), "schema and database validate")
	var query := left.duplicate(true)
	var result := matcher.search(query, {
		"posture": &"STANDING", "gait": &"RUN",
		"weapon_family": &"TWO_HAND_RIFLE", "current_clip": &"run_forward",
	})
	_check(StringName(result.get("clip", &"")) == &"run_left", "trajectory selects left run")
	_check(StringName(result.get("posture", &"")) == &"STANDING", "chooser excludes crouched database")
	_check(bool(result.get("switched", false)), "materially better pose can interrupt continuity")
	print("MOTION_MATCHING_POSE_SEARCH_REGRESSION PASS")
	quit(0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		push_error("MOTION_MATCHING_POSE_SEARCH_CHECK FAIL %s" % label)
		quit(1)
	print("MOTION_MATCHING_POSE_SEARCH_CHECK PASS ", label)
