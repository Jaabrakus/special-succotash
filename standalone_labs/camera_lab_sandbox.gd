@tool
class_name StandaloneCameraLabSandbox
extends Node3D

## Standalone SOCOM Camera Lab
## Full telemetry HUD, shoulder offsets, wall collision fraction, FOV zoom, and recoil recovery.

const CameraRigScript := preload("res://scripts/camera/socom_camera.gd")

var camera_rig: Node3D
var target_mannequin: CharacterBody3D

# Live stats and tuning variables
var shoulder_offset_x := 0.38
var shoulder_offset_y := 0.12
var shoulder_offset_z := 0.0
var camera_distance := 1.75
var camera_fov := 70.0
var aim_guide_visible := true

# UI Telemetry labels
var _stats_label: Label
var _collision_label: Label
var _slider_x: HSlider
var _slider_y: HSlider
var _slider_dist: HSlider
var _slider_fov: HSlider


func _ready() -> void:
	target_mannequin = get_node_or_null("TargetMannequin") as CharacterBody3D
	camera_rig = get_node_or_null("SocomCameraRig") as Node3D

	if target_mannequin == null:
		_setup_target_mannequin()
	if camera_rig == null:
		_setup_camera_rig()
	else:
		_configure_camera_rig()

	if not Engine.is_editor_hint():
		_build_full_telemetry_ui()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or camera_rig == null or _stats_label == null:
		return

	var pitch: float = rad_to_deg(float(camera_rig.get("current_pitch") if camera_rig.get("current_pitch") != null else 0.0))
	var yaw: float = rad_to_deg(float(camera_rig.get("current_yaw") if camera_rig.get("current_yaw") != null else 0.0))
	var dist: float = float(camera_rig.get("current_distance") if camera_rig.get("current_distance") != null else camera_distance)
	var col_frac: float = float(camera_rig.get("collision_fraction") if camera_rig.get("collision_fraction") != null else 1.0)

	_stats_label.text = "Pitch: %.1f° | Yaw: %.1f°\nDistance: %.2fm | FOV: %.1f°\nShoulder Offset: (%.2f, %.2f, %.2f)" % [
		pitch, yaw, dist, camera_fov, shoulder_offset_x, shoulder_offset_y, shoulder_offset_z
	]

	if _collision_label != null:
		if col_frac < 0.95:
			_collision_label.text = "Collision: OCCLUDED (%.0f%% distance)" % (col_frac * 100.0)
			_collision_label.modulate = Color(1.0, 0.4, 0.4)
		else:
			_collision_label.text = "Collision: CLEAR (100%)"
			_collision_label.modulate = Color(0.4, 0.9, 0.5)


func _configure_camera_rig() -> void:
	if camera_rig == null or target_mannequin == null:
		return
	camera_rig.set("target", target_mannequin)
	camera_rig.set("head_marker", target_mannequin.get_node_or_null("HeadMarker"))
	camera_rig.set("torso_marker", target_mannequin.get_node_or_null("TorsoMarker"))
	camera_rig.set("pelvis_marker", target_mannequin.get_node_or_null("PelvisMarker"))
	camera_rig.set("feet_marker", target_mannequin.get_node_or_null("FeetMarker"))


func _setup_target_mannequin() -> void:
	target_mannequin = CharacterBody3D.new()
	target_mannequin.name = "TargetMannequin"
	target_mannequin.position = Vector3(0.0, 0.05, 0.0)
	add_child(target_mannequin)

	var head := Marker3D.new()
	head.name = "HeadMarker"
	head.position = Vector3(0.0, 1.70, 0.0)
	target_mannequin.add_child(head)

	var torso := Marker3D.new()
	torso.name = "TorsoMarker"
	torso.position = Vector3(0.0, 1.20, 0.0)
	target_mannequin.add_child(torso)

	var pelvis := Marker3D.new()
	pelvis.name = "PelvisMarker"
	pelvis.position = Vector3(0.0, 0.85, 0.0)
	target_mannequin.add_child(pelvis)

	var feet := Marker3D.new()
	feet.name = "FeetMarker"
	feet.position = Vector3(0.0, 0.05, 0.0)
	target_mannequin.add_child(feet)


func _setup_camera_rig() -> void:
	var rig = CameraRigScript.new()
	rig.name = "SocomCameraRig"
	add_child(rig)
	camera_rig = rig
	_configure_camera_rig()


func _build_full_telemetry_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# Left telemetry & control dock
	var panel := PanelContainer.new()
	panel.offset_left = 20.0
	panel.offset_top = 20.0
	panel.offset_right = 380.0
	panel.offset_bottom = 440.0
	canvas.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "SOCOM CAMERA TELEMETRY"
	title.add_theme_color_override("font_color", Color(0.4, 0.9, 0.7))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_stats_label = Label.new()
	_stats_label.text = "Pitch: 0.0° | Yaw: 0.0°\nDistance: 1.75m | FOV: 70.0°\nShoulder Offset: (0.38, 0.12, 0.00)"
	vbox.add_child(_stats_label)

	_collision_label = Label.new()
	_collision_label.text = "Collision: CLEAR (100%)"
	_collision_label.modulate = Color(0.4, 0.9, 0.5)
	vbox.add_child(_collision_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Sliders
	var lbl_x := Label.new()
	lbl_x.text = "Shoulder Offset X:"
	vbox.add_child(lbl_x)
	_slider_x = HSlider.new()
	_slider_x.min_value = -0.8
	_slider_x.max_value = 0.8
	_slider_x.step = 0.02
	_slider_x.value = shoulder_offset_x
	_slider_x.value_changed.connect(func(v: float): shoulder_offset_x = v; _update_rig_params())
	vbox.add_child(_slider_x)

	var lbl_dist := Label.new()
	lbl_dist.text = "Camera Distance:"
	vbox.add_child(lbl_dist)
	_slider_dist = HSlider.new()
	_slider_dist.min_value = 0.6
	_slider_dist.max_value = 4.0
	_slider_dist.step = 0.05
	_slider_dist.value = camera_distance
	_slider_dist.value_changed.connect(func(v: float): camera_distance = v; _update_rig_params())
	vbox.add_child(_slider_dist)

	var kick_btn := Button.new()
	kick_btn.text = "Simulate Weapon Recoil Kick"
	kick_btn.pressed.connect(_on_simulate_recoil)
	vbox.add_child(kick_btn)


func _update_rig_params() -> void:
	if camera_rig == null:
		return
	if camera_rig.get("shoulder_offset") != null:
		camera_rig.set("shoulder_offset", Vector3(shoulder_offset_x, shoulder_offset_y, shoulder_offset_z))
	if camera_rig.get("base_distance") != null:
		camera_rig.set("base_distance", camera_distance)


func _on_simulate_recoil() -> void:
	if camera_rig != null and camera_rig.has_method("apply_functional_recoil"):
		camera_rig.call(
			"apply_functional_recoil",
			deg_to_rad(2.2),
			deg_to_rad(0.5),
			deg_to_rad(10.0),
			deg_to_rad(3.0),
			0.10,
			deg_to_rad(12.0)
		)
