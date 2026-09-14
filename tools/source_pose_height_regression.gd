extends "res://tools/source_camera_reference_projection.gd"
## Same-time independent source FK plus actual canonical build, and pure guards.

const Height = preload("res://scripts/player/operator_source_pose_height.gd")
var original_samples := 0
var protected_keys := 0


func _measure_current_rest(rest: Dictionary) -> void:
	super._measure_current_rest(rest)
	var data := _json(Height.PATH)
	_check(Height.valid_data(data), "saved height contract valid")
	report["height_profile_sha256"] = FileAccess.get_sha256(Height.PATH)
	_check(data.clips.size() == 21, "bounded21 stationary source names")
	_units(data)
	current_asset_runtime.animation_library = Height.adapt(current_asset_runtime.animation_library, current_skeleton)
	report["height_adapter_test"] = {"original_fk_samples": original_samples, "protected_keys": protected_keys,
		"scope": "Pelvis Y only; all other pose differences stay measured, not hidden by camera or scale."}


func _units(data: Dictionary) -> void:
	var library := AnimationLibrary.new()
	var local_units: float = float(current_skeleton.get_meta("iso_proportions").metres_per_source_unit) / 62.0
	for name: String in data.clips:
		var row: Dictionary = data.clips[name]
		var original := _json(SOURCE + "motion/" + String(row.height_source_name) + ".json")
		_check(FileAccess.get_sha256(SOURCE + "motion/" + name + ".json") == row.source_sha256, name + " original upper hash")
		_check(FileAccess.get_sha256(SOURCE + "motion/" + String(row.height_source_name) + ".json") == row.height_source_sha256, name + " original height hash")
		for frame in int(original.samples):
			var source_pose := _globals(original, frame)
			_check(absf(float(source_pose.hips.origin.y) - float(row.hip_y_source[frame])) < 0.00001, name + " generated Y agrees with independent Godot FK")
			original_samples += 1
		var clip := Animation.new()
		clip.length = float(row.source_duration)
		clip.loop_mode = Animation.LOOP_LINEAR
		clip.set_meta("seal_reference", true)
		clip.set_meta("source_name", name)
		clip.set_meta("source_sha256", row.source_sha256)
		if row.height_source_name != name:
			clip.set_meta("source_coverage", "composed_full")
			clip.set_meta("seal_composite_base", row.height_source_name)
		var position := clip.add_track(Animation.TYPE_POSITION_3D)
		clip.track_set_path(position, NodePath(".:mixamorig_Hips"))
		var rotation := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(rotation, NodePath(".:mixamorig_Hips"))
		var other := clip.add_track(Animation.TYPE_POSITION_3D)
		clip.track_set_path(other, NodePath(".:mixamorig_Spine2"))
		for frame in row.hip_y_source.size():
			var time := float(frame) / float(row.height_source_frames) * clip.length
			clip.position_track_insert_key(position, time, Vector3(0.001, -0.0001, -0.002))
			clip.rotation_track_insert_key(rotation, time, Quaternion(Vector3.UP, 0.1))
			clip.position_track_insert_key(other, time, Vector3(0.0, 0.3, 0.0))
		library.add_animation(name, clip)
	var converted: AnimationLibrary = Height.adapt_with_data(library, current_skeleton, data)
	var second: AnimationLibrary = Height.adapt_with_data(library, current_skeleton, data)
	var repeated: AnimationLibrary = Height.adapt_with_data(converted, current_skeleton, data)
	_check(converted != library, "returned library does not replace caller resource")
	for name in library.get_animation_list():
		var before := library.get_animation(name)
		var after := converted.get_animation(name)
		var row: Dictionary = data.clips[String(name)]
		_check(before != after, String(name) + " eligible clip cloned")
		_check(after == second.get_animation(name), String(name) + " immutable clip cache shared")
		_check(after.length == before.length and after.loop_mode == before.loop_mode and after.get_track_count() == before.get_track_count(), String(name) + " timeline unchanged")
		for track in before.get_track_count():
			_check(after.track_get_path(track) == before.track_get_path(track) and after.track_get_type(track) == before.track_get_type(track), "track identity")
			_check(after.track_get_key_count(track) == before.track_get_key_count(track), "key count")
			for key in before.track_get_key_count(track):
				_check(after.track_get_key_time(track, key) == before.track_get_key_time(track, key), "key timing")
				_check(after.track_get_key_value(track, key) == repeated.get_animation(name).track_get_key_value(track, key), "idempotent key")
				if track == 0:
					var a: Vector3 = before.track_get_key_value(track, key)
					var b: Vector3 = after.track_get_key_value(track, key)
					_check(a.y == Vector3(0.001, -0.0001, -0.002).y, "original Y immutable")
					_check(a.x == b.x and a.z == b.z, "horizontal keys immutable")
					_check(absf(b.y - float(row.hip_y_source[key]) * local_units) < 0.0000001, "exact source pelvis Y")
				else:
					_check(after.track_get_key_value(track, key) == before.track_get_key_value(track, key), "rotation/non-hips position unchanged")
				protected_keys += 1
	var off := data.duplicate(true)
	off.enabled = false
	_check(Height.adapt_with_data(library, current_skeleton, off) == library, "off preserves library identity")
	_check(Height.adapt_with_data(library, null, data) == library, "missing rig fails closed")
	for bad: Dictionary in [{}, {"schema_version": "1"}, {"enabled": "true"}, {"clips": []}, {"skeleton_sha256": "bad"}]:
		var malformed := data.duplicate(true)
		if bad.is_empty(): malformed.clear()
		else: malformed.merge(bad, true)
		_check(Height.adapt_with_data(library, current_skeleton, malformed) == library, "malformed profile fails closed")
	for invalid_value in [NAN, INF, "11.0", true]:
		var malformed := data.duplicate(true)
		malformed.clips.seal_stand.hip_y_source[0] = invalid_value
		_check(Height.adapt_with_data(library, current_skeleton, malformed) == library, "invalid height fails closed")
	var unknown := library.get_animation("seal_stand").duplicate() as Animation
	unknown.set_meta("source_name", "seal_runningjump_launch")
	var wrong_hash := library.get_animation("seal_stand").duplicate() as Animation
	wrong_hash.set_meta("source_sha256", "wrong")
	var held := library.get_animation("seal_stand").duplicate() as Animation
	held.set_meta("seal_held_source_time", 0.0)
	var unsupported := AnimationLibrary.new()
	var mutable := library.get_animation("seal_stand").duplicate() as Animation
	mutable.set_meta("operator_mutable_jump", true)
	unsupported.add_animation("mutable_jump", mutable)
	unsupported.add_animation("jump", unknown)
	unsupported.add_animation("wrong_hash", wrong_hash)
	unsupported.add_animation("held", held)
	var cache_before := Height.clips_cache.size()
	var result: AnimationLibrary = Height.adapt_with_data(unsupported, current_skeleton, data)
	_check(Height.clips_cache.size() == cache_before + 1, "only converted held clip retained; no unsupported/private cache entries")
	_check(result.get_animation("mutable_jump") == mutable, "private mutable jump bypasses height adapter")
	_check(result.get_animation("jump") == unknown, "jump untouched")
	_check(result.get_animation("wrong_hash") == wrong_hash, "wrong provenance untouched")
	for key in result.get_animation("held").track_get_key_count(0):
		_check(absf(result.get_animation("held").track_get_key_value(0,key).y - float(data.clips.seal_stand.hip_y_source[0])*local_units) < 0.0000001, "held source time retained")
	var parent := current_skeleton.get_bone_parent(0)
	_check(parent == -1, "unchanged65bone root hierarchy")
	_check(current_skeleton.get_bone_count() == 65, "no new source root bone")


func _processed_comparison(clip: String, data: Dictionary, sample_index: int, raw_pose: Dictionary) -> Dictionary:
	var result: Dictionary = super._processed_comparison(clip, data, sample_index, raw_pose)
	if not result.is_empty():
		var difference: Array = result.landmarks.hips.current_minus_original_m
		_check(absf(float(difference[1])) <= 0.000002, "corrected current pelvis height matches original " + clip)
		result["pelvis_height_parity_within_2_microns"] = absf(float(difference[1])) <= 0.000002
	return result
