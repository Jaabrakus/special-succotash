extends Control

const ComposureScript := preload("res://scripts/weapons/operator_composure.gd")
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const TargetDummyScript := preload("res://scripts/combat/lab_leak_target_dummy.gd")
const HurtboxProfile := preload("res://scripts/combat/socom_hurtbox_profile.gd")

const WEAPONS := {
	"Assault Rifle": {
		"rpm": 650.0,
		"shot_stress": 0.085,
		"opening_stress_multiplier": 0.28,
		"recovery_speed": 1.45,
		"bounce_duration": 0.070,
		"bounce_strength": 1.0,
		"damage": 34.0,
		"graze_scale": 0.38,
	},
	"Submachine Gun": {
		"rpm": 850.0,
		"shot_stress": 0.055,
		"opening_stress_multiplier": 0.32,
		"recovery_speed": 1.72,
		"bounce_duration": 0.058,
		"bounce_strength": 0.72,
		"damage": 24.0,
		"graze_scale": 0.42,
	},
	"Battle Rifle": {
		"rpm": 480.0,
		"shot_stress": 0.125,
		"opening_stress_multiplier": 0.20,
		"recovery_speed": 1.18,
		"bounce_duration": 0.085,
		"bounce_strength": 1.28,
		"damage": 48.0,
		"graze_scale": 0.34,
	},
	"Light Machine Gun": {
		"rpm": 720.0,
		"shot_stress": 0.075,
		"opening_stress_multiplier": 0.34,
		"recovery_speed": 1.02,
		"bounce_duration": 0.075,
		"bounce_strength": 1.10,
		"damage": 31.0,
		"graze_scale": 0.40,
	},
}

var composure := ComposureScript.new()
var movement_amount: float = 0.0
var turning_amount: float = 0.0
var stance: OperatorComposure.Stance = OperatorComposure.Stance.STANDING
var trigger_held: bool = false
var fire_clock: float = 0.0
var fire_interval: float = 60.0 / 650.0
var shots_fired: int = 0
var burst_shot_count: int = 0
var time_since_shot: float = 99.0
var active_weapon: Dictionary = {}
var shot_samples: Array[Dictionary] = []
var precision_hits: int = 0
var graze_hits: int = 0
var misses: int = 0
var total_damage: float = 0.0
var state_label: Label
var instruction_label: Label
var save_notice: Label
var hurtbox_preview_dummy: Node3D
var hurtbox_preview_camera: Camera3D
var shared_hurtbox_scales: Dictionary = HurtboxProfile.load_scales()


func _ready() -> void:
	set_process(true)
	_build_controls()
	_build_hurtbox_preview()
	_select_weapon(0)
	queue_redraw()


func _process(delta: float) -> void:
	time_since_shot += delta
	if not trigger_held and time_since_shot > maxf(fire_interval * 1.55, 0.14):
		burst_shot_count = 0
	if Input.is_key_pressed(KEY_SPACE):
		trigger_held = true
	elif not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		trigger_held = false

	if trigger_held:
		fire_clock -= delta
		while fire_clock <= 0.0:
			_fire_once()
			fire_clock += fire_interval
	else:
		fire_clock = 0.0

	composure.advance(delta, movement_amount, turning_amount, stance)
	if hurtbox_preview_dummy != null and hurtbox_preview_dummy.has_method("set_precision_core_debug"):
		hurtbox_preview_dummy.call(
			"set_precision_core_debug",
			true,
			composure.get_precision_core_scale()
		)
	_update_readout()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("10151d"))
	draw_rect(Rect2(330.0, 72.0, size.x - 360.0, size.y - 104.0), Color("171e28"), true)
	_draw_reticle(Vector2(size.x * 0.47, size.y * 0.43))
	_draw_target_legend(Vector2(size.x * 0.78, size.y * 0.42))
	_draw_timing_strip()


