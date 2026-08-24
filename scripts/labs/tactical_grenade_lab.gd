class_name SocomTacticalGrenadeLab
extends Node3D

const Smoke := preload("res://scripts/tactical/smoke_grenade.gd")
const Flash := preload("res://scripts/tactical/flashbang_grenade.gd")
const Frag := preload("res://scripts/tactical/frag_grenade.gd")
const Thrower := preload("res://scripts/tactical/tactical_grenade_thrower.gd")
const ScreenEffects := preload("res://scripts/tactical/tactical_screen_effects.gd")
const GrenadeProfile := preload("res://scripts/tactical/tactical_grenade_profile.gd")
const AnimationProfile := preload("res://scripts/player/operator_animation_profile.gd")
const AssetRuntime := preload("res://scripts/player/operator_asset_runtime.gd")
const PREVIEW_CAMERA_OFFSET := Vector3(3.8, 2.4, 5.6)

var camera: Camera3D
var thrower: TacticalGrenadeThrower
var selected_type := 0
var underhand := false
var selected_surface := "concrete"
var status: Label
var test_surface: StaticBody3D
var test_surface_material: StandardMaterial3D
var tuning_profile: Dictionary = {}
var operator_asset_runtime
var operator_model: Node3D
var operator_skeleton: Skeleton3D
var operator_animation_player: AnimationPlayer
var active_preview_grenade: TacticalGrenadeBase
var preview_focus := Vector3(0.0, 1.0, 2.5)
var preview_throw_in_progress := false
var preview_camera_follow_enabled := true


func _ready() -> void:
	tuning_profile = GrenadeProfile.load_profile()
	_build_arena()
	_build_ui()
	thrower = Thrower.new()
	thrower.configure_profile(tuning_profile)
	add_child(thrower)
	var effects := ScreenEffects.new()
	add_child(effects)
	effects.bind_camera(camera)


func _process(delta: float) -> void:
	if camera == null or not preview_camera_follow_enabled:
		return
	if active_preview_grenade != null and is_instance_valid(active_preview_grenade):
		preview_focus = active_preview_grenade.global_position + Vector3.UP * 0.35
	var desired_position := preview_focus + PREVIEW_CAMERA_OFFSET
	camera.global_position = camera.global_position.lerp(
		desired_position,
		1.0 - exp(-3.8 * delta)
	)
	camera.look_at(preview_focus + Vector3.UP * 0.35, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1: selected_type = 0
		elif event.keycode == KEY_2: selected_type = 1
		elif event.keycode == KEY_3: selected_type = 2
		elif event.keycode == KEY_U: underhand = not underhand
		elif event.keycode == KEY_C: _select_surface("concrete", Color("8993a1"))
		elif event.keycode == KEY_M: _select_surface("metal", Color("7da8b8"))
		elif event.keycode == KEY_S: _select_surface("sand", Color("c7aa69"))
		elif event.keycode == KEY_W: _select_surface("wood", Color("8e684b"))
		elif event.keycode == KEY_R: _select_surface("carpet", Color("765b78"))
		elif event.keycode == KEY_SPACE: _throw_grenade()
		_update_status()


func _throw_grenade() -> void:
	if preview_throw_in_progress:
		return
	preview_throw_in_progress = true
	_play_operator_throw_animation()
	status.text = "%s • THROW ANIMATION • RELEASE…" % ["SMOKE", "FLASH", "FRAG"][selected_type]
	await get_tree().create_timer(0.38).timeout
	var grenade: TacticalGrenadeBase
	if selected_type == 1:
		grenade = Flash.new()
	elif selected_type == 2:
		grenade = Frag.new()
	else:
		grenade = Smoke.new()
	grenade.configure_profile(tuning_profile)
	add_child(grenade)
	grenade.global_position = _operator_throw_origin()
	active_preview_grenade = grenade
	grenade.detonated.connect(_on_preview_grenade_detonated.bind(selected_type))
	var mode := Thrower.ThrowMode.UNDERHAND if underhand else Thrower.ThrowMode.OVERHAND
	grenade.launch(thrower.calculate_launch_velocity(Vector3(0.0, 0.0, -1.0), Vector3.UP, mode))
	preview_throw_in_progress = false
	_update_status()


func _build_arena() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("1b202a")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d7e2f0")
	settings.ambient_light_energy = 1.15
	settings.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.environment = settings
	add_child(environment)
	var key_light := DirectionalLight3D.new()
	key_light.name = "PreviewKeyLight"
	key_light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	key_light.light_color = Color("fff0d6")
	key_light.light_energy = 1.35
	key_light.shadow_enabled = true
	add_child(key_light)
	var fill_light := OmniLight3D.new()
	fill_light.name = "PreviewFillLight"
	fill_light.position = Vector3(-4.0, 4.5, 5.0)
	fill_light.light_color = Color("8bc7ff")
	fill_light.light_energy = 4.0
	fill_light.omni_range = 18.0
	add_child(fill_light)
	var floor := StaticBody3D.new()
	floor.set_meta(&"surface_audio", "concrete")
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80, 0.2, 80)
	collision.shape = shape
	floor.add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("4b5563")
	floor_material.roughness = 0.92
	mesh.material = floor_material
	mesh_instance.mesh = mesh
	floor.add_child(mesh_instance)
	add_child(floor)
	test_surface = StaticBody3D.new()
	test_surface.name = "SurfaceTestPad"
	test_surface.position = Vector3(0, 0.12, -2.8)
	test_surface.set_meta(&"surface_audio", selected_surface)
	var pad_collision := CollisionShape3D.new()
	var pad_shape := BoxShape3D.new()
	pad_shape.size = Vector3(6.0, 0.12, 5.0)
	pad_collision.shape = pad_shape
	test_surface.add_child(pad_collision)
	var pad_mesh := MeshInstance3D.new()
	var pad_box := BoxMesh.new()
	pad_box.size = pad_shape.size
	test_surface_material = StandardMaterial3D.new()
	test_surface_material.albedo_color = Color("8993a1")
	pad_box.material = test_surface_material
	pad_mesh.mesh = pad_box
	test_surface.add_child(pad_mesh)
	add_child(test_surface)
	_build_operator_preview()
	camera = Camera3D.new()
	camera.name = "GrenadePreviewCamera"
	camera.current = true
	camera.fov = 60.0
	camera.position = preview_focus + PREVIEW_CAMERA_OFFSET
	add_child(camera)
	camera.look_at(preview_focus + Vector3.UP * 0.35, Vector3.UP)


