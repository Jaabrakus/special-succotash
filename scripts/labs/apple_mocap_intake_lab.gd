class_name AppleMocapIntakeLab
extends Control

const EXTRACTOR := "res://tools/apple_mocap/apple_mocap_extract"
const MOTION_PROCESSOR := preload("res://scripts/mocap/apple_mocap_motion_processor.gd")
const OPERATOR_RETARGETER := preload("res://scripts/mocap/apple_mocap_operator_retargeter.gd")
const SKELETON_CONTRACT := preload("res://scripts/player/operator_skeleton_contract.gd")
const OPERATOR_SCENE := preload(
	"res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
)

var selected_video := ""
var output_path := ""
var process_id := -1
var file_dialog: FileDialog
var video_label: Label
var status_label: Label
var result_label: Label
var fps_box: SpinBox
var crop_preset: OptionButton
var extract_button: Button
var process_button: Button
var studio_button: Button
var preview: AppleMocapPreview
var raw_motion: Dictionary = {}
var processed_path := ""
var review_animation_path := ""


func _ready() -> void:
	_build_ui()
	set_process(false)


func _process(_delta: float) -> void:
	if process_id <= 0 or OS.is_process_running(process_id):
		return
	set_process(false)
	process_id = -1
	extract_button.disabled = false
	_load_result()


func _choose_video() -> void:
	file_dialog.popup_centered_ratio(0.82)


func _video_selected(path: String) -> void:
	selected_video = path
	video_label.text = path
	extract_button.disabled = false
	status_label.text = "Ready. Apple Vision runs locally on this Mac."


func _extract() -> void:
	if selected_video.is_empty():
		return
	var extractor := ProjectSettings.globalize_path(EXTRACTOR)
	if not FileAccess.file_exists(extractor):
		status_label.text = "Extractor is missing. Run tools/apple_mocap/build_extractor.sh."
		return
	var directory := ProjectSettings.globalize_path("user://apple_mocap")
	DirAccess.make_dir_recursive_absolute(directory)
	var base := selected_video.get_file().get_basename().validate_filename()
	output_path = directory.path_join("%s.apple_pose.json" % base)
	var arguments := [selected_video, output_path, "--fps", str(fps_box.value)]
	if crop_preset != null and crop_preset.selected == 1:
		arguments.append_array(["--crop", "0.0", "0.31", "1.0", "0.38"])
	process_id = OS.create_process(extractor, arguments)
	if process_id <= 0:
		status_label.text = "Apple Vision could not start."
		return
	extract_button.disabled = true
	status_label.text = "Extracting 3D body motion on Apple Neural Engine…"
	result_label.text = "You can keep working after this process finishes."
	set_process(true)


func _load_result() -> void:
	if not FileAccess.file_exists(output_path):
		status_label.text = "Extraction failed. No result file was created."
		return
	var file := FileAccess.open(output_path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file != null else null
	if not (parsed is Dictionary):
		status_label.text = "Extraction result is invalid."
		return
	var data := parsed as Dictionary
	raw_motion = data
	var ratio := float(data.get("detected_ratio", 0.0))
	status_label.text = "Extraction complete."
	result_label.text = "%d / %d frames detected (%.1f%%)\nSaved: %s" % [
		int(data.get("detected_frames", 0)), int(data.get("frame_count", 0)), ratio * 100.0, output_path
	]
	for raw_frame in data.get("frames", []):
		if raw_frame is Dictionary and bool(raw_frame.get("detected", false)):
			preview.show_frame(raw_frame)
			break
	process_button.disabled = false


func _process_for_studio() -> void:
	if raw_motion.is_empty():
		status_label.text = "Extract or load Apple motion first."
		return
	process_button.disabled = true
	studio_button.disabled = true
	status_label.text = "Repairing frames, rebuilding motion, and retargeting the operator…"
	var processor = MOTION_PROCESSOR.new()
	var processed: Dictionary = processor.process(raw_motion)
	if not bool(processed.get("ok", false)):
		status_label.text = "Motion processing failed: %s" % str(processed.get("errors", []))
		process_button.disabled = false
		return
	processed_path = output_path.trim_suffix(".apple_pose.json") + ".processed_motion.json"
	var processed_file := FileAccess.open(processed_path, FileAccess.WRITE)
	if processed_file == null:
		status_label.text = "Could not save the processed motion document."
		process_button.disabled = false
		return
	processed_file.store_string(JSON.stringify(processed, "  ", false))
	processed_file.close()
	var operator := OPERATOR_SCENE.instantiate()
	var skeleton := _find_skeleton(operator)
	if skeleton == null:
		operator.free()
		status_label.text = "The operator skeleton could not be loaded."
		process_button.disabled = false
		return
	SKELETON_CONTRACT.ensure_65_bones(skeleton)
	var retargeter = OPERATOR_RETARGETER.new()
	var animation: Animation = retargeter.build_animation(
		processed,
		skeleton,
		NodePath("."),
		{"include_lower_body": crop_preset == null or crop_preset.selected == 0}
	)
	operator.free()
	if animation == null:
		status_label.text = "The processed joints could not be retargeted."
		process_button.disabled = false
		return
	var requested_name := selected_video.get_file().get_basename() + "_apple_review"
	var saved: Dictionary = retargeter.save_review_animation(animation, requested_name)
	if not bool(saved.get("ok", false)):
		status_label.text = "Could not save the review animation: %s" % str(saved.get("error", ""))
		process_button.disabled = false
		return
	review_animation_path = str(saved.get("path", ""))
	_save_pending_review_manifest(processed)
	status_label.text = "Review animation ready. Nothing has been approved or assigned yet."
	result_label.text = (
		"Repaired samples: %d\nFrames: %d at %.1f fps\nReview clip: %s\nProcessed motion: %s"
		% [
			int(processed.get("repaired_samples", 0)),
			int(processed.get("frame_count", 0)),
			float(processed.get("fps", 0.0)),
			review_animation_path,
			processed_path,
		]
	)
	process_button.disabled = false
	studio_button.disabled = false


func _save_pending_review_manifest(processed: Dictionary) -> void:
	var manifest_path := ProjectSettings.globalize_path("user://apple_mocap/pending_review.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"schema": "socom_apple_mocap_review_v1",
		"status": "PENDING",
		"source_video": str(processed.get("source_video", selected_video)),
		"processed_motion": processed_path,
		"review_animation": review_animation_path,
		"created_unix_time": Time.get_unix_time_from_system(),
	}, "  ", false))
	file.close()