func _draw_reticle(aim_center: Vector2) -> void:
	var bloom := composure.get_visual_bloom()
	var bounce := composure.get_shot_bounce()
	var visible_center := aim_center + Vector2(0.0, -13.0 * bounce)
	var gap := lerpf(11.0, 62.0, bloom) + 3.0 * bounce
	var inner_radius := lerpf(8.0, 31.0, bloom)
	var color := Color("d9f22c")
	var shadow := Color(0.0, 0.0, 0.0, 0.82)

	draw_string(ThemeDB.fallback_font, aim_center + Vector2(-112, -142), "RETICLE / COMPOSURE", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("77f29a"))
	draw_circle(aim_center, 2.5, Color(0.25, 0.7, 1.0, 0.30))
	draw_arc(visible_center, inner_radius, 0.0, TAU, 48, Color(0.75, 0.9, 1.0, 0.24), 2.0, true)
	draw_circle(visible_center, 3.0, shadow)
	draw_circle(visible_center, 1.8, color)

	var length := 11.0
	var thickness := 2.5
	var directions := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	for raw_direction in directions:
		var direction: Vector2 = raw_direction
		var start: Vector2 = visible_center + direction * gap
		var finish: Vector2 = visible_center + direction * (gap + length)
		draw_line(start, finish, shadow, thickness + 2.0)
		draw_line(start, finish, color, thickness)

	draw_string(ThemeDB.fallback_font, aim_center + Vector2(-118, 142), "blue point = authoritative aim", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.65, 0.75, 0.86))
	draw_string(ThemeDB.fallback_font, aim_center + Vector2(-118, 162), "yellow = fast shot pop + slow bloom", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.65, 0.75, 0.86))


func _draw_target_legend(center: Vector2) -> void:
	draw_string(ThemeDB.fallback_font, center + Vector2(-132, -176), "LIVE T-POSE HURTBOX RIG", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("77f29a"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-132, 190), "colored shell = fixed anatomical hurtbox", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.65, 0.75, 0.86))
	draw_string(ThemeDB.fallback_font, center + Vector2(-132, 210), "cyan = shooter-specific precision core", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.65, 0.75, 0.86))
	draw_string(ThemeDB.fallback_font, center + Vector2(-132, 230), "edge contact = graze • center crossing = full", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.65, 0.75, 0.86))


