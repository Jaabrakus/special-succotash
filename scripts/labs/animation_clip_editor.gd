class_name SocomAnimationClipEditor
extends RefCounted

## Non-destructive frame baker for workbench trims and sequential assemblies.
## The source resources are sampled but never modified.


func trim(source: Animation, start_time: float, end_time: float, fps: float = 30.0) -> Animation:
	if source == null:
		return null
	return combine([{
		"animation": source,
		"start": start_time,
		"end": end_time,
	}], fps)


func combine(segments: Array, fps: float = 30.0) -> Animation:
	var result := Animation.new()
	var safe_fps := maxf(fps, 1.0)
	result.step = 1.0 / safe_fps
	result.loop_mode = Animation.LOOP_NONE
	var output_tracks: Dictionary = {}
	var output_offset := 0.0
	for raw_segment in segments:
		if not raw_segment is Dictionary:
			continue
		var segment: Dictionary = raw_segment
		var source: Animation = segment.get("animation") as Animation
		if source == null:
			continue
		var start_time := clampf(float(segment.get("start", 0.0)), 0.0, source.length)
		var end_time := clampf(float(segment.get("end", source.length)), start_time, source.length)
		var duration := end_time - start_time
		if duration <= 0.0001:
			continue
		var transition_frames := maxi(0, int(segment.get("transition_frames", 0)))
		var transition_duration := minf(float(transition_frames) / safe_fps, duration)
		_append_sampled_segment(result, output_tracks, source, start_time, duration, output_offset, safe_fps, transition_duration)
		output_offset += duration
	result.length = maxf(output_offset, result.step)
	return result


func _append_sampled_segment(
	result: Animation,
	output_tracks: Dictionary,
	source: Animation,
	start_time: float,
	duration: float,
	output_offset: float,
	fps: float,
	transition_duration: float
) -> void:
	var frame_count := maxi(1, ceili(duration * fps))
	for source_track in range(source.get_track_count()):
		var track_type := source.track_get_type(source_track)
		if not _is_supported_track_type(track_type):
			continue
		var path := source.track_get_path(source_track)
		var track_key := "%d|%s" % [track_type, str(path)]
		var output_track: int
		if output_tracks.has(track_key):
			output_track = int(output_tracks[track_key])
		else:
			output_track = result.add_track(track_type)
			result.track_set_path(output_track, path)
			result.track_set_interpolation_type(output_track, source.track_get_interpolation_type(source_track))
			result.track_set_interpolation_loop_wrap(output_track, false)
			result.track_set_enabled(output_track, source.track_is_enabled(source_track))
			output_tracks[track_key] = output_track
		var blend_from: Variant = null
		if transition_duration > 0.0 and output_offset > 0.0 and result.track_get_key_count(output_track) > 0:
			blend_from = result.track_get_key_value(output_track, result.track_get_key_count(output_track) - 1)

		for frame in range(frame_count + 1):
			var local_time := minf(float(frame) / fps, duration)
			var source_time := start_time + local_time
			var value: Variant = _sample_track(source, source_track, source_time, track_type)
			if value == null:
				continue
			if blend_from != null and local_time < transition_duration:
				var alpha := smoothstep(0.0, transition_duration, local_time)
				value = _blend_value(blend_from, value, alpha, track_type)
			result.track_insert_key(output_track, output_offset + local_time, value)


func _blend_value(from_value: Variant, to_value: Variant, alpha: float, track_type: Animation.TrackType) -> Variant:
	match track_type:
		Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D:
			return (from_value as Vector3).lerp(to_value as Vector3, alpha)
		Animation.TYPE_ROTATION_3D:
			return (from_value as Quaternion).slerp(to_value as Quaternion, alpha)
		Animation.TYPE_BLEND_SHAPE, Animation.TYPE_BEZIER:
			return lerpf(float(from_value), float(to_value), alpha)
		Animation.TYPE_VALUE:
			if (from_value is float or from_value is int) and (to_value is float or to_value is int):
				return lerpf(float(from_value), float(to_value), alpha)
	return to_value if alpha >= 0.5 else from_value


func _is_supported_track_type(track_type: Animation.TrackType) -> bool:
	return track_type in [
		Animation.TYPE_POSITION_3D,
		Animation.TYPE_ROTATION_3D,
		Animation.TYPE_SCALE_3D,
		Animation.TYPE_BLEND_SHAPE,
		Animation.TYPE_VALUE,
		Animation.TYPE_BEZIER,
	]


func _sample_track(
	source: Animation,
	track: int,
	time: float,
	track_type: Animation.TrackType
) -> Variant:
	match track_type:
		Animation.TYPE_POSITION_3D:
			return source.position_track_interpolate(track, time)
		Animation.TYPE_ROTATION_3D:
			return source.rotation_track_interpolate(track, time)
		Animation.TYPE_SCALE_3D:
			return source.scale_track_interpolate(track, time)
		Animation.TYPE_BLEND_SHAPE:
			return source.blend_shape_track_interpolate(track, time)
		Animation.TYPE_VALUE:
			return source.value_track_interpolate(track, time)
		Animation.TYPE_BEZIER:
			return source.bezier_track_interpolate(track, time)
	return null
