class_name SocomSoundEngineLab
extends Node3D

const Driver := preload("res://scripts/player/operator_animation_driver.gd")
const EventManager := preload("res://scripts/audio/audio_animation_event_manager.gd")
const Profile := preload("res://scripts/audio/audio_animation_event_profile.gd")

const EDIT_BONES := [
	"mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_Spine",
	"mixamorig_RightHand", "mixamorig_LeftHand", "mixamorig_Head"
]

var operator: SocomOperatorAnimationDriver
var event_manager: AudioAnimationEventManager
var camera: Camera3D
var selected_bone := "mixamorig_LeftFoot"
var selected_cue := "foot_concrete"
var timeline: HSlider
var time_label: Label
var volume_slider: HSlider
var pitch_slider: HSlider
var clip_selector: OptionButton
var bone_selector: OptionButton
var cue_selector: OptionButton
var event_list: ItemList
var status: Label
var markers: Dictionary = {}
var scrubbing := false


func _ready() -> void:
	_build_world()
	_build_operator()
	_build_audio()
	_build_ui()
	var navigation := get_node_or_null("/root/StudioNavigation")
	if navigation != null:
		navigation.call("activate")


func _process(_delta: float) -> void:
	_update_bone_markers()
	if (
		operator == null
		or operator.animation_player == null
		or operator.animation_player.current_animation.is_empty()
	):
		return
	if not scrubbing:
		timeline.value = operator.animation_player.current_animation_position
	_update_time_label()


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("202631")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c9d4e3")
	settings.ambient_light_energy = 0.75
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -28, 0)
	light.light_energy = 1.1
	add_child(light)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(18, 18)
	floor.mesh = plane
	add_child(floor)
	camera = Camera3D.new()
	camera.position = Vector3(3.8, 2.2, 4.8)
	camera.look_at_from_position(camera.position, Vector3(0, 1.0, 0))
	add_child(camera)


func _build_operator() -> void:
	operator = Driver.new()
	operator.name = "FoleyOperator"
	add_child(operator)
	operator.position = Vector3.ZERO
	for bone_name in EDIT_BONES:
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.035
		sphere.height = 0.07
		marker.mesh = sphere
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color("55d8ff")
		marker.material_override = material
		add_child(marker)
		markers[bone_name] = marker


func _build_audio() -> void:
	event_manager = operator.audio_event_manager


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.size = Vector2(410, 680)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var title := Label.new()
	title.text = "TACTICAL 3D SOUND + FOLEY LAB"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color("72e6a2"))
	column.add_child(title)
	column.add_child(_label("Animation clip"))
	clip_selector = OptionButton.new()
	column.add_child(clip_selector)
	for clip_name in operator.get_clip_names():
		clip_selector.add_item(String(clip_name))
	clip_selector.item_selected.connect(_on_clip_selected)
	column.add_child(_label("Bone attachment"))
	bone_selector = OptionButton.new()
	column.add_child(bone_selector)
	for bone_name in EDIT_BONES:
		bone_selector.add_item(bone_name)
	bone_selector.item_selected.connect(func(index: int): selected_bone = bone_selector.get_item_text(index))
	column.add_child(_label("Sound cue"))
	cue_selector = OptionButton.new()
	column.add_child(cue_selector)
	for cue_name in event_manager.foley.cue_names():
		cue_selector.add_item(cue_name)
	cue_selector.item_selected.connect(func(index: int): selected_cue = cue_selector.get_item_text(index))
	column.add_child(_label("Timeline"))
	timeline = HSlider.new()
	timeline.min_value = 0.0
	timeline.max_value = 2.0
	timeline.step = 1.0 / 30.0
	timeline.drag_started.connect(func(): scrubbing = true)
	timeline.drag_ended.connect(_on_timeline_drag_ended)
	timeline.value_changed.connect(_on_timeline_changed)
	column.add_child(timeline)
	time_label = _label("0.00 s")
	column.add_child(time_label)
	column.add_child(_label("Volume (dB)"))
	volume_slider = HSlider.new()
	volume_slider.min_value = -24
	volume_slider.max_value = 6
	volume_slider.value = 0
	column.add_child(volume_slider)
	column.add_child(_label("Pitch"))
	pitch_slider = HSlider.new()
	pitch_slider.min_value = 0.70
	pitch_slider.max_value = 1.30
	pitch_slider.step = 0.01
	pitch_slider.value = 1.0
	column.add_child(pitch_slider)
	var preview := Button.new()
	preview.text = "▶ Preview Cue at Bone"
	preview.pressed.connect(_preview_cue)
	column.add_child(preview)
	var add := Button.new()
	add.text = "+ Place Event Dot at Playhead"
	add.pressed.connect(_add_event)
	column.add_child(add)
	event_list = ItemList.new()
	event_list.custom_minimum_size.y = 150
	column.add_child(event_list)
	var save := Button.new()
	save.text = "Save Shared Foley Profile"
	save.pressed.connect(_save_profile)
	column.add_child(save)
	status = _label("Select a clip, scrub, then place a cue.")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	if clip_selector.item_count > 0:
		_on_clip_selected(0)


func _on_clip_selected(index: int) -> void:
	var clip := StringName(clip_selector.get_item_text(index))
	operator.play_action(clip)
	var animation := operator.animation_player.get_animation(clip)
	if animation != null:
		timeline.max_value = maxf(animation.length, 1.0 / 30.0)
	_refresh_events()


func _on_timeline_changed(value: float) -> void:
	if scrubbing and operator.animation_player != null:
		operator.animation_player.seek(value, true)
	_update_time_label()


func _on_timeline_drag_ended(_changed: bool) -> void:
	scrubbing = false
	operator.animation_player.seek(timeline.value, true)
	operator.animation_player.pause()


func _preview_cue() -> void:
	event_manager.preview_event(_current_event())


func _add_event() -> void:
	var clip := StringName(clip_selector.get_item_text(clip_selector.selected))
	event_manager.profile.add_event(clip, _current_event())
	_refresh_events()
	status.text = "Event placed. Save to publish it to gameplay."


func _save_profile() -> void:
	var ok := event_manager.profile.save_to_file()
	status.text = "Saved config/audio_animation_events.json" if ok else "ERROR: profile could not be saved"


func _refresh_events() -> void:
	event_list.clear()
	if clip_selector.selected < 0:
		return
	var clip := StringName(clip_selector.get_item_text(clip_selector.selected))
	for event in event_manager.profile.events_for(clip):
		event_list.add_item("%.2fs  %s  @ %s" % [event.time, event.cue, event.bone])


func _current_event() -> Dictionary:
	return {
		"time": timeline.value,
		"cue": selected_cue,
		"bone": selected_bone,
		"volume_db": volume_slider.value,
		"pitch_min": pitch_slider.value - 0.03,
		"pitch_max": pitch_slider.value + 0.03,
	}


func _update_bone_markers() -> void:
	if operator == null or operator.skeleton == null:
		return
	for bone_name in markers:
		var index := operator.skeleton.find_bone(bone_name)
		if index >= 0:
			markers[bone_name].global_position = operator.skeleton.to_global(
				operator.skeleton.get_bone_global_pose(index).origin
			)


func _update_time_label() -> void:
	if time_label != null:
		time_label.text = "%.2f / %.2f seconds" % [timeline.value, timeline.max_value]


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