func _open_animation_studio() -> void:
	if review_animation_path.is_empty():
		return
	get_tree().change_scene_to_file("res://animation_library_lab.tscn")


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("171c25")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var root := HSplitContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	add_child(root)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 420
	sidebar.add_theme_constant_override("separation", 14)
	root.add_child(sidebar)
	var title := Label.new()
	title.text = "APPLE VIDEO MOCAP INTAKE"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("86e4b4"))
	sidebar.add_child(title)
	var explanation := Label.new()
	explanation.text = "Convert a local video into an Apple Vision 3D body track. No NVIDIA GPU or cloud service is used. This stage creates landmarks, not a finished game animation."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(explanation)
	var choose := Button.new()
	choose.text = "1  SELECT VIDEO"
	choose.pressed.connect(_choose_video)
	sidebar.add_child(choose)
	video_label = Label.new()
	video_label.text = "No video selected"
	video_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(video_label)
	var fps_row := HBoxContainer.new()
	var fps_label := Label.new()
	fps_label.text = "Sample rate"
	fps_row.add_child(fps_label)
	fps_box = SpinBox.new()
	fps_box.min_value = 5
	fps_box.max_value = 30
	fps_box.step = 1
	fps_box.value = 15
	fps_box.suffix = " fps"
	fps_row.add_child(fps_box)
	sidebar.add_child(fps_row)
	crop_preset = OptionButton.new()
	crop_preset.add_item("Frame crop: Full video")
	crop_preset.add_item("Frame crop: Middle gameplay band")
	crop_preset.tooltip_text = "Use the middle band for vertical edits with titles above and below gameplay."
	sidebar.add_child(crop_preset)
	extract_button = Button.new()
	extract_button.text = "2  EXTRACT BODY MOTION"
	extract_button.disabled = true
	extract_button.pressed.connect(_extract)
	sidebar.add_child(extract_button)
	process_button = Button.new()
	process_button.text = "3  CLEAN + RETARGET FOR REVIEW"
	process_button.disabled = true
	process_button.pressed.connect(_process_for_studio)
	sidebar.add_child(process_button)
	studio_button = Button.new()
	studio_button.text = "4  OPEN IN ANIMATION STUDIO"
	studio_button.disabled = true
	studio_button.pressed.connect(_open_animation_studio)
	sidebar.add_child(studio_button)
	status_label = Label.new()
	status_label.text = "Select a full-body video."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(status_label)
	result_label = Label.new()
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(result_label)
	var limits := Label.new()
	limits.text = "REVIEW GATE\nProcessing repairs and retargets the capture into a pending clip. Animation Studio must review and explicitly save an approved authored animation before gameplay can use it."
	limits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	limits.add_theme_color_override("font_color", Color("d7c982"))
	sidebar.add_child(limits)
	preview = AppleMocapPreview.new()
	preview.custom_minimum_size = Vector2(620, 620)
	root.add_child(preview)
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.add_filter("*.mov, *.mp4, *.m4v", "Video files")
	file_dialog.file_selected.connect(_video_selected)
	add_child(file_dialog)
