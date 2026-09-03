class_name SocomRetargetMappingLab
extends Node3D

## Standalone visual authoring tool for explicit operator skin bone mappings.
## It never edits animation clips or the authoritative gameplay skeleton.

const PS1_SCENE := preload(
	"res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
)
const SUIT_SCENE := preload(
	"res://assets/characters/military_tactical_suit/military_tactical_suit_tpose.glb"
)
const SKELETON_CONTRACT := preload(
	"res://scripts/player/operator_skeleton_contract.gd"
)
const PS1_TEXTURE := preload(
	"res://assets/characters/ps1_gas_mask_soldier/trooper.png"
)
const VISUAL_SKIN_CALIBRATION := preload(
	"res://scripts/player/operator_visual_skin_calibration.gd"
)
const CHARACTER_CALIBRATION_PROFILE := preload(
	"res://scripts/labs/character_calibration/character_calibration_profile.gd"
)
const MAP_PATH := "res://config/character_skin_maps/military_tactical_suit.json"
const CALIBRATION_PROFILE_PATH := (
	"res://config/character_retarget_profiles/military_tactical_suit_v1.json"
)
const DISPLAY_HEIGHT_M := 1.85
const VIEW_CENTER := Vector3(0.0, 0.95, 0.0)
const TARGET_COLOR := Color("57d5ff")
const SOURCE_COLOR := Color("ffad4d")
const MAPPED_COLOR := Color("63e694")
const SELECTED_COLOR := Color("ffe266")

var target_root: Node3D
var source_root: Node3D
var target_skeleton: Skeleton3D
var source_skeleton: Skeleton3D
var camera: Camera3D
var mapping: Dictionary = {}
var rest_pose_offsets_degrees: Dictionary = {}
var selected_target := ""
var selected_source := ""
var bone_buttons: Dictionary = {}
var hierarchy_lines: Array[Line2D] = []
var mapping_lines: Array[Line2D] = []
var status_label: Label
var selection_label: Label
var mapping_list: ItemList
var filter_option: OptionButton
var show_meshes_toggle: CheckButton
var calibration_profile: Dictionary = {}
var calibration_report: Dictionary = {}
var calibration_status_label: Label
var left_twist_label: Label
var right_twist_label: Label
var left_twist_slider: HSlider
var right_twist_slider: HSlider
var yaw := 0.0
var camera_distance := 5.6
var _right_dragging := false


func _ready() -> void:
	_build_world()
	_load_characters()
	_load_mapping()
	_load_calibration_profile()
	_apply_profile_calibration()
	_build_ui()
	_build_bone_controls("target", target_skeleton)
	_build_bone_controls("source", source_skeleton)
	_refresh_mapping_list()
	_refresh_bone_styles()
	_refresh_calibration_report()
	_update_camera()
	set_process(true)


func _process(_delta: float) -> void:
	_update_bone_controls()


func mapping_count() -> int:
	return mapping.size()


func calibration_count() -> int:
	return rest_pose_offsets_degrees.size()


func calibration_profile_error_count() -> int:
	return CHARACTER_CALIBRATION_PROFILE.validate(calibration_profile).size()


func calibration_profile_version() -> int:
	return int(calibration_profile.get("version", 0))


func calibration_issue_count() -> int:
	return (calibration_report.get("issues", []) as Array).size()


func calibration_report_status() -> String:
	return String(calibration_report.get("status", "invalid"))


func forearm_twist_share(side: String) -> float:
	return CHARACTER_CALIBRATION_PROFILE.get_forearm_twist_share(
		calibration_profile,
		side
	)


func set_forearm_twist_share(side: String, value: float) -> void:
	CHARACTER_CALIBRATION_PROFILE.set_forearm_twist_share(
		calibration_profile,
		side,
		value
	)
	_sync_twist_controls()


func arm_alignment_error_degrees() -> float:
	return VISUAL_SKIN_CALIBRATION.arm_alignment_error_degrees(
		source_skeleton,
		_mapped_source_indices()
	)


func auto_t_pose_arms() -> void:
	rest_pose_offsets_degrees = VISUAL_SKIN_CALIBRATION.solve_t_pose_arm_offsets(
		source_skeleton,
		_mapped_source_indices()
	)
	VISUAL_SKIN_CALIBRATION.apply_offsets(
		source_skeleton,
		_mapped_source_indices(),
		rest_pose_offsets_degrees
	)
	if status_label != null:
		status_label.text = "T-pose aligned four arm joints. Save the profile to keep these offsets."


