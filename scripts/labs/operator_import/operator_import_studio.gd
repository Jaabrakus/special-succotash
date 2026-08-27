extends Control

const Validator := preload("res://scripts/labs/operator_import/operator_import_validator.gd")
const VisualProfile := preload("res://scripts/characters/operator_visual_profile.gd")
const Normalizer := preload("res://scripts/characters/operator_model_normalizer.gd")
const DEFAULT_MODEL := "res://source/CS PHISYIC MODEL.fbx"
const CANONICAL_PS1_MODEL := "res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
const ANIMATION_STUDIO := "res://animation_library_lab.tscn"

var model_path_edit: LineEdit
var result_view: RichTextLabel
var status_label: Label
var approve_button: Button
var file_dialog: FileDialog
var preview_viewport: SubViewport
var preview_stage: Node3D
var preview_camera: Camera3D
var preview_model: Node3D
var canonical_reference: Node3D
var reference_toggle: CheckButton
var current_report: Dictionary = {}
var preview_normalization: Dictionary = {}
var reference_normalization: Dictionary = {}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	call_deferred("_validate_current")


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("0d1219")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var split := HSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.split_offset = 440
	add_child(split)

	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 430.0
	split.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 22)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "OPERATOR IMPORT STUDIO"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("8bc5ae"))
	column.add_child(title)
	var purpose := Label.new()
	purpose.text = "Import → Validate → Approve for canonical conversion"
	purpose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	purpose.add_theme_color_override("font_color", Color("aab4c4"))
	column.add_child(purpose)
	column.add_child(HSeparator.new())

	var path_row := HBoxContainer.new()
	column.add_child(path_row)
	model_path_edit = LineEdit.new()
	model_path_edit.name = "OperatorModelPath"
	model_path_edit.text = DEFAULT_MODEL
	model_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_path_edit.text_submitted.connect(func(_text: String) -> void: _validate_current())
	path_row.add_child(model_path_edit)
	var browse := Button.new()
	browse.text = "Browse"
	browse.pressed.connect(_show_file_dialog)
	path_row.add_child(browse)

	var action_row := HBoxContainer.new()
	column.add_child(action_row)
	var validate_button := Button.new()
	validate_button.text = "VALIDATE"
	validate_button.pressed.connect(_validate_current)
	action_row.add_child(validate_button)
	approve_button = Button.new()
	approve_button.text = "APPROVE PROFILE"
	approve_button.disabled = true
	approve_button.pressed.connect(_approve_current)
	action_row.add_child(approve_button)
	reference_toggle = CheckButton.new()
	reference_toggle.text = "PS1 RIG OVERLAY"
	reference_toggle.tooltip_text = "Show the canonical PS1 operator as a transparent alignment reference."
	reference_toggle.toggled.connect(_set_reference_visible)
	column.add_child(reference_toggle)

	result_view = RichTextLabel.new()
	result_view.name = "OperatorImportResults"
	result_view.bbcode_enabled = true
	result_view.fit_content = false
	result_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result_view.custom_minimum_size.y = 380.0
	column.add_child(result_view)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("7f8b9c"))
	column.add_child(status_label)
	var nav_row := HBoxContainer.new()
	column.add_child(nav_row)
	var animation_button := Button.new()
	animation_button.text = "OPEN ANIMATION STUDIO"
	animation_button.pressed.connect(_open_animation_studio)
	nav_row.add_child(animation_button)
	var home_button := Button.new()
	home_button.text = "STUDIO HOME"
	home_button.pressed.connect(_open_home)
	nav_row.add_child(home_button)

	_build_preview(split)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.fbx, *.glb, *.gltf ; Character models"])
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)


func _build_preview(parent: Control) -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(container)
	preview_viewport = SubViewport.new()
	preview_viewport.own_world_3d = true
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(preview_viewport)
	preview_stage = Node3D.new()
	preview_viewport.add_child(preview_stage)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("536174")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d9e5ef")
	environment.ambient_light_energy = 0.75
	environment_node.environment = environment
	preview_stage.add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	light.shadow_enabled = true
	preview_stage.add_child(light)
	preview_camera = Camera3D.new()
	preview_camera.current = true
	preview_stage.add_child(preview_camera)


func _validate_current() -> void:
	var path := model_path_edit.text.strip_edges()
	current_report = Validator.validate(path)
	approve_button.disabled = not bool(current_report.get("compatible", false))
	_load_preview(path)
	_render_report()


