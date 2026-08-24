class_name SocomAnimationRootSanitizer
extends RefCounted

## Imported clips are visual-only. CharacterBody3D owns authoritative travel, so
## horizontal hips/root displacement must never accumulate inside an animation.
## Looping clips also close their authored hips-yaw drift while preserving the
## within-cycle sway that gives the motion weight.


static func sanitize(
	animation: Animation,
	close_loop_yaw: bool,
	vertical_motion_scale: float = 1.0,
	up_axis: Vector3 = Vector3.UP
) -> Dictionary:
	var report := {
		"horizontal_keys_cleared": 0,
		"vertical_keys_reduced": 0,
		"yaw_tracks_closed": 0,
		"maximum_yaw_drift_degrees": 0.0,
	}
	if animation == null:
		return report
	var safe_up := up_axis.normalized()
	if safe_up.length_squared() < 0.99:
		safe_up = Vector3.UP
	var safe_vertical_scale := clampf(vertical_motion_scale, 0.0, 1.0)
	for track in range(animation.get_track_count()):
		if not _is_root_or_hips_track(animation, track):
			continue
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				var mean_height := 0.0
				var key_count := animation.track_get_key_count(track)
				if key_count > 0 and safe_vertical_scale < 0.999:
					for key in range(key_count):
						mean_height += safe_up.dot(Vector3(
							animation.track_get_key_value(track, key)
						))
					mean_height /= float(key_count)
				for key in range(animation.track_get_key_count(track)):
					var position: Vector3 = animation.track_get_key_value(track, key)
					var height := safe_up.dot(position)
					var horizontal := position - safe_up * height
					if horizontal.length_squared() > 0.00000001:
						report["horizontal_keys_cleared"] = int(report["horizontal_keys_cleared"]) + 1
					if safe_vertical_scale < 0.999:
						height = mean_height + (
							height - mean_height
						) * safe_vertical_scale
						report["vertical_keys_reduced"] = int(
							report["vertical_keys_reduced"]
						) + 1
					position = safe_up * height
					animation.track_set_key_value(track, key, position)
			Animation.TYPE_ROTATION_3D:
				if close_loop_yaw:
					var yaw_drift := _close_rotation_yaw_drift(
						animation, track, safe_up
					)
					if absf(yaw_drift) > 0.0001:
						report["yaw_tracks_closed"] = int(report["yaw_tracks_closed"]) + 1
						report["maximum_yaw_drift_degrees"] = maxf(
							float(report["maximum_yaw_drift_degrees"]),
							absf(rad_to_deg(yaw_drift))
						)
	return report


static func root_motion_report(
	animation: Animation,
	up_axis: Vector3 = Vector3.UP
) -> Dictionary:
	var report := {
		"maximum_horizontal_displacement": 0.0,
		"maximum_yaw_drift_degrees": 0.0,
	}
	if animation == null:
		return report
	var safe_up := up_axis.normalized()
	if safe_up.length_squared() < 0.99:
		safe_up = Vector3.UP
	for track in range(animation.get_track_count()):
		if not _is_root_or_hips_track(animation, track):
			continue
		var key_count := animation.track_get_key_count(track)
		if key_count < 2:
			continue
		if animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
			var first: Vector3 = animation.track_get_key_value(track, 0)
			var last: Vector3 = animation.track_get_key_value(track, key_count - 1)
			var displacement := last - first
			var horizontal := displacement - safe_up * safe_up.dot(displacement)
			report["maximum_horizontal_displacement"] = maxf(
				float(report["maximum_horizontal_displacement"]),
				horizontal.length()
			)
		elif animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			var first_rotation: Quaternion = animation.track_get_key_value(track, 0)
			var last_rotation: Quaternion = animation.track_get_key_value(track, key_count - 1)
			var drift := absf(rad_to_deg(_yaw_delta(
				first_rotation, last_rotation, safe_up
			)))
			report["maximum_yaw_drift_degrees"] = maxf(float(report["maximum_yaw_drift_degrees"]), drift)
	return report


static func _close_rotation_yaw_drift(
	animation: Animation,
	track: int,
	up_axis: Vector3
) -> float:
	var key_count := animation.track_get_key_count(track)
	if key_count < 2:
		return 0.0
	var first_rotation: Quaternion = animation.track_get_key_value(track, 0)
	var last_rotation: Quaternion = animation.track_get_key_value(track, key_count - 1)
	var yaw_drift := _yaw_delta(first_rotation, last_rotation, up_axis)
	if absf(yaw_drift) <= 0.0001:
		return 0.0
	var first_time := animation.track_get_key_time(track, 0)
	var last_time := animation.track_get_key_time(track, key_count - 1)
	var duration := maxf(last_time - first_time, 0.0001)
	for key in range(key_count):
		var key_time := animation.track_get_key_time(track, key)
		var alpha := clampf((key_time - first_time) / duration, 0.0, 1.0)
		var rotation: Quaternion = animation.track_get_key_value(track, key)
		var correction := Quaternion(up_axis, -yaw_drift * alpha)
		animation.track_set_key_value(track, key, (correction * rotation).normalized())
	return yaw_drift


static func _yaw_delta(
	first: Quaternion,
	last: Quaternion,
	up_axis: Vector3
) -> float:
	var reference_forward := (
		Vector3.FORWARD
		if absf(up_axis.dot(Vector3.FORWARD)) < 0.9
		else Vector3.UP
	)
	var first_forward := Basis(first) * reference_forward
	var last_forward := Basis(last) * reference_forward
	first_forward -= up_axis * up_axis.dot(first_forward)
	last_forward -= up_axis * up_axis.dot(last_forward)
	if first_forward.length_squared() < 0.000001 or last_forward.length_squared() < 0.000001:
		return 0.0
	first_forward = first_forward.normalized()
	last_forward = last_forward.normalized()
	return atan2(
		up_axis.dot(first_forward.cross(last_forward)),
		first_forward.dot(last_forward)
	)


static func _is_root_or_hips_track(animation: Animation, track: int) -> bool:
	var path := str(animation.track_get_path(track)).to_lower()
	var bone := path.split(":")[-1]
	return (
		"hips" in bone
		or "pelvis" in bone
		or bone == "root"
		or bone.ends_with("_root")
	)
