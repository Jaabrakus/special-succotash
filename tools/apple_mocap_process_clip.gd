extends SceneTree

## Command-line bridge for the same review-only conversion used by the intake lab.
## Usage:
##   godot --headless --path . --script res://tools/apple_mocap_process_clip.gd \
##     -- --raw /absolute/capture.apple_pose.json --name capture_name

const MotionProcessor := preload("res://scripts/mocap/apple_mocap_motion_processor.gd")
const OperatorRetargeter := preload("res://scripts/mocap/apple_mocap_operator_retargeter.gd")
const OperatorScene := preload(
	"res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var options := _arguments()
	var raw_path := str(options.get("raw", ""))
	if raw_path.is_empty():
		_fail("Missing --raw capture path.")
		return
	var raw := _load_json(raw_path)
	if raw.is_empty():
		_fail("The raw Apple capture could not be loaded: %s" % raw_path)
		return
	var requested_duration := float(options.get("duration", "-1"))
	if requested_duration > 0.0:
		raw = _slice_raw_capture(raw, float(options.get("start", "0")), requested_duration)
	var processed: Dictionary = MotionProcessor.new().process(raw)
	if not bool(processed.get("ok", false)):
		_fail("Motion processing failed: %s" % str(processed.get("errors", [])))
		return
	var source_name := str(options.get("name", "")).to_snake_case().validate_filename()
	if source_name.is_empty():
		source_name = raw_path.get_file().trim_suffix(".apple_pose.json").to_snake_case()
	if source_name.is_empty():
		source_name = "apple_motion"
	var data_directory := "user://apple_mocap"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_directory))
	var raw_copy_path := "%s/%s.apple_pose.json" % [data_directory, source_name]
	if not _save_json(raw_copy_path, raw):
		_fail("The raw Apple motion document could not be preserved.")
		return
	var processed_path := "%s/%s.processed_motion.json" % [data_directory, source_name]
	if not _save_json(processed_path, processed):
		_fail("The processed motion document could not be saved.")
		return
	var operator := OperatorScene.instantiate()
	var skeleton := _find_skeleton(operator)
	if skeleton == null:
		operator.free()
		_fail("The operator skeleton could not be loaded.")
		return
	var retargeter := OperatorRetargeter.new()
	var animation: Animation = retargeter.build_animation(
		processed,
		skeleton,
		NodePath("."),
		{"include_lower_body": str(options.get("upper-body-only", "false")) != "true"}
	)
	operator.free()
	if animation == null:
		_fail("The processed motion could not be retargeted.")
		return
	var saved: Dictionary = retargeter.save_review_animation(
		animation,
		"%s_apple_review" % source_name,
		true
	)
	if not bool(saved.get("ok", false)):
		_fail("The review animation could not be saved: %s" % str(saved.get("error", "")))
		return
	var review_path := str(saved.get("path", ""))
	var pending_path := "%s/%s.pending_review.json" % [data_directory, source_name]
	_save_json(pending_path, {
		"schema": "socom_apple_mocap_review_v1",
		"status": "PENDING",
		"source_video": str(processed.get("source_video", "")),
		"raw_motion": raw_copy_path,
		"processed_motion": processed_path,
		"review_animation": review_path,
		"created_unix_time": Time.get_unix_time_from_system(),
	})
	print("APPLE_MOCAP_PROCESS_COMPLETE")
	print("APPLE_MOCAP_SOURCE ", str(processed.get("source_video", "")))
	print("APPLE_MOCAP_FRAMES ", int(processed.get("frame_count", 0)))
	print("APPLE_MOCAP_REPAIRED_SAMPLES ", int(processed.get("repaired_samples", 0)))
	print("APPLE_MOCAP_RAW ", raw_copy_path)
	print("APPLE_MOCAP_PROCESSED ", processed_path)
	print("APPLE_MOCAP_REVIEW ", review_path)
	print("APPLE_MOCAP_STATUS PENDING")
	quit(0)


func _arguments() -> Dictionary:
	var result := {}
	var values := OS.get_cmdline_user_args()
	var index := 0
	while index < values.size():
		var key := str(values[index])
		if key.begins_with("--") and index + 1 < values.size():
			result[key.trim_prefix("--")] = str(values[index + 1])
			index += 2
		else:
			index += 1
	return result


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _slice_raw_capture(raw: Dictionary, start_seconds: float, duration_seconds: float) -> Dictionary:
	var fps := clampf(float(raw.get("fps", 15.0)), 1.0, 60.0)
	var source_frames: Array = raw.get("frames", [])
	var start_index := clampi(floori(maxf(start_seconds, 0.0) * fps), 0, maxi(source_frames.size() - 1, 0))
	var requested_count := maxi(1, ceili(maxf(duration_seconds, 1.0 / fps) * fps))
	var end_index := mini(start_index + requested_count, source_frames.size())
	var sliced_frames: Array[Dictionary] = []
	var detected_frames := 0
	for source_index in range(start_index, end_index):
		var frame: Dictionary = (source_frames[source_index] as Dictionary).duplicate(true)
		frame["source_frame"] = int(frame.get("frame", source_index))
		frame["source_time"] = float(frame.get("time", float(source_index) / fps))
		frame["frame"] = sliced_frames.size()
		frame["time"] = float(sliced_frames.size()) / fps
		if bool(frame.get("detected", false)):
			detected_frames += 1
		sliced_frames.append(frame)
	var sliced := raw.duplicate(true)
	sliced["source_start_time"] = float(start_index) / fps
	sliced["duration"] = float(maxi(sliced_frames.size() - 1, 0)) / fps
	sliced["frame_count"] = sliced_frames.size()
	sliced["detected_frames"] = detected_frames
	sliced["detected_ratio"] = float(detected_frames) / maxf(float(sliced_frames.size()), 1.0)
	sliced["frames"] = sliced_frames
	return sliced


func _save_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  ", false))
	file.close()
	return true


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	push_error(message)
	print("APPLE_MOCAP_PROCESS_FAILED ", message)
	quit(1)
