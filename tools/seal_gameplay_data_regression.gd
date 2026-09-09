extends SceneTree

const BUILDER = preload("res://tools/build_seal_gameplay_candidate.gd")
const POSTURE = preload("res://scripts/player/operator_posture_layer.gd")
var failures := 0

func _initialize() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/animation_presets/seal_gameplay_candidate.json"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/animations/seal_gameplay/manifest.json"))
	var before_path := "res://config/animation_presets/pre_seal_gameplay.json"
	if not FileAccess.file_exists(before_path):
		before_path = "res://config/operator_animation_map.json"
	var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(before_path))
	check(manifest.states.size() == 63, "63 existing/new states mapped")
	var firing: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/animations/seal_firing_reference/manifest.json"))
	check(firing.entries.size() == 25, "25 recovered firing-pose clips")
	for name: String in firing.entries:
		var entry: Dictionary = firing.entries[name]
		check(map.clips[name] == entry.get("composed_path", entry.path), name + " firing saved route")
		var source := load(str(entry.path)) as Animation
		var selected := load(str(map.clips[name])) as Animation
		check(source.get_meta("seal_firing_pose", false) and source.get_meta("source_sha256", "") == entry.sha256, name + " firing provenance")
		check(source.loop_mode == selected.loop_mode, name + " source loop policy")
		for track in source.get_track_count():
			var index := selected.find_track(source.track_get_path(track), source.track_get_type(track))
			check(index >= 0, name + " firing native channel retained")
			if index >= 0:
				check(selected.track_get_key_count(index) == source.track_get_key_count(track), name + " firing samples retained")
				for key in source.track_get_key_count(track):
					check(selected.track_get_key_value(index, key) == source.track_get_key_value(track, key), name + " firing samples unchanged")
	for state: String in manifest.states:
		var entry: Dictionary = manifest.states[state]
		check(map.clips[state] == entry.path, state + " saved contract")
		var clip := load(str(entry.path)) as Animation
		check(clip != null and clip.get_meta("source_name", "") == entry.source, state + " provenance")
		if clip == null:
			continue
		if entry.get("kind", "") == "held pre-recoil source frame":
			var source := load(BUILDER.ROOT + str(entry.source) + ".tres") as Animation
			for track in source.get_track_count():
				var held_track := clip.find_track(source.track_get_path(track), source.track_get_type(track))
				check(held_track >= 0, state + " held source channel exists")
				if held_track >= 0:
					check(clip.track_get_key_count(held_track) == 1 and clip.track_get_key_value(held_track, 0) == source.track_get_key_value(track, 0), state + " exact pre-recoil source sample")
		check(str(clip.get_meta("source_coverage", "")) in ["full", "composed_full"], state + " complete body")
		for section in ["clip_aliases", "mirrored_clips", "leg_mirrored_clips", "pose_yaw_offsets_degrees"]:
			check(not map[section].has(state), state + " no legacy remap")
		if "grenade" in state:
			var old_state := "grenade_toss" if state == "crouch_grenade_toss" else state
			check(absf(clip.length - BUILDER._duration(before.clips[old_state])) < 0.00001, state + " cue duration preserved")
		if BUILDER.COMPOSITES.has(state):
			var original := load(BUILDER.ROOT + str(entry.source) + ".tres") as Animation
			for track in original.get_track_count():
				var target := clip.find_track(original.track_get_path(track), original.track_get_type(track))
				check(target >= 0, state + " original channel retained")
				if target >= 0:
					check(clip.track_get_key_count(target) == original.track_get_key_count(track), state + " sample count")
					for key in original.track_get_key_count(track):
						check(clip.track_get_key_value(target, key) == original.track_get_key_value(track, key), state + " upper samples unchanged")
		if preload("res://tools/extend_seal_locomotion_candidate.gd").PAIRS.has(state):
			var original := load(BUILDER.ROOT + str(entry.source) + ".tres") as Animation
			for track in original.get_track_count():
				var target := clip.find_track(original.track_get_path(track), original.track_get_type(track))
				check(target >= 0, state + " native channel retained")
				if target >= 0:
					check(clip.track_get_key_count(target) == original.track_get_key_count(track), state + " sample count")
					for key in original.track_get_key_count(track):
						check(clip.track_get_key_value(target, key) == original.track_get_key_value(track, key), state + " native sample unchanged")
	for state: String in manifest.unconverted:
		check(map.clips[state] == before.clips[state], state + " original fallback retained")
	var posture := POSTURE.new()
	posture.configure_authored_peek(map.authored_peek)
	check(posture.authored_peek_clips.size() == 12, "12 rifle/pistol stance-side lean poses")
	for key: String in posture.authored_peek_clips:
		var clip: Animation = posture.authored_peek_clips[key]
		var maximum := 0.0
		for track in clip.get_track_count():
			if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D and "Spine" in str(clip.track_get_path(track)):
				maximum = maxf(maximum, clip.rotation_track_interpolate(track, 0).angle_to(clip.rotation_track_interpolate(track, clip.length)))
		check(maximum > deg_to_rad(5), key + " holds a non-neutral final lean")
	check(map.authored_peek == BUILDER.AUTHORED_PEEK, "builder reproduces saved lean configuration")
	print("SEAL_GAMEPLAY_DATA ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("SEAL_GAMEPLAY_DATA " + message)
