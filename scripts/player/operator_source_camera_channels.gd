extends RefCounted

const PATH := "res://config/source_camera_channels.json"
const Anchor := preload("res://scripts/player/operator_source_camera_anchor.gd")
const ROOT_PATH := NodePath("SourceCameraAnchor:root_source")
const COVERAGE_PATH := NodePath("SourceCameraAnchor:coverage")
static var channels: Dictionary = {}
static var augmented_clips: Dictionary = {}

static func data() -> Dictionary:
	if channels.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary and parsed.get("schema_version") == 1 and parsed.get("position_divisor") == 256:
			channels = parsed.get("clips", {})
	return channels

static func augment(source: AnimationLibrary, skeleton: Skeleton3D) -> AnimationLibrary:
	if not skeleton.has_node("SourceCameraAnchor"):
		var anchor := Anchor.new()
		anchor.name = "SourceCameraAnchor"
		skeleton.add_child(anchor)
	# After proportion adaptation and movement root sanitation. No shared source
	# resource is changed, and no 66th bone is appended to the skinned rig.
	var result := AnimationLibrary.new()
	for name: StringName in source.get_animation_list():
		var original := source.get_animation(name)
		var key := original.get_instance_id()
		var shared := not bool(original.get_meta("operator_mutable_jump", false))
		# Input clips are immutable shared cache resources, except the six jumps
		# already duplicated per operator by _make_jump_clips_local(). Instance
		# identity preserves that distinction and avoids179 copies per remote peer.
		if shared and augmented_clips.has(key):
			result.add_animation(name, augmented_clips[key])
			continue
		var clip := original.duplicate() as Animation
		for track in original.get_track_count():
			for index in original.track_get_key_count(track):
				clip.track_set_key_time(track,index,original.track_get_key_time(track,index))
		var descriptor := describe(clip)
		var root_track := clip.add_track(Animation.TYPE_VALUE)
		clip.track_set_path(root_track, ROOT_PATH)
		clip.value_track_set_update_mode(root_track, Animation.UPDATE_CONTINUOUS)
		clip.track_set_interpolation_loop_wrap(root_track, false)
		var valid_track := clip.add_track(Animation.TYPE_VALUE)
		clip.track_set_path(valid_track, COVERAGE_PATH)
		clip.value_track_set_update_mode(valid_track, Animation.UPDATE_CONTINUOUS)
		clip.track_insert_key(valid_track, 0.0, 0.0 if descriptor.is_empty() else 1.0)
		if descriptor.is_empty():
			clip.track_insert_key(root_track, 0.0, Vector3.ZERO)
		else:
			var times: Array[float] = [0.0, clip.length]
			if float(descriptor.timeline) > 0.0 and float(descriptor.timeline) < clip.length:
				times.append(float(descriptor.timeline))
			var row: Dictionary = data()[descriptor.name]
			var duration: float = row.duration
			var span: float = descriptor.end - descriptor.start
			if span > 0.0:
				for index in (row.positions_raw as Array).size():
					var source_time: float = float(index) * duration / float(row.frames)
					var time: float = (source_time - float(descriptor.start)) / span * float(descriptor.timeline)
					if time > 0.0 and time < clip.length: times.append(time)
			times.sort()
			for time in times:
				clip.track_insert_key(root_track, time, sample(descriptor, time))
		clip.set_meta("source_camera_channel", descriptor)
		if shared: augmented_clips[key] = clip
		result.add_animation(name, clip)
	return result

static func describe(clip: Animation, depth: int = 0) -> Dictionary:
	if clip == null or depth > 4: return {}
	if clip.has_meta("source_window") and clip.has_meta("source_asset"):
		var source := load(String(clip.get_meta("source_asset"))) as Animation
		var parent := describe(source, depth + 1)
		if parent.is_empty(): return {}
		var window: Vector2 = clip.get_meta("source_window")
		var parent_span: float = float(parent.end) - float(parent.start)
		var start: float = float(parent.start) + window.x / float(parent.timeline) * parent_span
		var end: float = float(parent.start) + window.y / float(parent.timeline) * parent_span
		# build_coherent_source_jump uses keys0..1 plus a nonplaying tail.
		return {"name":parent.name,"start":start,"end":end,"timeline":1.0}
	var name := String(clip.get_meta("source_name", ""))
	if not data().has(name):
		name = String(clip.get_meta("seal_composite_base", ""))
	if not data().has(name): return {}
	var row: Dictionary = data()[name]
	# Direct provenance must agree; composite base has its independent sidecar
	# hash. Source originals stay untouched and unavailable clips reset coverage.
	if name == String(clip.get_meta("source_name", "")) and String(clip.get_meta("source_sha256", "")) != String(row.sha256): return {}
	if clip.has_meta("seal_held_source_time"):
		var held: float = clip.get_meta("seal_held_source_time")
		return {"name":name,"start":held,"end":held,"timeline":clip.length}
	if bool(clip.get_meta("seal_terminal_closure_removed", false)):
		# The one-shot body explicitly removed the duplicate upright terminal
		# pose (seal_dive_clip.build). Its observer must use the same retained
		# source clock, not squeeze the old closing pose into the shorter clip.
		var retained_end := float(row.duration) * (float(row.frames)-1.0) / float(row.frames)
		return {"name":name,"start":0.0,"end":retained_end,"timeline":clip.length}
	return {"name":name,"start":0.0,"end":float(row.duration),"timeline":clip.length}

static func sample(descriptor: Dictionary, time: float) -> Vector3:
	if descriptor.is_empty(): return Vector3.ZERO
	var row: Dictionary = data()[descriptor.name]
	var samples: Array = row.positions_raw
	var source_time := lerpf(float(descriptor.start), float(descriptor.end), clampf(time / maxf(float(descriptor.timeline), .000001),0.0,1.0))
	var index := clampf(source_time / float(row.duration) * float(row.frames),0.0,float(samples.size()-1))
	var a: Array = samples[int(index)]
	var b: Array = samples[mini(int(index)+1,samples.size()-1)]
	return Vector3(float(a[0]),float(a[1]),float(a[2])).lerp(Vector3(float(b[0]),float(b[1]),float(b[2])),index-floorf(index)) / 256.0
