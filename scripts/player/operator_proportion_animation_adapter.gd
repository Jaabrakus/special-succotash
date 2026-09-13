extends RefCounted

## Asset-build time adaptation only; the existing AnimationTree owns playback.
static var shared: Dictionary = {}

static func adapt(source: AnimationLibrary, old_rests: Array, rig: Skeleton3D, fingerprint: String) -> AnimationLibrary:
	var key := fingerprint + JSON.stringify(rig.get_meta("iso_proportions")).sha256_text()
	if shared.has(key): return shared[key]
	var result := AnimationLibrary.new()
	for name in source.get_animation_list():
		var clip := source.get_animation(name).duplicate() as Animation
		for track in clip.get_track_count():
			if clip.track_get_type(track) != Animation.TYPE_POSITION_3D: continue
			var path := clip.track_get_path(track)
			if path.get_subname_count() != 1: continue
			var bone := rig.find_bone(path.get_subname(0))
			if bone < 0: continue
			var previous: Vector3 = old_rests[bone].origin
			var current := rig.get_bone_rest(bone).origin
			for frame in clip.track_get_key_count(track):
				var value: Vector3 = clip.track_get_key_value(track, frame)
				if rig.get_bone_name(bone) == &"mixamorig_Hips":
					# Scale presentation height only; never add horizontal root travel.
					value.y *= current.y / previous.y if absf(previous.y) > .00001 else 1.0
				else:
					value = current + (value - previous)
				clip.track_set_key_value(track, frame, value)
		clip.set_meta("iso_proportion_adapted", true)
		result.add_animation(name, clip)
	shared[key] = result
	return result