func assign_mapping(target_name: String, source_name: String) -> bool:
	if target_skeleton == null or source_skeleton == null:
		return false
	if target_skeleton.find_bone(target_name) < 0:
		return false
	var source_index := _find_compatible_source_bone(source_name)
	if source_index < 0:
		return false
	source_name = source_skeleton.get_bone_name(source_index)
	for existing_target in mapping.keys():
		if String(mapping[existing_target]) == source_name and String(existing_target) != target_name:
			mapping.erase(existing_target)
	mapping[target_name] = source_name
	selected_target = target_name
	selected_source = source_name
	_refresh_mapping_list()
	_refresh_bone_styles()
	_update_selection_label()
	return true


func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("111821")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("cbd7e5")
	environment.ambient_light_energy = 0.9
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45.0, -25.0, 0.0)
	key.light_color = Color("fff0d6")
	key.light_energy = 1.5
	key.shadow_enabled = true
	add_child(key)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 5.0)
	floor.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("263344")
	floor.material_override = floor_material
	add_child(floor)
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.current = true
	add_child(camera)


func _load_characters() -> void:
	target_root = PS1_SCENE.instantiate() as Node3D
	target_root.name = "PS1TargetRig"
	add_child(target_root)
	target_skeleton = _find_skeleton(target_root)
	if target_skeleton != null:
		SKELETON_CONTRACT.ensure_65_bones(target_skeleton)
		_normalize_mixamo_names(target_skeleton)
		_disable_animation_players(target_root)
		target_skeleton.reset_bone_poses()
		_apply_ps1_texture(target_root)
		_scale_to_height(target_root, target_skeleton, DISPLAY_HEIGHT_M)
		# This camera views from -Z, so positive world X appears on screen-left.
		target_root.position.x = 1.25

	source_root = SUIT_SCENE.instantiate() as Node3D
	source_root.name = "TacticalSuitSourceRig"
	add_child(source_root)
	source_skeleton = _find_skeleton(source_root)
	if source_skeleton != null:
		_disable_animation_players(source_root)
		source_skeleton.reset_bone_poses()
		_scale_to_height(source_root, source_skeleton, DISPLAY_HEIGHT_M)
		source_root.position.x = -1.25
		_set_named_visibility(source_root, "Mil_R5_HeadphonesT", false)
		_set_named_visibility(source_root, "Object_110", false)
		_set_named_visibility(source_root, "Object_111", false)


func _scale_to_height(model_root: Node3D, skeleton: Skeleton3D, desired_height: float) -> void:
	if skeleton == null:
		return
	model_root.force_update_transform()
	skeleton.force_update_transform()
	var head := _find_bone_by_suffix(skeleton, "Head")
	var left_foot := _find_bone_by_suffix(skeleton, "LeftFoot")
	var right_foot := _find_bone_by_suffix(skeleton, "RightFoot")
	if head < 0 or left_foot < 0 or right_foot < 0:
		return
	var head_world := skeleton.to_global(skeleton.get_bone_global_rest(head).origin)
	var feet_world := (
		skeleton.to_global(skeleton.get_bone_global_rest(left_foot).origin)
		+ skeleton.to_global(skeleton.get_bone_global_rest(right_foot).origin)
	) * 0.5
	var current_height := head_world.distance_to(feet_world)
	if current_height > 0.001:
		model_root.scale *= desired_height / current_height
		model_root.force_update_transform()
		skeleton.force_update_transform()
		head_world = skeleton.to_global(skeleton.get_bone_global_rest(head).origin)
		feet_world = (
			skeleton.to_global(skeleton.get_bone_global_rest(left_foot).origin)
			+ skeleton.to_global(skeleton.get_bone_global_rest(right_foot).origin)
		) * 0.5
		model_root.global_position.y -= feet_world.y


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "AuthoringUI"
	add_child(canvas)
	var title := Label.new()
	title.text = "PS1 TARGET RIG"
	title.position = Vector2(90, 24)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TARGET_COLOR)
	canvas.add_child(title)
	var source_title := Label.new()
	source_title.text = "TACTICAL SUIT SOURCE RIG"
	source_title.position = Vector2(480, 24)
	source_title.add_theme_font_size_override("font_size", 22)
	source_title.add_theme_color_override("font_color", SOURCE_COLOR)
	canvas.add_child(source_title)

	var panel := PanelContainer.new()
	panel.name = "MappingPanel"
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.anchor_left = 0.76
	panel.offset_left = 8.0
	panel.offset_top = 16.0
	panel.offset_right = -16.0
	panel.offset_bottom = -16.0
	canvas.add_child(panel)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("1a2431e8")
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var heading := Label.new()
	heading.text = "BONE MAPPING"
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color("f1f5fa"))
	column.add_child(heading)
	var help := Label.new()
	help.text = "Click one cyan PS1 bone and one orange suit bone. Right-drag rotates the view. Mouse wheel zooms. Bone sides are anatomical: a facing character's Right appears on your left."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)
	filter_option = OptionButton.new()
	filter_option.add_item("Core body bones")
	filter_option.add_item("All bones")
	filter_option.add_item("Finger bones")
	filter_option.item_selected.connect(_filter_changed)
	column.add_child(filter_option)
	show_meshes_toggle = CheckButton.new()
	show_meshes_toggle.text = "Show character meshes"
	show_meshes_toggle.button_pressed = true
	show_meshes_toggle.toggled.connect(_show_meshes_changed)
	column.add_child(show_meshes_toggle)
	var t_pose_button := Button.new()
	t_pose_button.text = "AUTO-ALIGN SUIT TO T-POSE"
	t_pose_button.pressed.connect(auto_t_pose_arms)
	column.add_child(t_pose_button)
	selection_label = Label.new()
	selection_label.text = "PS1: none\nSuit: none"
	selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_label.custom_minimum_size.y = 54
	column.add_child(selection_label)
	mapping_list = ItemList.new()
	mapping_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mapping_list.custom_minimum_size.y = 260
	mapping_list.item_selected.connect(_mapping_item_selected)
	column.add_child(mapping_list)
	var remove_button := Button.new()
	remove_button.text = "REMOVE SELECTED PAIR"
	remove_button.pressed.connect(_remove_selected_pair)
	column.add_child(remove_button)
	var save_button := Button.new()
	save_button.text = "SAVE PROFILE"
	save_button.pressed.connect(_save_mapping)
	column.add_child(save_button)
	status_label = Label.new()
	status_label.text = "Loaded %d mappings. Mapping names alone does not correct a bad rest-pose axis." % mapping.size()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("aebed0"))
	column.add_child(status_label)
	_add_calibration_controls(column)


