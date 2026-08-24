class_name SocomSoundEngineLab
extends Node3D

const Driver := preload("res://scripts/player/operator_animation_driver.gd")
const EventManager := preload("res://scripts/audio/audio_animation_event_manager.gd")
const Profile := preload("res://scripts/audio/audio_animation_event_profile.gd")
const AcousticEngine := preload("res://scripts/audio/acoustic_propagation_engine.gd")
const AcousticPreview := preload("res://scripts/labs/acoustic_route_preview.gd")
const RuntimeAudio := preload("res://scripts/audio/lab_leak_audio_engine.gd")

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
var acoustic_engine: AcousticPropagationEngine
var acoustic_preview: AcousticRoutePreview
var acoustic_mode: OptionButton
var acoustic_status: Label
var speed_slider: HSlider
var portal_loss_slider: HSlider
var blocked_loss_slider: HSlider
var portal_cutoff_slider: HSlider
var blocked_cutoff_slider: HSlider
var reverb_slider: HSlider
var acoustic_stream: AudioStreamWAV


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
	acoustic_engine = AcousticEngine.new()
	acoustic_engine.name = "AcousticPropagationEngine"
	add_child(acoustic_engine)
	acoustic_engine.set_listener(camera)
	acoustic_engine.route_solved.connect(_on_acoustic_route_solved)
	# Preview the exact cached stream used by live rifle fire. The Lab is now a
	# true authoring preview instead of a separate, better-sounding demo path.
	acoustic_stream = RuntimeAudio.gunshot_stream(false)


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
	_build_acoustic_ui(layer)


func _build_acoustic_ui(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -550.0
	panel.offset_right = -20.0
	panel.offset_top = 18.0
	panel.offset_bottom = -18.0
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	var title := _label("ACOUSTIC PROPAGATION + EXIT ROUTING")
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("65cfff"))
	column.add_child(title)
	var explanation := _label("A shot searches doors and windows before it bleeds through a wall. This preview changes sound only.")
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(explanation)
	acoustic_mode = OptionButton.new()
	acoustic_mode.add_item("Open air — direct path")
	acoustic_mode.add_item("Inside → open doorway → outside")
	acoustic_mode.add_item("Inside → closed wall → outside")
	acoustic_mode.select(1)
	column.add_child(acoustic_mode)
	acoustic_preview = AcousticPreview.new()
	column.add_child(acoustic_preview)
	var preview_button := Button.new()
	preview_button.text = "▶ FIRE ACOUSTIC TEST SHOT"
	preview_button.pressed.connect(_preview_acoustic_shot)
	column.add_child(preview_button)
	var impact_row := HBoxContainer.new()
	impact_row.add_theme_constant_override("separation", 8)
	column.add_child(impact_row)
	var body_button := Button.new()
	body_button.text = "Body Impact"
	body_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_button.pressed.connect(_preview_acoustic_body.bind(false))
	impact_row.add_child(body_button)
	var footstep_button := Button.new()
	footstep_button.text = "Footstep"
	footstep_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footstep_button.pressed.connect(_preview_acoustic_footstep)
	impact_row.add_child(footstep_button)
	var helmet_button := Button.new()
	helmet_button.text = "Helmet / Head Impact"
	helmet_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	helmet_button.pressed.connect(_preview_acoustic_body.bind(true))
	impact_row.add_child(helmet_button)
	var production_note := _label("RUNTIME: 24 voices • 14 events/frame • weapon/explosion priority • distance culling • material transmission")
	production_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	production_note.add_theme_font_size_override("font_size", 11)
	production_note.add_theme_color_override("font_color", Color("9dacbd"))
	column.add_child(production_note)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	speed_slider = _acoustic_slider(grid, "Sound speed", 250.0, 400.0, 1.0, acoustic_engine.profile.get_float(&"speed_of_sound_mps", 343.0))
	portal_loss_slider = _acoustic_slider(grid, "Doorway loss (dB)", -12.0, 0.0, 0.5, acoustic_engine.profile.get_float(&"portal_loss_db", -2.5))
	blocked_loss_slider = _acoustic_slider(grid, "Wall loss (dB)", -36.0, -6.0, 0.5, acoustic_engine.profile.get_float(&"blocked_loss_db", -18.0))
	portal_cutoff_slider = _acoustic_slider(grid, "Doorway clarity (Hz)", 1000.0, 16000.0, 100.0, acoustic_engine.profile.get_float(&"portal_lowpass_hz", 7200.0))
	blocked_cutoff_slider = _acoustic_slider(grid, "Wall clarity (Hz)", 300.0, 4000.0, 50.0, acoustic_engine.profile.get_float(&"blocked_lowpass_hz", 1350.0))
	reverb_slider = _acoustic_slider(grid, "Room reflection", 0.0, 0.75, 0.01, acoustic_engine.profile.get_float(&"reverb_wet", 0.24))
	var save := Button.new()
	save.text = "Save Shared Acoustic Profile"
	save.pressed.connect(_save_acoustic_profile)
	column.add_child(save)
	acoustic_status = _label("Ready. Open-door sounds emerge from the doorway.")
	acoustic_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	acoustic_status.add_theme_color_override("font_color", Color("88efb2"))
	column.add_child(acoustic_status)