func _render_report() -> void:
	var compatible := bool(current_report.get("compatible", false))
	var color := "7df0ad" if compatible else "ff7c7c"
	var state := "PASS — READY FOR CONVERSION" if compatible else "BLOCKED"
	var lines: Array[String] = [
		"[color=#%s][b]%s[/b][/color]" % [color, state],
		"",
		"Skeleton: %s (%d bones)" % [
			String(current_report.get("skeleton_name", "None")),
			int(current_report.get("bone_count", 0)),
		],
		"Core roles: %d / %d" % [
			(current_report.get("bone_map", {}) as Dictionary).size(),
			Validator.REQUIRED_BONE_ROLES.size(),
		],
		"Meshes: %d total • %d skinned" % [
			int(current_report.get("mesh_count", 0)),
			int(current_report.get("skinned_mesh_count", 0)),
		],
		"Material slots: %d" % (current_report.get("material_slots", []) as Array).size(),
		"Embedded clips: %d" % int(current_report.get("animation_count", 0)),
		"Conversion: %s" % (
			"Bone-map bake required"
			if bool(current_report.get("requires_canonical_conversion", true))
			else "Already uses the canonical skeleton"
		),
	]
	var normalization: Dictionary = current_report.get("normalization", {})
	if bool(normalization.get("ok", false)):
		lines.append("Normalized rig: %.2f m • scale ×%.5f • yaw %.1f°" % [
			float(normalization.get("target_rig_height", 0.0)),
			float(normalization.get("scale_factor", 1.0)),
			float(normalization.get("yaw_degrees", 0.0)),
		])
	for error: String in current_report.get("errors", []):
		lines.append("[color=#ff7c7c]ERROR: %s[/color]" % error)
	for warning: String in current_report.get("warnings", []):
		lines.append("[color=#f2cf6a]CHECK: %s[/color]" % warning)
	lines.append("")
	lines.append("[b]Mapped operator roles[/b]")
	var bone_map: Dictionary = current_report.get("bone_map", {})
	for role in Validator.REQUIRED_BONE_ROLES:
		lines.append("%s → %s" % [role, String(bone_map.get(role, "MISSING"))])
	result_view.text = "\n".join(lines)
	status_label.text = "Validation does not change the live operator."


func _load_preview(path: String) -> void:
	if preview_model != null:
		preview_model.queue_free()
		preview_model = null
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	preview_model = packed.instantiate() as Node3D
	if preview_model == null:
		return
	preview_normalization = Normalizer.apply(
		preview_model,
		current_report.get("bone_map", {}) as Dictionary
	)
	preview_stage.add_child(preview_model)
	_frame_preview_camera()
	if reference_toggle.button_pressed:
		_build_canonical_reference()


func _set_reference_visible(enabled: bool) -> void:
	if enabled:
		_build_canonical_reference()
	elif canonical_reference != null:
		canonical_reference.queue_free()
		canonical_reference = null


func _build_canonical_reference() -> void:
	if canonical_reference != null:
		canonical_reference.queue_free()
		canonical_reference = null
	if preview_model == null or not ResourceLoader.exists(CANONICAL_PS1_MODEL):
		return
	var packed := load(CANONICAL_PS1_MODEL) as PackedScene
	if packed == null:
		return
	canonical_reference = packed.instantiate() as Node3D
	if canonical_reference == null:
		return
	var reference_report := Validator.validate(CANONICAL_PS1_MODEL)
	reference_normalization = Normalizer.apply(
		canonical_reference,
		reference_report.get("bone_map", {}) as Dictionary
	)
	preview_stage.add_child(canonical_reference)
	_apply_reference_material(canonical_reference)


func _frame_preview_camera() -> void:
	if preview_model == null:
		return
	var bounds := _model_bounds(preview_model)
	var height := maxf(bounds.size.y, 0.5)
	var extent := maxf(height, maxf(bounds.size.x, bounds.size.z))
	var center := bounds.get_center()
	preview_camera.position = center + Vector3(extent * 0.72, height * 0.18, extent * 1.45)
	preview_camera.look_at_from_position(preview_camera.position, center)


func _model_bounds(model: Node3D) -> AABB:
	return Normalizer.model_bounds(model)


func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		result.append_array(_mesh_instances(child))
	return result


func _apply_reference_material(node: Node) -> void:
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.25, 1.0, 0.72, 0.24)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = false
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_apply_reference_material(child)


func _approve_current() -> void:
	var profile := VisualProfile.from_validation(model_path_edit.text.strip_edges(), current_report)
	var result := VisualProfile.save(profile)
	status_label.text = (
		"Approved profile saved: %s. The live operator remains unchanged until canonical conversion." % result.path
		if bool(result.get("ok", false))
		else "Approval failed: %s" % String(result.get("error", "unknown error"))
	)


func _show_file_dialog() -> void:
	file_dialog.popup_centered_ratio(0.75)


func _on_file_selected(path: String) -> void:
	model_path_edit.text = path
	_validate_current()


func _open_animation_studio() -> void:
	var navigation := get_node_or_null("/root/StudioNavigation")
	if navigation != null and bool(navigation.get("active")):
		navigation.call("open_scene", ANIMATION_STUDIO)
	else:
		get_tree().change_scene_to_file(ANIMATION_STUDIO)


func _open_home() -> void:
	var navigation := get_node_or_null("/root/StudioNavigation")
	if navigation != null and bool(navigation.get("active")):
		navigation.call("open_home")
	else:
		get_tree().change_scene_to_file("res://game_launcher.tscn")
