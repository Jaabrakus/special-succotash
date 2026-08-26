class_name SocomOperatorCameraMarkerFilter
extends Node

## Bounds animation-driven marker motion before the camera framing solver sees
## it. This is presentation only: it never changes the operator or camera aim.

@export_range(0.0, 1.0, 0.01) var head_follow_weight: float = 0.18
@export_range(0.0, 1.0, 0.01) var torso_follow_weight: float = 0.10
@export_range(0.0, 1.0, 0.01) var pelvis_follow_weight: float = 0.05
@export_range(0.0, 1.0, 0.01) var ready_moving_head_follow_weight: float = 0.0
@export_range(0.0, 1.0, 0.01) var ready_moving_torso_follow_weight: float = 0.0
@export_range(0.0, 1.0, 0.01) var ready_moving_pelvis_follow_weight: float = 0.0
@export_range(0.0, 0.30, 0.01) var maximum_horizontal_offset_m: float = 0.10
@export_range(0.0, 0.20, 0.01) var maximum_vertical_offset_m: float = 0.05


func filtered_delta(
	raw_delta: Vector3,
	marker_role: StringName,
	presentation_mode: StringName = &"DEFAULT"
) -> Vector3:
	var bounded := Vector3(
		clampf(raw_delta.x, -maximum_horizontal_offset_m, maximum_horizontal_offset_m),
		clampf(raw_delta.y, -maximum_vertical_offset_m, maximum_vertical_offset_m),
		clampf(raw_delta.z, -maximum_horizontal_offset_m, maximum_horizontal_offset_m)
	)
	return bounded * _weight_for(marker_role, presentation_mode)


func maximum_weighted_vertical_offset(
	marker_role: StringName,
	presentation_mode: StringName = &"DEFAULT"
) -> float:
	return maximum_vertical_offset_m * _weight_for(marker_role, presentation_mode)


func _weight_for(marker_role: StringName, presentation_mode: StringName) -> float:
	if presentation_mode in [&"READY", &"READY_MOVING"]:
		match marker_role:
			&"HEAD":
				return ready_moving_head_follow_weight
			&"TORSO":
				return ready_moving_torso_follow_weight
			&"PELVIS":
				return ready_moving_pelvis_follow_weight
			_:
				return 0.0
	match marker_role:
		&"HEAD":
			return head_follow_weight
		&"TORSO":
			return torso_follow_weight
		&"PELVIS":
			return pelvis_follow_weight
		_:
			return 0.0