func _build_operator_preview() -> void:
	var animation_profile := AnimationProfile.new()
	animation_profile.load_project_map()
	operator_asset_runtime = AssetRuntime.new()
	var runtime: Dictionary = operator_asset_runtime.build(
		self,
		animation_profile,
		62.0,
		Vector3(-0.02, 0.08, 0.05),
		Vector3(-90.0, 180.0, 0.0)
	)
	operator_model = runtime.get("model_root") as Node3D
	operator_skeleton = runtime.get("skeleton") as Skeleton3D
	operator_animation_player = runtime.get("animation_player") as AnimationPlayer
	if operator_model != null:
		operator_model.position = Vector3(0.0, 0.1, 3.8)
	if operator_animation_player != null and operator_animation_player.has_animation(&"aim_idle"):
		operator_animation_player.play(&"aim_idle")


func _play_operator_throw_animation() -> void:
	if operator_animation_player == null:
		return
	# Standing uses the complete authored toss. Runtime anchors its hips so the
	# preview remains stationary instead of inheriting imported world movement.
	var clip := &"grenade_toss"
	if operator_animation_player.has_animation(clip):
		operator_animation_player.play(clip, 0.08)
		return
	if operator_animation_player.has_animation(&"aim_idle"):
		operator_animation_player.play(&"aim_idle")


func _operator_throw_origin() -> Vector3:
	if operator_skeleton != null:
		var hand_index := operator_skeleton.find_bone("mixamorig_RightHand")
		if hand_index >= 0:
			return (
				operator_skeleton.global_transform
				* operator_skeleton.get_bone_global_pose(hand_index)
			).origin
	if operator_model != null:
		return operator_model.global_position + Vector3(0.25, 1.35, -0.25)
	return Vector3(0.25, 1.35, 3.5)


func _on_preview_grenade_detonated(position: Vector3, grenade_type: int) -> void:
	preview_focus = position + Vector3.UP * (1.25 if grenade_type == 0 else 0.45)
	active_preview_grenade = null
	status.text = "%s DETONATED • CAMERA HOLDING EFFECT" % ["SMOKE", "FLASH", "FRAG"][grenade_type]
	if operator_animation_player != null and operator_animation_player.has_animation(&"aim_idle"):
		operator_animation_player.play(&"aim_idle", 0.18)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(22, 20)
	label.text = (
		"TACTICAL GRENADE LAB\n"
		+ "1 Smoke • 2 Flash • 3 Frag • U throw mode • Space animated throw\n"
		+ "Surface: C concrete • M metal • S sand • W wood • R carpet"
	)
	label.add_theme_font_size_override("font_size", 20)
	layer.add_child(label)
	status = Label.new()
	status.position = Vector2(22, 108)
	status.text = "SMOKE • OVERHAND • CONCRETE"
	layer.add_child(status)
	_build_tuning_panel(layer)


