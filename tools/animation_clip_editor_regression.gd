extends SceneTree

const CLIP_EDITOR := preload("res://scripts/labs/animation_clip_editor.gd")

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var source := Animation.new()
	source.length = 2.0
	source.step = 1.0 / 30.0
	var position_track := source.add_track(Animation.TYPE_POSITION_3D)
	source.track_set_path(position_track, NodePath("Rig:mixamorig_Hips"))
	source.position_track_insert_key(position_track, 0.0, Vector3(0.0, 1.0, 0.0))
	source.position_track_insert_key(position_track, 1.0, Vector3(10.0, 1.0, 0.0))
	source.position_track_insert_key(position_track, 2.0, Vector3(20.0, 1.0, 0.0))
	var rotation_track := source.add_track(Animation.TYPE_ROTATION_3D)
	source.track_set_path(rotation_track, NodePath("Rig:mixamorig_Spine"))
	source.rotation_track_insert_key(rotation_track, 0.0, Quaternion.IDENTITY)
	source.rotation_track_insert_key(rotation_track, 2.0, Quaternion(Vector3.UP, PI))

	var editor = CLIP_EDITOR.new()
	var trimmed: Animation = editor.trim(source, 0.5, 1.5, 30.0)
	_expect(trimmed != null, "trim creates a new animation resource")
	_expect(is_equal_approx(trimmed.length, 1.0), "trim length matches the selected frame range")
	_expect(is_equal_approx(trimmed.step, 1.0 / 30.0), "trim records a 30 FPS frame step")
	_expect(trimmed.get_track_count() == 2, "trim preserves compatible position and rotation tracks")
	_expect(
		trimmed.position_track_interpolate(0, 0.0).is_equal_approx(Vector3(5.0, 1.0, 0.0)),
		"trim samples the exact in-frame pose"
	)
	_expect(
		trimmed.position_track_interpolate(0, 1.0).is_equal_approx(Vector3(15.0, 1.0, 0.0)),
		"trim samples the exact out-frame pose"
	)
	_expect(source.length == 2.0 and source.track_get_key_count(0) == 3, "trim never modifies the source clip")

	var combined: Animation = editor.combine([
		{"animation": source, "start": 0.0, "end": 0.5},
		{"animation": source, "start": 1.5, "end": 2.0},
	], 30.0)
	_expect(is_equal_approx(combined.length, 1.0), "two half-second trims combine into a one-second authored clip")
	_expect(combined.get_track_count() == 2, "combined clip merges matching skeleton tracks")
	_expect(
		combined.position_track_interpolate(0, 0.0).is_equal_approx(Vector3(0.0, 1.0, 0.0)),
		"combined clip begins at the first segment pose"
	)
	_expect(
		combined.position_track_interpolate(0, 0.5).is_equal_approx(Vector3(15.0, 1.0, 0.0)),
		"combined clip switches to the second segment at the seam"
	)
	var blended: Animation = editor.combine([
		{"animation": source, "start": 0.0, "end": 0.5},
		{"animation": source, "start": 1.5, "end": 2.0, "transition_frames": 6},
	], 30.0)
	_expect(
		blended.position_track_interpolate(0, 0.5).is_equal_approx(Vector3(5.0, 1.0, 0.0)),
		"blend handle preserves the outgoing pose at the seam"
	)
	_expect(
		blended.position_track_interpolate(0, 0.6).x > 5.0 and blended.position_track_interpolate(0, 0.6).x < 16.0,
		"blend handle interpolates toward the incoming clip over its selected frames"
	)
	var saved_path := OS.get_temp_dir().path_join("socom-authored-animation-regression.tres")
	var save_error := ResourceSaver.save(combined, saved_path)
	var reloaded := load(saved_path) as Animation
	_expect(save_error == OK and reloaded != null, "authored animation saves and reloads as a Godot resource")
	_expect(reloaded != null and is_equal_approx(reloaded.length, combined.length), "saved authored resource preserves combined timing")
	if FileAccess.file_exists(saved_path):
		DirAccess.remove_absolute(saved_path)

	if failures.is_empty():
		print("ANIMATION_CLIP_EDITOR_REGRESSION PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("ANIMATION_CLIP_EDITOR_REGRESSION FAIL ", failures)
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("CLIP_EDITOR_CHECK PASS ", description)
	else:
		failures.append(description)
		push_error("CLIP_EDITOR_CHECK FAIL %s" % description)
