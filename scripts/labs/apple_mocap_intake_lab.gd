class_name AppleMocapIntakeLab
extends Control

const EXTRACTOR := "res://tools/apple_mocap/apple_mocap_extract"

var selected_video := ""
var output_path := ""
var process_id := -1
var file_dialog: FileDialog
var video_label: Label
var status_label: Label
var result_label: Label
var fps_box: SpinBox
var extract_button: Button
var preview: AppleMocapPreview


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
	process_id = OS.create_process(extractor, [selected_video, output_path, "--fps", str(fps_box.value)])
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
	var ratio := float(data.get("detected_ratio", 0.0))
	status_label.text = "Extraction complete."
	result_label.text = "%d / %d frames detected (%.1f%%)\nSaved: %s" % [
		int(data.get("detected_frames", 0)), int(data.get("frame_count", 0)), ratio * 100.0, output_path
	]
	for raw_frame in data.get("frames", []):
		if raw_frame is Dictionary and bool(raw_frame.get("detected", false)):
			preview.show_frame(raw_frame)
			break


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
	extract_button = Button.new()
	extract_button.text = "2  EXTRACT BODY MOTION"
	extract_button.disabled = true
	extract_button.pressed.connect(_extract)
	sidebar.add_child(extract_button)
	status_label = Label.new()
	status_label.text = "Select a full-body video."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(status_label)
	result_label = Label.new()
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(result_label)
	var limits := Label.new()
	limits.text = "NEXT STAGE\nLandmark smoothing, confidence review, foot contacts, and Mixamo retarget are intentionally separate. This prevents a weak capture from overwriting an approved animation."
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
