extends SceneTree

## Copies decoded source poses, with explicit phase boundaries. Source files
## remain untouched. Runtime physics supplies phase progress, not root motion.
const OUTPUT := "res://assets/animations/seal_gameplay/"

func _initialize() -> void:
	var source := load("res://assets/animations/seal_gameplay/jump_up_standing.tres") as Animation
	var landing := load("res://assets/animations/seal_gameplay/jump_down.tres") as Animation
	var up := _segment(source, 0.23333333, 0.4)
	var air := _segment(source, 0.4, 0.6333333)
	var down := _segment(landing, 0.0, 0.6)
	var running := _segment(load(OUTPUT + "jump_up.tres") as Animation, 0.0, 0.8)
	var running_air := _segment(load(OUTPUT + "jump_loop.tres") as Animation, 0.0, 0.43333333)
	var running_down := _segment(landing, 0.0, 0.6)
	_match_entry(running_air, running, 0.2)
	_match_entry(running_down, running_air, 0.5)
	# Carry the preceding phase pose into contact instead of switching to an
	# unrelated landing start. Recover source landing motion over its first half.
	for track in down.get_track_count():
		if down.track_get_type(track) != Animation.TYPE_ROTATION_3D: continue
		var previous := air.find_track(down.track_get_path(track), Animation.TYPE_ROTATION_3D)
		if previous < 0: continue
		var anchor := air.rotation_track_interpolate(previous, 1.0)
		for key in down.track_get_key_count(track):
			var time := down.track_get_key_time(track, key)
			var weight := smoothstep(0.0, 0.5, time)
			var original: Quaternion = down.track_get_key_value(track, key)
			down.track_set_key_value(track, key, anchor.slerp(original, weight))
	for pair in [["jump_coherent_up", up], ["jump_coherent_run", running], ["jump_running_air", running_air], ["jump_running_land", running_down], ["jump_coherent_air", air], ["jump_coherent_land", down]]:
		assert(ResourceSaver.save(pair[1], OUTPUT + pair[0] + ".tres") == OK)
	print("COHERENT_SOURCE_JUMP_BUILD PASS")
	quit()

func _match_entry(clip: Animation, previous: Animation, blend_end: float) -> void:
	for track in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D: continue
		var prior := previous.find_track(clip.track_get_path(track), Animation.TYPE_ROTATION_3D)
		if prior < 0: continue
		var anchor := previous.rotation_track_interpolate(prior, 1.0)
		for key in clip.track_get_key_count(track):
			var original: Quaternion = clip.track_get_key_value(track, key)
			clip.track_set_key_value(track, key, anchor.slerp(original, smoothstep(0.0, blend_end, clip.track_get_key_time(track, key))))

func _segment(source: Animation, start: float, end: float) -> Animation:
	var result := Animation.new()
	# Small non-playing tail keeps the existing bounded-timeline contract.
	result.length = 1.03333333
	result.set_meta("seal_reference", true)
	result.set_meta("source_coverage", "full")
	result.set_meta("source_asset", source.resource_path)
	result.set_meta("source_window", Vector2(start, end))
	for track in source.get_track_count():
		var type := source.track_get_type(track)
		if type not in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D]: continue
		var target := result.add_track(type)
		result.track_set_path(target, source.track_get_path(track))
		result.track_set_interpolation_loop_wrap(target, false)
		for frame in 31:
			var phase := float(frame) / 30.0
			var time := lerpf(start, end, phase)
			var value: Variant = source.rotation_track_interpolate(track, time) if type == Animation.TYPE_ROTATION_3D else source.position_track_interpolate(track, time)
			result.track_insert_key(target, phase, value)
	return result
