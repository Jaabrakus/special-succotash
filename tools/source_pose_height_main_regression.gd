extends "res://tools/source_character_scale_regression.gd"
## Executes the existing real-main scale/equip/stance/fire proof unchanged.

const Height := preload("res://scripts/player/operator_source_pose_height.gd")


func _initialize() -> void:
	super._initialize()
	var output_supplied := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-prefix="): output_supplied = true
	if not output_supplied:
		output_prefix = "/private/tmp/source-pose-height-main"


func _sample(label: String) -> void:
	await super._sample(label)
	var verified := []
	for slot in ["idle_rifle", "seal_stand_alert02", "idle_crouch", "idle_prone", "pistol_idle", "pistol_idle_kneeling", "pistol_idle_prone"]:
		var clip: Animation = driver.animation_player.get_animation(slot)
		_check(clip != null and clip.has_meta("source_pose_height"), "real main built source pelvis metadata " + slot)
		if clip == null or not clip.has_meta("source_pose_height"): continue
		var track := clip.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
		_check(track >= 0, "source height uses existing pelvis track " + slot)
		var source: String = clip.get_meta("source_name", "")
		var row: Dictionary = Height.saved.clips.get(source, {})
		_check(not row.is_empty(), "same saved original height contract " + slot)
		if track < 0 or row.is_empty(): continue
		var metadata: Dictionary = clip.get_meta("source_pose_height")
		var local_units: float = metadata.skeleton_units_per_source_unit
		for key in clip.track_get_key_count(track):
			var phase := clip.track_get_key_time(track, key) / clip.length
			if clip.has_meta("seal_held_source_time"):
				phase = float(clip.get_meta("seal_held_source_time")) / float(row.height_source_duration)
			var value: Vector3 = clip.track_get_key_value(track, key)
			_check(absf(value.y - Height.sample(row, phase) * local_units) < 0.0000001, "real main pelvis key uses original height " + slot)
		verified.append({"slot": slot, "source": source, "height_metadata": metadata})
	var report_row: Dictionary = samples.back()
	report_row["source_pose_height_verified"] = verified
	report_row["source_pose_height_profile_sha256"] = FileAccess.get_sha256(Height.PATH)
	report_row["known_limit"] = "Stationary source pelvis Y corrected; modern skin and other retarget differences remain. No camera or collision compensation."