func _add_calibration_controls(column: VBoxContainer) -> void:
	column.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = "CHARACTER CALIBRATION V1"
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", Color("8de6c1"))
	column.add_child(heading)
	var help := Label.new()
	help.text = "Analyze palm and foot axes before animation baking. Twist sliders divide rotation between the forearm and hand; they never change gameplay aim."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)
	var analyze_button := Button.new()
	analyze_button.name = "AnalyzeCalibration"
	analyze_button.text = "ANALYZE PALMS & FEET"
	analyze_button.pressed.connect(_refresh_calibration_report)
	column.add_child(analyze_button)
	calibration_status_label = Label.new()
	calibration_status_label.name = "CalibrationStatus"
	calibration_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(calibration_status_label)

	left_twist_label = Label.new()
	column.add_child(left_twist_label)
	left_twist_slider = _new_twist_slider("LeftTwistShare", "left")
	column.add_child(left_twist_slider)
	right_twist_label = Label.new()
	column.add_child(right_twist_label)
	right_twist_slider = _new_twist_slider("RightTwistShare", "right")
	column.add_child(right_twist_slider)
	_sync_twist_controls()

	var save_calibration_button := Button.new()
	save_calibration_button.name = "SaveCalibrationProfile"
	save_calibration_button.text = "SAVE CALIBRATION PROFILE"
	save_calibration_button.pressed.connect(_save_calibration_profile)
	column.add_child(save_calibration_button)


func _new_twist_slider(control_name: String, side: String) -> HSlider:
	var slider := HSlider.new()
	slider.name = control_name
	slider.min_value = 0.5
	slider.max_value = 0.9
	slider.step = 0.01
	slider.value_changed.connect(_twist_share_changed.bind(side))
	return slider


func _twist_share_changed(value: float, side: String) -> void:
	CHARACTER_CALIBRATION_PROFILE.set_forearm_twist_share(
		calibration_profile,
		side,
		value
	)
	_sync_twist_controls(false)
	if calibration_status_label != null:
		calibration_status_label.text = "Twist distribution changed. Save the calibration profile to keep it."


func _sync_twist_controls(update_values := true) -> void:
	var left_share := forearm_twist_share("left")
	var right_share := forearm_twist_share("right")
	if update_values:
		if left_twist_slider != null:
			left_twist_slider.set_value_no_signal(left_share)
		if right_twist_slider != null:
			right_twist_slider.set_value_no_signal(right_share)
	if left_twist_label != null:
		left_twist_label.text = "LEFT ARM TWIST  •  FOREARM %d%%  /  HAND %d%%" % [
			roundi(left_share * 100.0),
			roundi((1.0 - left_share) * 100.0),
		]
	if right_twist_label != null:
		right_twist_label.text = "RIGHT ARM TWIST  •  FOREARM %d%%  /  HAND %d%%" % [
			roundi(right_share * 100.0),
			roundi((1.0 - right_share) * 100.0),
		]