func _acoustic_slider(
	grid: GridContainer,
	label_text: String,
	minimum: float,
	maximum: float,
	step_value: float,
	current: float
) -> HSlider:
	grid.add_child(_label(label_text))
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 270.0
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_value
	slider.value = current
	grid.add_child(slider)
	return slider


func _preview_acoustic_shot() -> void:
	_apply_acoustic_controls()
	var setup := _acoustic_preview_setup()
	var route := acoustic_engine.preview_event(
		acoustic_stream,
		setup.source_position,
		setup.source_zone,
		setup.listener_position,
		setup.listener_zone,
		setup.portals,
		setup.direct_clear
	)
	acoustic_preview.show_route(route, bool(setup.portal_open) or bool(setup.direct_clear))


func _preview_acoustic_body(is_headshot: bool) -> void:
	_apply_acoustic_controls()
	var setup := _acoustic_preview_setup()
	var visible_route: Dictionary = {}
	for layer: Dictionary in RuntimeAudio.body_impact_layers(is_headshot):
		var route := acoustic_engine.preview_event(
			layer.get("stream") as AudioStream,
			setup.source_position,
			setup.source_zone,
			setup.listener_position,
			setup.listener_zone,
			setup.portals,
			setup.direct_clear,
			layer
		)
		if visible_route.is_empty():
			visible_route = route
	acoustic_preview.show_route(
		visible_route, bool(setup.portal_open) or bool(setup.direct_clear)
	)
	acoustic_status.text = ("HELMET / HEAD LAYERS" if is_headshot else "BODY IMPACT LAYERS") + " • " + acoustic_status.text


func _preview_acoustic_footstep() -> void:
	_apply_acoustic_controls()
	var stream := event_manager.foley.stream_for_cue(&"foot_concrete")
	if stream == null:
		acoustic_status.text = "ERROR: footstep preview stream is missing."
		return
	var setup := _acoustic_preview_setup()
	var route := acoustic_engine.preview_event(
		stream,
		setup.source_position,
		setup.source_zone,
		setup.listener_position,
		setup.listener_zone,
		setup.portals,
		setup.direct_clear,
		{"volume_db": -1.5, "pitch_scale": 1.0}
	)
	acoustic_preview.show_route(route, bool(setup.portal_open) or bool(setup.direct_clear))
	acoustic_status.text = "FOOTSTEP • " + acoustic_status.text


func _acoustic_preview_setup() -> Dictionary:
	var mode := acoustic_mode.selected
	var source_position := Vector3(-6.0, 1.4, 0.0)
	var listener_position := Vector3(7.0, 1.5, 1.0)
	var source_zone := &"room_a"
	var listener_zone := &"outside"
	var direct_clear := mode == 0
	var portal_open := mode == 1
	if direct_clear:
		source_zone = &"outside"
	var portals: Array[Dictionary] = [{
		"id": "lab_door",
		"from_zone": &"room_a",
		"to_zone": &"outside",
		"position": Vector3(0.0, 1.2, 0.0),
		"open": portal_open,
		"bidirectional": true,
		"loss_db": acoustic_engine.profile.get_float(&"portal_loss_db", -2.5),
	}]
	return {
		"source_position": source_position,
		"listener_position": listener_position,
		"source_zone": source_zone,
		"listener_zone": listener_zone,
		"direct_clear": direct_clear,
		"portal_open": portal_open,
		"portals": portals,
	}


func _on_acoustic_route_solved(route: Dictionary) -> void:
	if acoustic_status == null:
		return
	acoustic_status.text = "%s • %.1f m • %.1f ms • %.1f dB • %.0f Hz • %d exit(s)" % [
		String(route.get("kind", "unknown")).to_upper(),
		float(route.get("distance_m", 0.0)),
		float(route.get("delay_seconds", 0.0)) * 1000.0,
		float(route.get("volume_db", 0.0)),
		float(route.get("lowpass_hz", 20500.0)),
		int(route.get("portal_hops", 0)),
	]


func _apply_acoustic_controls() -> void:
	acoustic_engine.profile.set_value(&"speed_of_sound_mps", speed_slider.value)
	acoustic_engine.profile.set_value(&"portal_loss_db", portal_loss_slider.value)
	acoustic_engine.profile.set_value(&"blocked_loss_db", blocked_loss_slider.value)
	acoustic_engine.profile.set_value(&"portal_lowpass_hz", portal_cutoff_slider.value)
	acoustic_engine.profile.set_value(&"blocked_lowpass_hz", blocked_cutoff_slider.value)
	acoustic_engine.profile.set_value(&"reverb_wet", reverb_slider.value)
	acoustic_engine.refresh_effects()


func _save_acoustic_profile() -> void:
	_apply_acoustic_controls()
	var ok := acoustic_engine.profile.save_to_file()
	acoustic_status.text = (
		"Saved config/acoustic_propagation.json for gameplay and Map Lab."
		if ok else "ERROR: acoustic profile could not be saved."
	)


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