func _build_tuning_panel(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.name = "ThrowableTuningPanel"
	panel.position = Vector2(22, 140)
	panel.size = Vector2(500, 550)
	layer.add_child(panel)
	var layout := VBoxContainer.new()
	panel.add_child(layout)
	var title := Label.new()
	title.text = "THROWABLE TUNING — LIVE PREVIEW"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("55e7ff"))
	layout.add_child(title)
	var help := Label.new()
	help.text = "Adjust a value, then throw to preview it. Save applies one shared profile to the playable build and multiplayer authority."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(help)

	var tabs := TabContainer.new()
	tabs.name = "ThrowableTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(tabs)
	_build_smoke_tab(tabs)
	_build_flash_tab(tabs)
	_build_frag_tab(tabs)
	_build_throw_tab(tabs)
	tabs.tab_changed.connect(_on_tuning_tab_changed)

	var save_button := Button.new()
	save_button.name = "SaveThrowableProfile"
	save_button.text = "SAVE ALL THROWABLES + APPLY TO GAME"
	save_button.add_theme_color_override("font_color", Color("9cffad"))
	save_button.pressed.connect(_save_tuning_profile)
	layout.add_child(save_button)


func _build_smoke_tab(tabs: TabContainer) -> void:
	var box := _new_tuning_tab(tabs, "Smoke")
	_add_tuning_slider(box, "smoke", "maximum_radius", "Cloud radius (m)", 2.0, 12.0, 0.1)
	_add_tuning_slider(box, "smoke", "visual_opacity", "Puff opacity", 0.05, 0.75, 0.01)
	_add_tuning_slider(box, "smoke", "particle_amount", "Particle count", 48.0, 800.0, 1.0, true)
	_add_tuning_slider(box, "smoke", "particle_lifetime", "Particle lifetime (s)", 1.0, 12.0, 0.1)
	_add_tuning_slider(box, "smoke", "emission_radius", "Emission radius (m)", 0.5, 8.0, 0.1)
	_add_tuning_slider(box, "smoke", "puff_size_min", "Minimum puff size", 0.4, 8.0, 0.1)
	_add_tuning_slider(box, "smoke", "puff_size_max", "Maximum puff size", 0.8, 12.0, 0.1)
	_add_tuning_slider(box, "smoke", "sprout_seconds", "Expansion time (s)", 0.25, 5.0, 0.05)
	_add_tuning_slider(box, "smoke", "dense_seconds", "Dense duration (s)", 2.0, 40.0, 0.5)
	_add_tuning_slider(box, "smoke", "dissipate_seconds", "Fade duration (s)", 1.0, 20.0, 0.25)


func _build_flash_tab(tabs: TabContainer) -> void:
	var box := _new_tuning_tab(tabs, "Flash")
	_add_tuning_slider(box, "flash", "effective_radius", "Effective radius (m)", 3.0, 35.0, 0.5)
	_add_tuning_slider(box, "flash", "intensity_multiplier", "Screen intensity", 0.10, 2.0, 0.05)
	var note := Label.new()
	note.text = "Facing direction and wall visibility still reduce exposure. These controls cannot flash through solid cover."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)


func _build_frag_tab(tabs: TabContainer) -> void:
	var box := _new_tuning_tab(tabs, "Frag")
	_add_tuning_slider(box, "frag", "blast_radius", "Damage radius (m)", 2.0, 15.0, 0.25)
	_add_tuning_slider(box, "frag", "maximum_damage", "Maximum damage", 10.0, 300.0, 1.0)
	_add_tuning_slider(box, "frag", "impulse_strength", "Physics impulse", 0.0, 40.0, 0.5)
	_add_tuning_slider(box, "frag", "debris_count", "Visual debris count", 0.0, 40.0, 1.0, true)
	_add_tuning_slider(box, "frag", "blast_effect_seconds", "Radius smoke duration (s)", 0.25, 1.50, 0.05)
	_add_tuning_slider(box, "frag", "blast_smoke_particles", "Radius smoke particles", 24.0, 500.0, 1.0, true)
	_add_tuning_slider(box, "frag", "blast_smoke_opacity", "Radius smoke opacity", 0.04, 0.55, 0.01)
	var note := Label.new()
	note.text = "The smoke boundary uses Damage radius exactly. Puffs stay inside it. Damage falls with distance, and solid walls block it."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)


