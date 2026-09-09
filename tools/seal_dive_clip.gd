extends RefCounted

## The decoded terminal sample repeats frame zero. A one-shot must end prone.
static func build(source: Animation) -> Animation:
	var clip := source.duplicate(true) as Animation
	var end := 0.0
	for track in clip.get_track_count():
		var count := clip.track_get_key_count(track)
		if count > 1 and is_equal_approx(clip.track_get_key_time(track, count - 1), source.length):
			var first: Variant = clip.track_get_key_value(track, 0)
			var last: Variant = clip.track_get_key_value(track, count - 1)
			var same: bool = first.is_equal_approx(last) if first is Quaternion or first is Vector3 else first == last
			if not same:
				push_error("Unexpected dive terminal sample on " + str(clip.track_get_path(track)) + ": " + str(clip.track_get_key_value(track, 0)) + " -> " + str(clip.track_get_key_value(track, count - 1)))
				return null
			clip.track_remove_key(track, count - 1)
		count = clip.track_get_key_count(track)
		if count > 0:
			end = maxf(end, clip.track_get_key_time(track, count - 1))
	clip.length = end
	clip.loop_mode = Animation.LOOP_NONE
	clip.set_meta("seal_terminal_closure_removed", true)
	return clip