func _build_hurtbox_preview() -> void:
	var container := SubViewportContainer.new()
	container.name = "LiveHurtboxPreview"
	container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	container.anchor_left = 0.60
	container.anchor_top = 0.16
	container.anchor_right = 0.97
	container.anchor_bottom = 0.77
	container.offset_left = 0.0
	container.offset_top = 0.0
	container.offset_right = 0.0
	container.offset_bottom = 0.0
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	var viewport := SubViewport.new()
	viewport.name = "HurtboxViewport"
	viewport.transparent_bg = false
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	var environment := WorldEnvironment.new()
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color("171e28")
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color(0.72, 0.78, 0.88)
	environment_resource.ambient_light_energy = 1.25
	environment.environment = environment_resource
	viewport.add_child(environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	light.light_energy = 1.4
	viewport.add_child(light)

	hurtbox_preview_camera = Camera3D.new()
	hurtbox_preview_camera.position = Vector3(0.0, 1.05, 3.6)
	hurtbox_preview_camera.fov = 42.0
	hurtbox_preview_camera.current = true
	viewport.add_child(hurtbox_preview_camera)
	hurtbox_preview_camera.look_at(Vector3(0.0, 1.02, 0.0), Vector3.UP)

	hurtbox_preview_dummy = TargetDummyScript.new() as Node3D
	hurtbox_preview_dummy.name = "ComposureTposeTarget"
	viewport.add_child(hurtbox_preview_dummy)
	call_deferred("_finish_hurtbox_preview")


func _finish_hurtbox_preview() -> void:
	if hurtbox_preview_dummy == null:
		return
	if hurtbox_preview_dummy.has_method("set_hurtbox_debug_visible"):
		hurtbox_preview_dummy.call("set_hurtbox_debug_visible", true)
	if hurtbox_preview_dummy.has_method("apply_hurtbox_tuning"):
		hurtbox_preview_dummy.call("apply_hurtbox_tuning", shared_hurtbox_scales)
	if hurtbox_preview_dummy.has_method("set_precision_core_debug"):
		hurtbox_preview_dummy.call(
			"set_precision_core_debug",
			true,
			composure.get_precision_core_scale()
		)
	var health_label := hurtbox_preview_dummy.get_node_or_null("HealthLabel")
	if health_label is Label3D:
		(health_label as Label3D).visible = false


func _draw_timing_strip() -> void:
	var area := Rect2(360.0, size.y - 116.0, size.x - 410.0, 58.0)
	draw_rect(area, Color("0b0f15"), true)
	var bloom_width := area.size.x * composure.get_visual_bloom()
	var core_width := area.size.x * composure.get_precision_core_scale()
	draw_rect(Rect2(area.position + Vector2(0, 8), Vector2(bloom_width, 14)), Color("d9f22c"), true)
	draw_rect(Rect2(area.position + Vector2(0, 34), Vector2(core_width, 14)), Color("26dfe7"), true)
	draw_string(ThemeDB.fallback_font, area.position + Vector2(8, 20), "BLOOM", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
	draw_string(ThemeDB.fallback_font, area.position + Vector2(8, 46), "PRECISION CORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)


func _build_controls() -> void:
	var title := Label.new()
	title.position = Vector2(24, 18)
	title.text = "SOCOM-141 AUTHORITATIVE COMPOSURE & HURTBOX LAB"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("77f29a"))
	add_child(title)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(24, 82)
	scroll.anchor_bottom = 1.0
	scroll.offset_right = 306.0
	scroll.offset_bottom = -34.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size.x = 270.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 10)
	scroll.add_child(panel)

	var weapon_label := Label.new()
	weapon_label.text = "WEAPON PROFILE"
	panel.add_child(weapon_label)
	var weapon_picker := OptionButton.new()
	for weapon_name in WEAPONS.keys():
		weapon_picker.add_item(weapon_name)
	weapon_picker.item_selected.connect(_select_weapon)
	panel.add_child(weapon_picker)

	_add_slider(panel, "MOVEMENT", 0.0, 1.0, 0.0, func(value: float): movement_amount = value)
	_add_slider(panel, "TURNING", 0.0, 1.0, 0.0, func(value: float): turning_amount = value)
	_add_slider(panel, "STRESS PER SHOT", 0.0, 0.30, composure.shot_stress, func(value: float): composure.shot_stress = value)
	_add_slider(panel, "RECOVERY RATE", 0.20, 4.0, composure.recovery_speed, func(value: float): composure.recovery_speed = value)
	_add_slider(panel, "MINIMUM PRECISION CORE", 0.30, 1.0, composure.minimum_core_scale, func(value: float): composure.minimum_core_scale = value)
	_add_slider(panel, "GRAZE DAMAGE", 0.0, 1.0, 0.38, func(value: float): active_weapon["graze_scale"] = value)
	_add_slider(panel, "OUTER HITBOX SCALE", 0.45, 1.25, float(shared_hurtbox_scales["global"]), func(value: float): _set_shared_hurtbox_scale("global", value))
	_add_slider(panel, "HEAD HITBOX", 0.45, 1.25, float(shared_hurtbox_scales["head"]), func(value: float): _set_shared_hurtbox_scale("head", value))
	_add_slider(panel, "TORSO HITBOX", 0.45, 1.25, float(shared_hurtbox_scales["torso"]), func(value: float): _set_shared_hurtbox_scale("torso", value))
	_add_slider(panel, "ARM HITBOXES", 0.45, 1.25, float(shared_hurtbox_scales["arms"]), func(value: float): _set_shared_hurtbox_scale("arms", value))
	_add_slider(panel, "LEG HITBOXES", 0.45, 1.25, float(shared_hurtbox_scales["legs"]), func(value: float): _set_shared_hurtbox_scale("legs", value))

	var stance_label := Label.new()
	stance_label.text = "STANCE"
	panel.add_child(stance_label)
	var stance_picker := OptionButton.new()
	stance_picker.add_item("Standing")
	stance_picker.add_item("Crouched")
	stance_picker.add_item("Prone")
	stance_picker.item_selected.connect(func(index: int): stance = index as OperatorComposure.Stance)
	panel.add_child(stance_picker)

	var single := Button.new()
	single.text = "FIRE ONE SHOT"
	single.pressed.connect(_fire_once)
	panel.add_child(single)

	var automatic := Button.new()
	automatic.text = "HOLD FOR AUTOMATIC FIRE"
	automatic.button_down.connect(func(): trigger_held = true)
	automatic.button_up.connect(func(): trigger_held = false)
	panel.add_child(automatic)

	var reset_button := Button.new()
	reset_button.text = "RESET COMPOSURE"
	reset_button.pressed.connect(_reset_lab)
	panel.add_child(reset_button)

	var save_button := Button.new()
	save_button.text = "SAVE COMPOSURE TO EQUIPPED WEAPON"
	save_button.pressed.connect(_save_to_equipped_rig)
	panel.add_child(save_button)

	var save_hurtboxes_button := Button.new()
	save_hurtboxes_button.text = "SAVE SHARED HURTBOXES"
	save_hurtboxes_button.tooltip_text = (
		"Writes the one anatomical profile loaded by the playground and future network operators."
	)
	save_hurtboxes_button.pressed.connect(_save_shared_hurtboxes)
	panel.add_child(save_hurtboxes_button)

	var play_button := Button.new()
	play_button.text = "SAVE + PLAY CANONICAL PLAYGROUND"
	play_button.pressed.connect(_save_and_play)
	panel.add_child(play_button)

	save_notice = Label.new()
	save_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_notice.add_theme_color_override("font_color", Color("77f29a"))
	panel.add_child(save_notice)

	state_label = Label.new()
	state_label.custom_minimum_size = Vector2(275, 150)
	state_label.add_theme_font_size_override("font_size", 16)
	panel.add_child(state_label)

	instruction_label = Label.new()
	instruction_label.position = Vector2(360, 20)
	instruction_label.text = "SPACE or HOLD button: fire   •   Movement/Turning: simulate combat stress"
	instruction_label.add_theme_font_size_override("font_size", 16)
	instruction_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
	add_child(instruction_label)


func _add_slider(
	parent: VBoxContainer,
	label_text: String,
	minimum: float,
	maximum: float,
	value: float,
	callback: Callable
) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.01
	slider.value = value
	slider.custom_minimum_size = Vector2(270, 24)
	slider.value_changed.connect(callback)
	parent.add_child(slider)


func _select_weapon(index: int) -> void:
	var names := WEAPONS.keys()
	if index < 0 or index >= names.size():
		return
	var profile: Dictionary = WEAPONS[names[index]]
	active_weapon = profile
	composure.configure_weapon(profile)
	fire_interval = 60.0 / float(profile.get("rpm", 650.0))


func _set_shared_hurtbox_scale(key: String, value: float) -> void:
	shared_hurtbox_scales[key] = value
	if hurtbox_preview_dummy != null and hurtbox_preview_dummy.has_method("apply_hurtbox_tuning"):
		hurtbox_preview_dummy.call("apply_hurtbox_tuning", shared_hurtbox_scales)


func _fire_once() -> void:
	shots_fired += 1
	burst_shot_count += 1
	time_since_shot = 0.0
	var shot_core_scale := composure.get_precision_core_scale()
	var dispersion_multiplier := composure.get_shot_dispersion_multiplier(
		burst_shot_count,
		movement_amount,
		turning_amount
	)
	var opening_multiplier := float(active_weapon.get("opening_stress_multiplier", 0.30))
	var stress_multiplier := opening_multiplier if burst_shot_count <= 2 else 1.0
	# Reticle pop remains immediate on every shot. Only the slow accuracy stress
	# receives the opening-pair benefit.
	composure.notify_shot(1.0, stress_multiplier)
	_record_authoritative_shot(dispersion_multiplier, shot_core_scale)


func _reset_lab() -> void:
	composure.reset()
	shots_fired = 0
	burst_shot_count = 0
	time_since_shot = 99.0
	shot_samples.clear()
	precision_hits = 0
	graze_hits = 0
	misses = 0
	total_damage = 0.0


func _save_to_equipped_rig() -> bool:
	var config_path := WeaponContract.resolve_config_path()
	if config_path.is_empty() or not FileAccess.file_exists(config_path):
		save_notice.text = "No equipped Gunsmith rig was found. Save and equip a weapon first."
		return false
	var read_file := FileAccess.open(config_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(read_file.get_as_text()) if read_file else null
	if not parsed is Dictionary:
		save_notice.text = "The equipped weapon profile could not be read."
		return false
	var config: Dictionary = (parsed as Dictionary).duplicate(true)
	var profile := composure.export_profile()
	profile["opening_stress_multiplier"] = float(
		active_weapon.get("opening_stress_multiplier", 0.28)
	)
	profile["graze_damage_scale"] = float(active_weapon.get("graze_scale", 0.38))
	config["composure"] = profile
	var reticle: Dictionary = (
		(config.get("reticle", {}) as Dictionary).duplicate(true)
		if config.get("reticle", {}) is Dictionary
		else {}
	)
	reticle["shot_bounce_duration"] = composure.shot_bounce_duration
	config["reticle"] = reticle
	var write_file := FileAccess.open(config_path, FileAccess.WRITE)
	if write_file == null:
		save_notice.text = "Could not write the equipped weapon profile."
		return false
	write_file.store_string(JSON.stringify(config, "  "))
	write_file.close()
	save_notice.text = "Saved to %s. This exact profile now loads in main.tscn." % config_path.get_file()
	return true


func _save_shared_hurtboxes() -> bool:
	if not HurtboxProfile.save_scales(shared_hurtbox_scales):
		save_notice.text = "Could not save the canonical anatomical hurtbox profile."
		return false
	save_notice.text = (
		"Shared hurtboxes saved. New playground targets and network operators "
		+ "will load these exact outer dimensions."
	)
	return true


func _save_and_play() -> void:
	if not _save_shared_hurtboxes():
		return
	if not _save_to_equipped_rig():
		return
	call_deferred("_open_canonical_playground")


func _open_canonical_playground() -> void:
	var error := get_tree().change_scene_to_file("res://main.tscn")
	if error != OK:
		save_notice.text = "Could not open main.tscn (%s)." % error_string(error)


func _record_authoritative_shot(
	dispersion_multiplier: float,
	shot_core_scale: float
) -> void:
	# The lab uses the authoritative stress, never the breathing/display spring,
	# for deterministic dispersion and damage classification.
	var random := RandomNumberGenerator.new()
	random.seed = shots_fired * 7919 + 104729
	var angle := random.randf() * TAU
	var normalized_radius := sqrt(random.randf())
	var spread_radius := lerpf(11.0, 118.0, pow(composure.stress, 0.92))
	var target_center := Vector2(size.x * 0.78, size.y * 0.42)
	var position := (
		target_center
		+ Vector2(cos(angle), sin(angle))
		* normalized_radius
		* spread_radius
		* dispersion_multiplier
	)
	var anatomical_score := _body_distance_score(position, target_center)
	var core_scale := shot_core_scale
	var result := "MISS"
	var damage := 0.0
	if anatomical_score <= core_scale:
		result = "PRECISION"
		damage = float(active_weapon.get("damage", 34.0))
		precision_hits += 1
	elif anatomical_score <= 1.0:
		result = "GRAZE"
		damage = float(active_weapon.get("damage", 34.0)) * float(active_weapon.get("graze_scale", 0.38))
		graze_hits += 1
	else:
		misses += 1
	total_damage += damage
	shot_samples.push_back({
		"position": position,
		"result": result,
		"damage": damage,
		"stress": composure.stress,
		"dispersion_multiplier": dispersion_multiplier,
	})
	if shot_samples.size() > 72:
		shot_samples.pop_front()


func _body_distance_score(point: Vector2, center: Vector2) -> float:
	var score := point.distance_to(center + Vector2(0, -91)) / 31.0
	var torso_delta := point - (center + Vector2(0, 11))
	score = minf(score, Vector2(torso_delta.x / 52.0, torso_delta.y / 66.0).length())
	for segment in [
		[center + Vector2(-45, -38), center + Vector2(-92, 35)],
		[center + Vector2(45, -38), center + Vector2(92, 35)],
		[center + Vector2(-25, 70), center + Vector2(-38, 152)],
		[center + Vector2(25, 70), center + Vector2(38, 152)],
	]:
		var start: Vector2 = segment[0]
		var finish: Vector2 = segment[1]
		var nearest := Geometry2D.get_closest_point_to_segment(point, start, finish)
		score = minf(score, point.distance_to(nearest) / 12.5)
	return score


func _update_readout() -> void:
	if state_label == null:
		return
	state_label.text = (
		"COMPOSURE        %5.1f%%\n"
		+ "AUTHORITATIVE STRESS %5.1f%%\n"
		+ "VISIBLE BLOOM    %5.1f%%\n"
		+ "PRECISION CORE   %5.1f%%\n"
		+ "SHOT POP         %5.1f%%\n"
		+ "SHOTS            %d\n"
		+ "FULL / GRAZE / MISS  %d / %d / %d\n"
		+ "SAMPLED DAMAGE   %6.1f"
	) % [
		composure.get_composure() * 100.0,
		composure.stress * 100.0,
		composure.get_visual_bloom() * 100.0,
		composure.get_precision_core_scale() * 100.0,
		composure.get_shot_bounce() * 100.0,
		shots_fired,
		precision_hits,
		graze_hits,
		misses,
		total_damage,
	]