func _build_bone_controls(side: String, skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	var canvas := get_node("AuthoringUI") as CanvasLayer
	for bone_index in range(skeleton.get_bone_count()):
		var line := Line2D.new()
		line.width = 1.0
		line.default_color = Color(TARGET_COLOR if side == "target" else SOURCE_COLOR, 0.34)
		line.z_index = 1
		canvas.add_child(line)
		hierarchy_lines.append(line)
		var button := Button.new()
		button.name = "%sBone%d" % [side.to_pascal_case(), bone_index]
		button.custom_minimum_size = Vector2(13, 13)
		button.size = Vector2(13, 13)
		button.text = ""
		button.tooltip_text = skeleton.get_bone_name(bone_index)
		button.focus_mode = Control.FOCUS_NONE
		button.z_index = 3
		button.pressed.connect(_bone_selected.bind(side, bone_index))
		canvas.add_child(button)
		bone_buttons["%s:%d" % [side, bone_index]] = {
			"button": button,
			"line": line,
			"skeleton": skeleton,
			"index": bone_index,
			"side": side,
		}


func _update_bone_controls() -> void:
	if camera == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	for key in bone_buttons:
		var entry: Dictionary = bone_buttons[key]
		var skeleton := entry["skeleton"] as Skeleton3D
		var bone_index := int(entry["index"])
		var button := entry["button"] as Button
		var line := entry["line"] as Line2D
		var bone_name := skeleton.get_bone_name(bone_index)
		var filter_visible := _bone_passes_filter(bone_name, String(entry["side"]))
		var world := skeleton.to_global(skeleton.get_bone_global_pose(bone_index).origin)
		var behind := camera.is_position_behind(world)
		var screen := camera.unproject_position(world)
		var inside_authoring_view := screen.x < viewport_size.x * 0.76
		button.visible = filter_visible and not behind and inside_authoring_view
		button.position = screen - button.size * 0.5
		var parent_index := skeleton.get_bone_parent(bone_index)
		line.visible = button.visible and parent_index >= 0
		if line.visible:
			var parent_world := skeleton.to_global(
				skeleton.get_bone_global_pose(parent_index).origin
			)
			line.points = PackedVector2Array([camera.unproject_position(parent_world), screen])
	_update_mapping_lines()


func _update_mapping_lines() -> void:
	while mapping_lines.size() < mapping.size():
		var line := Line2D.new()
		line.width = 2.0
		line.default_color = Color(MAPPED_COLOR, 0.5)
		line.z_index = 2
		(get_node("AuthoringUI") as CanvasLayer).add_child(line)
		mapping_lines.append(line)
	var line_index := 0
	var targets: Array = mapping.keys()
	targets.sort()
	for target_variant in targets:
		var target_name := String(target_variant)
		var source_name := String(mapping[target_variant])
		var target_index := target_skeleton.find_bone(target_name)
		var source_index := _find_compatible_source_bone(source_name)
		var line := mapping_lines[line_index]
		line_index += 1
		line.visible = target_index >= 0 and source_index >= 0 and _bone_passes_filter(target_name, "target")
		if not line.visible:
			continue
		var target_world := target_skeleton.to_global(
			target_skeleton.get_bone_global_pose(target_index).origin
		)
		var source_world := source_skeleton.to_global(
			source_skeleton.get_bone_global_pose(source_index).origin
		)
		line.points = PackedVector2Array([
			camera.unproject_position(target_world),
			camera.unproject_position(source_world),
		])
	for hidden_index in range(line_index, mapping_lines.size()):
		mapping_lines[hidden_index].visible = false


func _bone_selected(side: String, bone_index: int) -> void:
	var skeleton := target_skeleton if side == "target" else source_skeleton
	var bone_name := skeleton.get_bone_name(bone_index)
	if side == "target":
		selected_target = bone_name
		if mapping.has(bone_name):
			selected_source = String(mapping[bone_name])
	else:
		selected_source = bone_name
	if not selected_target.is_empty() and not selected_source.is_empty():
		assign_mapping(selected_target, selected_source)
	_refresh_bone_styles()
	_update_selection_label()


func _refresh_bone_styles() -> void:
	for key in bone_buttons:
		var entry: Dictionary = bone_buttons[key]
		var skeleton := entry["skeleton"] as Skeleton3D
		var bone_name := skeleton.get_bone_name(int(entry["index"]))
		var side := String(entry["side"])
		var color := TARGET_COLOR if side == "target" else SOURCE_COLOR
		if side == "target" and mapping.has(bone_name):
			color = MAPPED_COLOR
		elif side == "source" and bone_name in mapping.values():
			color = MAPPED_COLOR
		if (side == "target" and bone_name == selected_target) or (side == "source" and bone_name == selected_source):
			color = SELECTED_COLOR
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.corner_radius_top_left = 7
		style.corner_radius_top_right = 7
		style.corner_radius_bottom_left = 7
		style.corner_radius_bottom_right = 7
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.border_color = color.lightened(0.25)
		(entry["button"] as Button).add_theme_stylebox_override("normal", style)
		(entry["button"] as Button).add_theme_stylebox_override("hover", style)
		(entry["button"] as Button).add_theme_stylebox_override("pressed", style)


func _update_selection_label() -> void:
	selection_label.text = "PS1: %s\nSuit: %s" % [
		selected_target if not selected_target.is_empty() else "none",
		selected_source if not selected_source.is_empty() else "none",
	]


func _refresh_mapping_list() -> void:
	if mapping_list == null:
		return
	mapping_list.clear()
	var targets: Array = mapping.keys()
	targets.sort()
	for target_variant in targets:
		var target_name := String(target_variant)
		mapping_list.add_item("%s  →  %s" % [target_name, String(mapping[target_variant])])
		mapping_list.set_item_metadata(mapping_list.item_count - 1, target_name)


func _mapping_item_selected(index: int) -> void:
	selected_target = String(mapping_list.get_item_metadata(index))
	selected_source = String(mapping.get(selected_target, ""))
	_refresh_bone_styles()
	_update_selection_label()


func _remove_selected_pair() -> void:
	if selected_target.is_empty() or not mapping.has(selected_target):
		status_label.text = "Select a mapped PS1 bone first."
		return
	mapping.erase(selected_target)
	status_label.text = "Removed %s. Save to apply the change." % selected_target
	selected_source = ""
	_refresh_mapping_list()
	_refresh_bone_styles()
	_update_selection_label()


func _save_mapping() -> void:
	var file := FileAccess.open(MAP_PATH, FileAccess.WRITE)
	if file == null:
		status_label.text = "Could not write %s" % MAP_PATH
		return
	var ordered_mapping: Dictionary = {}
	var targets: Array = mapping.keys()
	targets.sort()
	for target in targets:
		ordered_mapping[String(target)] = String(mapping[target])
	file.store_string(JSON.stringify({
		"schema_version": 2,
		"source_skin": "military_tactical_suit",
		"target_rig": "ps1_operator_65",
		"notes": "Authored by retarget_mapping_lab.tscn. Restart gameplay after saving.",
		"calibration": {
			"auto_t_pose_arms": false,
			"rotation_offsets_degrees": rest_pose_offsets_degrees,
		},
		"mappings": ordered_mapping,
	}, "  ", false) + "\n")
	file.close()
	status_label.text = "Saved %d mappings. Restart gameplay to load them." % mapping.size()


func _load_mapping() -> void:
	mapping.clear()
	if not FileAccess.file_exists(MAP_PATH):
		return
	var file := FileAccess.open(MAP_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary and (parsed as Dictionary).get("mappings", {}) is Dictionary:
		mapping = ((parsed as Dictionary)["mappings"] as Dictionary).duplicate(true)
		var calibration = (parsed as Dictionary).get("calibration", {})
		if calibration is Dictionary:
			var stored_offsets = (calibration as Dictionary).get(
				"rotation_offsets_degrees",
				{}
			)
			if stored_offsets is Dictionary:
				rest_pose_offsets_degrees = (stored_offsets as Dictionary).duplicate(true)
			if bool((calibration as Dictionary).get("auto_t_pose_arms", false)):
				rest_pose_offsets_degrees = VISUAL_SKIN_CALIBRATION.solve_t_pose_arm_offsets(
					source_skeleton,
					_mapped_source_indices()
				)


func _load_calibration_profile() -> void:
	calibration_profile = CHARACTER_CALIBRATION_PROFILE.load_profile(
		CALIBRATION_PROFILE_PATH
	)


func _save_calibration_profile() -> void:
	var error := CHARACTER_CALIBRATION_PROFILE.save_profile(
		CALIBRATION_PROFILE_PATH,
		calibration_profile
	)
	if calibration_status_label == null:
		return
	if error == OK:
		calibration_status_label.text = "Saved calibration profile version %d." % calibration_profile_version()
	else:
		calibration_status_label.text = "Calibration profile was not saved: %s" % error_string(error)


func _refresh_calibration_report() -> void:
	var profile_errors := CHARACTER_CALIBRATION_PROFILE.validate(calibration_profile)
	var palm_metrics: Dictionary = {}
	var foot_metrics: Dictionary = {}
	var issues: Array[String] = []
	if profile_errors.is_empty():
		for side in ["left", "right"]:
			var side_title: String = String(side).capitalize()
			var palm := _palm_alignment_metrics(side_title)
			var foot := _foot_alignment_metrics(side_title)
			palm_metrics[side] = palm
			foot_metrics[side] = foot
			var quality := calibration_profile.get("quality_limits", {}) as Dictionary
			if float(palm.get("forward_error_degrees", INF)) > float(quality.get("palm_forward_error_degrees", 5.0)):
				issues.append("%s palm forward axis needs calibration" % side_title)
			if float(palm.get("normal_error_degrees", INF)) > float(quality.get("palm_normal_error_degrees", 5.0)):
				issues.append("%s palm normal needs calibration" % side_title)
			if float(foot.get("forward_error_degrees", INF)) > float(quality.get("foot_forward_error_degrees", 5.0)):
				issues.append("%s foot/toe direction needs calibration" % side_title)
			if float(foot.get("up_error_degrees", INF)) > float(quality.get("sole_normal_error_degrees", 7.5)):
				issues.append("%s ankle/sole direction needs calibration" % side_title)
	else:
		issues.append_array(profile_errors)
	calibration_report = {
		"status": "pass" if issues.is_empty() else "needs_calibration",
		"profile_errors": profile_errors,
		"palm_metrics": palm_metrics,
		"foot_metrics": foot_metrics,
		"issues": issues,
	}
	if calibration_status_label != null:
		calibration_status_label.text = _calibration_report_text()


func _calibration_report_text() -> String:
	if calibration_report_status() == "pass":
		return "PASS • Palm and foot rest axes are inside the profile limits."
	var lines: Array[String] = [
		"NEEDS CALIBRATION • %d issue(s)" % calibration_issue_count()
	]
	for issue in calibration_report.get("issues", []):
		lines.append("• %s" % String(issue))
	for side in ["left", "right"]:
		var palm = (calibration_report.get("palm_metrics", {}) as Dictionary).get(side, {})
		var foot = (calibration_report.get("foot_metrics", {}) as Dictionary).get(side, {})
		if palm is Dictionary and not (palm as Dictionary).is_empty():
			lines.append("%s palm: forward %.1f° • normal %.1f°" % [
				side.capitalize(),
				float((palm as Dictionary).get("forward_error_degrees", INF)),
				float((palm as Dictionary).get("normal_error_degrees", INF)),
			])
		if foot is Dictionary and not (foot as Dictionary).is_empty():
			lines.append("%s foot: toe %.1f° • sole %.1f°" % [
				side.capitalize(),
				float((foot as Dictionary).get("forward_error_degrees", INF)),
				float((foot as Dictionary).get("up_error_degrees", INF)),
			])
	return "\n".join(lines)


func _palm_alignment_metrics(side: String) -> Dictionary:
	var target_indices := {
		"hand": _find_bone_by_suffix(target_skeleton, "%sHand" % side),
		"index": _find_bone_by_suffix(target_skeleton, "%sHandIndex1" % side),
		"middle": _find_bone_by_suffix(target_skeleton, "%sHandMiddle1" % side),
		"pinky": _find_bone_by_suffix(target_skeleton, "%sHandPinky1" % side),
	}
	var target_basis := _palm_basis(
		target_skeleton,
		int(target_indices["hand"]),
		int(target_indices["index"]),
		int(target_indices["middle"]),
		int(target_indices["pinky"])
	)
	var source_chain = (calibration_profile.get("anatomy", {}) as Dictionary).get(
		"%s_arm" % side.to_lower(),
		{}
	)
	if not source_chain is Dictionary:
		return {}
	var source_indices := {
		"hand": _find_compatible_source_bone(String((source_chain as Dictionary).get("hand", ""))),
		"index": _find_compatible_source_bone(String((source_chain as Dictionary).get("index_knuckle", ""))),
		"middle": _find_compatible_source_bone(String((source_chain as Dictionary).get("middle_knuckle", ""))),
		"pinky": _find_compatible_source_bone(String((source_chain as Dictionary).get("pinky_knuckle", ""))),
	}
	var source_basis := _palm_basis(
		source_skeleton,
		int(source_indices["hand"]),
		int(source_indices["index"]),
		int(source_indices["middle"]),
		int(source_indices["pinky"])
	)
	if target_basis.is_empty() or source_basis.is_empty():
		var missing: Array[String] = []
		for key in target_indices:
			if int(target_indices[key]) < 0:
				missing.append("reference.%s" % String(key))
		for key in source_indices:
			if int(source_indices[key]) < 0:
				missing.append("character.%s" % String(key))
		var stored_measurements = calibration_profile.get("latest_measurements", {})
		var stored_palm = (
			(stored_measurements as Dictionary).get("%s_palm" % side.to_lower(), {})
			if stored_measurements is Dictionary
			else {}
		)
		if stored_palm is Dictionary and not (stored_palm as Dictionary).is_empty():
			return {
				"forward_error_degrees": float((stored_palm as Dictionary).get("forward_error_degrees", INF)),
				"normal_error_degrees": float((stored_palm as Dictionary).get("normal_error_degrees", INF)),
				"measurement_source": String((stored_measurements as Dictionary).get("method", "offline")),
			}
		return {
			"forward_error_degrees": INF,
			"normal_error_degrees": INF,
			"missing_landmarks": missing,
		}
	return {
		"forward_error_degrees": rad_to_deg(
			(target_basis["forward"] as Vector3).angle_to(source_basis["forward"] as Vector3)
		),
		"normal_error_degrees": rad_to_deg(
			(target_basis["normal"] as Vector3).angle_to(source_basis["normal"] as Vector3)
		),
	}


func _foot_alignment_metrics(side: String) -> Dictionary:
	var target_basis := _foot_basis(
		target_skeleton,
		_find_bone_by_suffix(target_skeleton, "%sLeg" % side),
		_find_bone_by_suffix(target_skeleton, "%sFoot" % side),
		_find_bone_by_suffix(target_skeleton, "%sToeBase" % side)
	)
	var source_chain = (calibration_profile.get("anatomy", {}) as Dictionary).get(
		"%s_leg" % side.to_lower(),
		{}
	)
	if not source_chain is Dictionary:
		return {}
	var source_basis := _foot_basis(
		source_skeleton,
		_find_compatible_source_bone(String((source_chain as Dictionary).get("lower_leg", ""))),
		_find_compatible_source_bone(String((source_chain as Dictionary).get("foot", ""))),
		_find_compatible_source_bone(String((source_chain as Dictionary).get("toe", "")))
	)
	if target_basis.is_empty() or source_basis.is_empty():
		return {}
	return {
		"forward_error_degrees": rad_to_deg(
			(target_basis["forward"] as Vector3).angle_to(source_basis["forward"] as Vector3)
		),
		"up_error_degrees": rad_to_deg(
			(target_basis["up"] as Vector3).angle_to(source_basis["up"] as Vector3)
		),
	}


func _palm_basis(
	skeleton: Skeleton3D,
	hand_index: int,
	index_index: int,
	middle_index: int,
	pinky_index: int
) -> Dictionary:
	if skeleton == null or [hand_index, index_index, middle_index, pinky_index].min() < 0:
		return {}
	var hand := _rest_world_origin(skeleton, hand_index)
	var middle := _rest_world_origin(skeleton, middle_index)
	var index := _rest_world_origin(skeleton, index_index)
	var pinky := _rest_world_origin(skeleton, pinky_index)
	var forward := middle - hand
	var across := index - pinky
	if forward.length_squared() <= 0.000001 or across.length_squared() <= 0.000001:
		return {}
	forward = forward.normalized()
	across = across.normalized()
	var normal := forward.cross(across).normalized()
	return {"forward": forward, "normal": normal}


func _foot_basis(
	skeleton: Skeleton3D,
	lower_leg_index: int,
	foot_index: int,
	toe_index: int
) -> Dictionary:
	if skeleton == null or [lower_leg_index, foot_index, toe_index].min() < 0:
		return {}
	var lower_leg := _rest_world_origin(skeleton, lower_leg_index)
	var foot := _rest_world_origin(skeleton, foot_index)
	var toe := _rest_world_origin(skeleton, toe_index)
	var forward := toe - foot
	var up := lower_leg - foot
	if forward.length_squared() <= 0.000001 or up.length_squared() <= 0.000001:
		return {}
	return {"forward": forward.normalized(), "up": up.normalized()}


func _rest_world_origin(skeleton: Skeleton3D, bone_index: int) -> Vector3:
	return skeleton.to_global(skeleton.get_bone_global_rest(bone_index).origin)


func _apply_profile_calibration() -> void:
	VISUAL_SKIN_CALIBRATION.apply_offsets(
		source_skeleton,
		_mapped_source_indices(),
		rest_pose_offsets_degrees
	)


func _mapped_source_indices() -> Dictionary:
	var indices: Dictionary = {}
	for target_variant in mapping:
		var source_index := _find_compatible_source_bone(String(mapping[target_variant]))
		if source_index >= 0:
			indices[String(target_variant)] = source_index
	return indices


func _filter_changed(_index: int) -> void:
	_refresh_bone_styles()


func _bone_passes_filter(bone_name: String, side := "") -> bool:
	var is_finger := _is_finger_bone(bone_name)
	match filter_option.selected if filter_option != null else 0:
		1:
			return true
		2:
			return is_finger
		_:
			if side == "target":
				return mapping.has(bone_name)
			if side == "source":
				return _source_bone_is_mapped(bone_name)
			return not is_finger


func _source_bone_is_mapped(bone_name: String) -> bool:
	var normalized := _canonical_bone_name(bone_name)
	for source_variant in mapping.values():
		if _canonical_bone_name(String(source_variant)) == normalized:
			return true
	return false


func _is_finger_bone(bone_name: String) -> bool:
	return (
		"Thumb" in bone_name
		or "Index" in bone_name
		or "Middle" in bone_name
		or "Ring" in bone_name
		or "Pinky" in bone_name
	)


func _show_meshes_changed(visible: bool) -> void:
	_set_mesh_visibility(target_root, visible)
	_set_mesh_visibility(source_root, visible)


func _set_mesh_visibility(node: Node, visible: bool) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).visible = visible
	for child in node.get_children():
		_set_mesh_visibility(child, visible)


func _apply_ps1_texture(node: Node) -> void:
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_texture = PS1_TEXTURE
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.roughness = 0.95
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_apply_ps1_texture(child)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			_right_dragging = mouse_button.pressed
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(camera_distance - 0.35, 2.8)
			_update_camera()
		elif mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(camera_distance + 0.35, 9.0)
			_update_camera()
	elif event is InputEventMouseMotion and _right_dragging:
		yaw -= (event as InputEventMouseMotion).relative.x * 0.008
		_update_camera()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			get_tree().quit()


func _update_camera() -> void:
	if camera == null:
		return
	var orbit := Vector3(sin(yaw), 0.18, -cos(yaw)) * camera_distance
	camera.global_position = VIEW_CENTER + orbit
	camera.look_at(VIEW_CENTER, Vector3.UP)


func _normalize_mixamo_names(skeleton: Skeleton3D) -> void:
	for index in range(skeleton.get_bone_count()):
		var name_string := String(skeleton.get_bone_name(index)).replace("mixamorig:", "mixamorig_")
		skeleton.set_bone_name(index, name_string)


func _find_bone_by_suffix(skeleton: Skeleton3D, suffix: String) -> int:
	for index in range(skeleton.get_bone_count()):
		var normalized := String(skeleton.get_bone_name(index)).replace(":", "_")
		var suffix_start := normalized.rfind("_")
		if suffix_start >= 0 and normalized.substr(suffix_start + 1).is_valid_int():
			normalized = normalized.left(suffix_start)
		if normalized.ends_with(suffix):
			return index
	return -1


func _find_compatible_source_bone(requested_name: String) -> int:
	var direct_index := source_skeleton.find_bone(requested_name)
	if direct_index >= 0:
		return direct_index
	var requested_normalized := _canonical_bone_name(requested_name)
	for index in range(source_skeleton.get_bone_count()):
		if _canonical_bone_name(source_skeleton.get_bone_name(index)) == requested_normalized:
			return index
	return -1


func _canonical_bone_name(raw_name: String) -> String:
	var normalized := raw_name.replace(":", "_")
	var suffix_start := normalized.rfind("_")
	if suffix_start >= 0 and normalized.substr(suffix_start + 1).is_valid_int():
		normalized = normalized.left(suffix_start)
	return normalized


func _disable_animation_players(node: Node) -> void:
	if node is AnimationPlayer:
		(node as AnimationPlayer).process_mode = Node.PROCESS_MODE_DISABLED
	for child in node.get_children():
		_disable_animation_players(child)


func _set_named_visibility(node: Node, target_name: String, visible: bool) -> void:
	if node.name == target_name and node is Node3D:
		(node as Node3D).visible = visible
	for child in node.get_children():
		_set_named_visibility(child, target_name, visible)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