func _on_tuning_tab_changed(tab_index: int) -> void:
	if tab_index >= 0 and tab_index <= 2:
		selected_type = tab_index
		_update_status()


func _build_throw_tab(tabs: TabContainer) -> void:
	var box := _new_tuning_tab(tabs, "Throw + Fuse")
	_add_tuning_slider(box, "common", "fuse_seconds", "Fuse time (s)", 1.0, 8.0, 0.1)
	_add_tuning_slider(box, "common", "bounce_restitution", "Bounce", 0.0, 0.95, 0.01)
	_add_tuning_slider(box, "common", "mass_kg", "Grenade mass (kg)", 0.10, 2.0, 0.05)
	_add_tuning_slider(box, "throw", "overhand_speed", "Full overhand speed", 4.0, 30.0, 0.25)
	_add_tuning_slider(box, "throw", "underhand_speed", "Full underhand speed", 2.0, 16.0, 0.25)
	_add_tuning_slider(box, "throw", "minimum_overhand_speed", "Minimum overhand speed", 2.0, 20.0, 0.25)
	_add_tuning_slider(box, "throw", "minimum_underhand_speed", "Minimum underhand speed", 1.0, 12.0, 0.25)
	_add_tuning_slider(box, "throw", "overhand_lift", "Overhand arc lift", 0.0, 0.80, 0.01)
	_add_tuning_slider(box, "throw", "underhand_lift", "Underhand arc lift", 0.0, 0.50, 0.01)
	_add_tuning_slider(box, "throw", "full_throw_charge_seconds", "Time to full power (s)", 0.10, 2.0, 0.05)
	_add_tuning_slider(box, "throw", "maximum_hold_seconds", "Automatic release time (s)", 0.25, 3.0, 0.05)
	_add_tuning_slider(box, "throw", "full_throw_playback_speed", "Full throw animation speed", 0.50, 2.0, 0.05)
	_add_tuning_slider(box, "throw", "quick_throw_playback_speed", "Quick throw animation speed", 0.75, 3.0, 0.05)
	_add_tuning_slider(box, "throw", "recovery_blend_seconds", "Movement recovery blend (s)", 0.04, 0.30, 0.01)


func _new_tuning_tab(tabs: TabContainer, tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func _add_tuning_slider(
	parent: VBoxContainer,
	section_name: String,
	key: String,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	integer_value: bool = false
) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 190.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "%s_%s" % [section_name, key]
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var section: Dictionary = tuning_profile.get(section_name, {})
	slider.value = float(section.get(key, minimum))
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 58.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = _format_tuning_value(slider.value, integer_value)
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float):
		_set_tuning_value(section_name, key, value, integer_value)
		value_label.text = _format_tuning_value(value, integer_value)
	)


func _set_tuning_value(
	section_name: String,
	key: String,
	value: float,
	integer_value: bool
) -> void:
	var section: Dictionary = (tuning_profile.get(section_name, {}) as Dictionary).duplicate(true)
	section[key] = int(round(value)) if integer_value else value
	tuning_profile[section_name] = section
	if thrower != null:
		thrower.configure_profile(tuning_profile)


func _format_tuning_value(value: float, integer_value: bool) -> String:
	return "%d" % int(round(value)) if integer_value else "%.2f" % value


func _save_tuning_profile() -> void:
	tuning_profile = GrenadeProfile.normalize(tuning_profile)
	if GrenadeProfile.save_profile(tuning_profile):
		if thrower != null:
			thrower.configure_profile(tuning_profile)
		status.text = "SAVED • ALL THROWABLES NOW FEED THE PLAYABLE BUILD"
		status.add_theme_color_override("font_color", Color("9cffad"))
	else:
		status.text = "SAVE FAILED • THROWABLE PROFILE WAS NOT CHANGED"
		status.add_theme_color_override("font_color", Color("ff6868"))


func _select_surface(surface_name: String, color: Color) -> void:
	selected_surface = surface_name
	if test_surface != null:
		test_surface.set_meta(&"surface_audio", selected_surface)
	if test_surface_material != null:
		test_surface_material.albedo_color = color


func _update_status() -> void:
	if status == null:
		return
	status.text = "%s • %s • %s" % [
		["SMOKE", "FLASH", "FRAG"][selected_type],
		"UNDERHAND" if underhand else "OVERHAND",
		selected_surface.to_upper(),
	]
