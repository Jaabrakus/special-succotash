extends RefCounted
## Build-time resource adapter. Existing AnimationTree is the only pose writer.

const PATH := "res://config/source_pose_heights.json"
const SOURCE_RIG_HASH := "26e991e38bb09147c54ce3062116466fef3225e76b5e6771da619d56e625c551"
const STATIONARY := ["seal_stand", "seal_stand_alert01", "seal_stand_alert02", "seal_crouch",
	"seal_crouch_alert01", "seal_crouch_alert02", "seal_prone", "seal_p_stand", "seal_p_crouch",
	"seal_p_prone", "seal_fp_stand", "seal_fp_crouch", "seal_fp_prone", "seal_pfp_stand",
	"seal_pfp_crouch", "seal_pfp_prone", "seal_recoil", "seal_crouch_recoil",
	"seal_prone_recoil", "seal_p_recoil", "seal_p_prone_recoil"]
static var saved: Dictionary = {}
static var clips_cache: Dictionary = {}

static func adapt(source: AnimationLibrary, rig: Skeleton3D) -> AnimationLibrary:
	if saved.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: saved = parsed
	return adapt_with_data(source, rig, saved)


static func adapt_with_data(source: AnimationLibrary, rig: Skeleton3D, data: Dictionary) -> AnimationLibrary:
	if source == null or rig == null or not valid_data(data) or not data.enabled:
		return source
	var metadata: Variant = rig.get_meta("iso_proportions", {})
	if not metadata is Dictionary or not metadata.get("source_sha256") is String or String(metadata.source_sha256) != SOURCE_RIG_HASH or rig.get_bone_count() != 65:
		return source
	var pelvis := rig.find_bone("mixamorig_Hips")
	if pelvis < 0 or rig.get_bone_parent(pelvis) != -1:
		return source
	var at_scale62: Variant = metadata.get("metres_per_source_unit")
	if not _number(at_scale62) or float(at_scale62) <= 0.0:
		return source
	var units := float(at_scale62) / 62.0
	var fingerprint := JSON.stringify(data).sha256_text() + ":" + str(units)
	var result := AnimationLibrary.new()
	for name: StringName in source.get_animation_list():
		var original := source.get_animation(name)
		if bool(original.get_meta("operator_mutable_jump", false)):
			result.add_animation(name, original)
			continue
		var key := str(original.get_instance_id()) + ":" + fingerprint
		if clips_cache.has(key):
			result.add_animation(name, clips_cache[key].result)
			continue
		var converted := _clip(original, data.clips, units)
		# Keep source alive in the cache so recycled instance IDs cannot alias.
		# Unsupported/private clips are not retained between player lifetimes.
		if converted != original: clips_cache[key] = {"source": original, "result": converted}
		result.add_animation(name, converted)
	return result


static func _clip(original: Animation, rows: Dictionary, units: float) -> Animation:
	if not bool(original.get_meta("seal_reference", false)):
		return original
	var name := String(original.get_meta("source_name", ""))
	if not rows.has(name): return original
	var row: Dictionary = rows[name]
	if String(original.get_meta("source_sha256", "")) != String(row.source_sha256): return original
	var base := String(original.get_meta("seal_composite_base", ""))
	if String(row.height_source_name) != name:
		if base != String(row.height_source_name) or String(original.get_meta("source_coverage", "")) != "composed_full": return original
	elif not base.is_empty():
		return original # Do not guess the source of a composite pelvis.
	if original.has_meta("source_window") or not is_finite(original.length) or original.length <= 0.0:
		return original # Airborne/trimmed traversal windows are outside this change.
	var track := original.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
	if track < 0 or original.track_get_key_count(track) == 0: return original
	for index in original.track_get_key_count(track):
		var time := original.track_get_key_time(track, index)
		var value: Vector3 = original.track_get_key_value(track, index)
		if not is_finite(time) or not value.is_finite() or time < 0.0 or time > original.length + 0.00001:
			return original
	var held: Variant = original.get_meta("seal_held_source_time", -1.0)
	if not _number(held) or (float(held) >= 0.0 and float(held) > float(row.height_source_duration)):
		return original
	var result := original.duplicate() as Animation
	# Animation's duplicate/property round-trip can quantize timestamp arrays.
	# Restore every original timestamp explicitly: this adapter never retimes.
	for other in original.get_track_count():
		for key in original.track_get_key_count(other):
			result.track_set_key_time(other, key, original.track_get_key_time(other, key))
	for index in result.track_get_key_count(track):
		var time := result.track_get_key_time(track, index)
		var phase := float(held) / float(row.height_source_duration) if float(held) >= 0.0 else time / original.length
		var value: Vector3 = result.track_get_key_value(track, index)
		value.y = sample(row, phase) * units
		result.track_set_key_value(track, index, value)
	result.set_meta("source_pose_height", {"schema_version": 1, "height_source_name": row.height_source_name,
		"height_source_sha256": row.height_source_sha256, "skeleton_units_per_source_unit": units})
	return result


static func sample(row: Dictionary, phase: float) -> float:
	var values: Array = row.hip_y_source
	var index := clampf(phase, 0.0, 1.0) * float(values.size() - 1)
	var lower := int(floorf(index))
	return lerpf(float(values[lower]), float(values[mini(lower + 1, values.size() - 1)]), index - lower)


static func valid_data(data: Dictionary) -> bool:
	if not _number(data.get("schema_version")) or float(data.schema_version) != 1.0 or not data.get("enabled") is bool:
		return false
	if not data.get("skeleton_sha256") is String or String(data.skeleton_sha256) != SOURCE_RIG_HASH:
		return false
	var rows: Variant = data.get("clips")
	if not rows is Dictionary or rows.is_empty(): return false
	for name in rows:
		var row: Variant = rows[name]
		if not name is String or name not in STATIONARY or not row is Dictionary: return false
		for field in ["source_sha256", "height_source_sha256"]:
			if not row.get(field) is String or String(row[field]).length() != 64: return false
		if not row.get("height_source_name") is String: return false
		for field in ["source_duration", "height_source_duration", "height_source_frames"]:
			if not _number(row.get(field)) or float(row[field]) <= 0.0: return false
		if float(row.height_source_frames) != floorf(float(row.height_source_frames)): return false
		var heights: Variant = row.get("hip_y_source")
		if not heights is Array or heights.size() != int(row.height_source_frames) + 1: return false
		for height in heights:
			if not _number(height): return false
	return true


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
