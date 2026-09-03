@tool
class_name StandaloneGunsLabSandbox
extends Node3D

## Standalone Guns & Weapon Calibration Lab
## Right-hand stats dock with RPM, damage, recoil, bloom cones, socket calibration, and target telemetry.

const WEAPONS_CONFIG_DIR := "res://standalone_labs/configs/"
const WEAPONS_SCENE_DIR := "res://standalone_labs/weapons/"

@export var selected_weapon_id: String = "m16a2":
	set(value):
		selected_weapon_id = value
		_load_weapon(value)

var _active_config: Dictionary = {}
var _active_weapon_instance: Node3D
var _weapon_mount: Node3D
var _preview_camera: Camera3D
var _target_dummies: Array[Node3D] = []

# Camera orbit / pan controls
var _camera_target := Vector3(0.0, 1.25, 0.0)
var _camera_distance := 1.8
var _camera_yaw := PI
var _camera_pitch := 0.1
var _is_orbiting := false
var _is_panning := false
var _last_pointer_pos := Vector2.ZERO

# Runtime shooting stats
var _fire_cooldown := 0.0
var _current_bloom := 0.0
var _recoil_pitch_offset := 0.0
var _recoil_yaw_offset := 0.0

# UI Nodes
var _stats_panel: PanelContainer
var _rpm_slider: HSlider
var _dmg_slider: HSlider
var _recoil_pitch_slider: HSlider
var _recoil_yaw_slider: HSlider
var _bloom_slider: HSlider
var _stats_summary: Label
var _last_hit_label: Label


func _ready() -> void:
	_weapon_mount = get_node_or_null("WeaponMount") as Node3D
	_preview_camera = get_node_or_null("WorkbenchCamera") as Camera3D

	if _weapon_mount == null:
		_setup_weapon_bench()
	if _preview_camera == null:
		_setup_camera()

	var targets_node := get_node_or_null("Targets") as Node3D
	if targets_node != null:
		for child in targets_node.get_children():
			if child is Node3D:
				_target_dummies.append(child)
	elif not Engine.is_editor_hint():
		_setup_targets()

	if not Engine.is_editor_hint():
		_build_full_right_hand_stats_ui()

	_load_weapon(selected_weapon_id)
	_sync_camera()


func _process(delta: float) -> void:
	if _fire_cooldown > 0.0:
		_fire_cooldown = maxf(0.0, _fire_cooldown - delta)

	if _current_bloom > 0.0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var recovery_rate: float = float(_active_config.get("bloom_recovery", 4.5))
		_current_bloom = maxf(0.0, _current_bloom - recovery_rate * delta)

	_recoil_pitch_offset = lerpf(_recoil_pitch_offset, 0.0, delta * 8.0)
	_recoil_yaw_offset = lerpf(_recoil_yaw_offset, 0.0, delta * 8.0)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_is_orbiting = mb.pressed
			_last_pointer_pos = mb.position
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = mb.pressed
			_last_pointer_pos = mb.position
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = maxf(0.4, _camera_distance - 0.15)
			_sync_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = minf(10.0, _camera_distance + 0.15)
			_sync_camera()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_try_fire_weapon()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var delta_pos := mm.position - _last_pointer_pos
		_last_pointer_pos = mm.position
		if _is_orbiting:
			_camera_yaw -= delta_pos.x * 0.006
			_camera_pitch = clampf(_camera_pitch - delta_pos.y * 0.006, -0.6, 0.8)
			_sync_camera()
		elif _is_panning and _preview_camera != null:
			var right := _preview_camera.global_transform.basis.x
			var up := _preview_camera.global_transform.basis.y
			_camera_target -= (right * delta_pos.x - up * delta_pos.y) * (_camera_distance * 0.0015)
			_sync_camera()
	elif event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		if key.keycode == KEY_R:
			_reload_weapon()


func _sync_camera() -> void:
	if _preview_camera == null:
		return
	var offset := Vector3(
		sin(_camera_yaw) * cos(_camera_pitch),
		sin(_camera_pitch),
		cos(_camera_yaw) * cos(_camera_pitch)
	) * _camera_distance
	_preview_camera.global_position = _camera_target + offset
	_preview_camera.look_at(_camera_target, Vector3.UP)


func _try_fire_weapon() -> void:
	if _fire_cooldown > 0.0 or _active_weapon_instance == null:
		return
	var rpm: float = float(_active_config.get("rpm", 750.0))
	var shot_interval: float = 60.0 / maxf(rpm, 60.0)
	_fire_cooldown = shot_interval

	# Recoil calculation
	var pitch_recoil: float = float(_active_config.get("recoil_pitch", 1.2))
	var yaw_recoil: float = float(_active_config.get("recoil_yaw", 0.4))
	_recoil_pitch_offset += deg_to_rad(pitch_recoil)
	_recoil_yaw_offset += deg_to_rad((randf() - 0.5) * yaw_recoil * 2.0)

	# Bloom spread
	var max_bloom: float = float(_active_config.get("max_bloom_deg", 3.0))
	var bloom_add: float = float(_active_config.get("bloom_per_shot", 0.4))
	_current_bloom = minf(max_bloom, _current_bloom + bloom_add)

	_spawn_muzzle_flash_and_tracer()


func _spawn_muzzle_flash_and_tracer() -> void:
	var muzzle: Node3D = _active_weapon_instance.get_node_or_null("Socket_Muzzle") as Node3D
	var origin: Vector3 = muzzle.global_position if muzzle != null else _weapon_mount.global_position + Vector3(0, 0, -0.6)
	var forward: Vector3 = -_preview_camera.global_transform.basis.z if _preview_camera != null else Vector3.FORWARD

	var spread_rad := deg_to_rad(_current_bloom)
	var spread_offset := Vector3(
		(randf() - 0.5) * spread_rad,
		(randf() - 0.5) * spread_rad + _recoil_pitch_offset,
		0.0
	)
	var ray_dir := (forward + spread_offset).normalized()

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + ray_dir * 100.0)
	var hit := space_state.intersect_ray(query)

	if not hit.is_empty():
		var hit_collider: Object = hit.get("collider")
		if hit_collider != null and hit_collider.has_method("take_hit"):
			var damage: float = float(_active_config.get("damage", 32.0))
			hit_collider.call("take_hit", damage, hit.get("position", Vector3.ZERO))
			if _last_hit_label != null:
				_last_hit_label.text = "Last Hit: %s (%.0f DMG)" % [hit_collider.get_parent().name if hit_collider.get_parent() else "Target", damage]


func _reload_weapon() -> void:
	_fire_cooldown = 1.2
	_current_bloom = 0.0


func _load_weapon(weapon_id: String) -> void:
	if _weapon_mount == null:
		return
	for child in _weapon_mount.get_children():
		child.queue_free()

	var json_path := WEAPONS_CONFIG_DIR + weapon_id + ".json"
	if FileAccess.file_exists(json_path):
		var file := FileAccess.open(json_path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			_active_config = parsed
		else:
			_active_config = _build_default_weapon_config(weapon_id)
	else:
		_active_config = _build_default_weapon_config(weapon_id)

	var scene_path := WEAPONS_SCENE_DIR + weapon_id + ".tscn"
	if ResourceLoader.exists(scene_path):
		var packed := load(scene_path) as PackedScene
		if packed != null:
			_active_weapon_instance = packed.instantiate() as Node3D
			_weapon_mount.add_child(_active_weapon_instance)
	if _active_weapon_instance == null:
		_active_weapon_instance = _build_fallback_weapon_mesh()
		_weapon_mount.add_child(_active_weapon_instance)

	_sync_ui_with_config()


func _build_default_weapon_config(weapon_id: String) -> Dictionary:
	return {
		"weapon_id": weapon_id,
		"name": weapon_id.to_upper(),
		"damage": 32.0,
		"rpm": 750.0,
		"recoil_pitch": 1.2,
		"recoil_yaw": 0.4,
		"max_bloom_deg": 3.0,
		"bloom_per_shot": 0.35,
		"bloom_recovery": 5.0
	}


func _build_fallback_weapon_mesh() -> Node3D:
	var root_node := Node3D.new()
	root_node.name = "FallbackWeapon"
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.04, 0.08, 0.6)
	body.mesh = box
	root_node.add_child(body)

	var muzzle := Marker3D.new()
	muzzle.name = "Socket_Muzzle"
	muzzle.position = Vector3(0, 0.02, -0.3)
	root_node.add_child(muzzle)

	return root_node


func _setup_weapon_bench() -> void:
	_weapon_mount = Node3D.new()
	_weapon_mount.name = "WeaponMount"
	_weapon_mount.position = Vector3(0.2, 1.3, -0.4)
	add_child(_weapon_mount)


func _setup_camera() -> void:
	_preview_camera = Camera3D.new()
	_preview_camera.name = "WorkbenchCamera"
	_preview_camera.position = Vector3(0.0, 1.35, 0.0)
	_preview_camera.current = true
	_preview_camera.fov = 55.0
	add_child(_preview_camera)


func _setup_targets() -> void:
	var distances := [10.0, 20.0, 35.0]
	for dist: float in distances:
		var target := _create_target_dummy(Vector3(0.0, 1.0, -dist), "Target_%dm" % int(dist))
		add_child(target)
		_target_dummies.append(target)


func _create_target_dummy(pos: Vector3, label_text: String) -> Node3D:
	var root_target := StaticBody3D.new()
	root_target.position = pos
	root_target.set_script(load("res://standalone_labs/dummy_target.gd"))

	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	col.shape = capsule
	root_target.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var cap_mesh := CapsuleMesh.new()
	cap_mesh.radius = 0.3
	cap_mesh.height = 1.7
	mesh_inst.mesh = cap_mesh
	root_target.add_child(mesh_inst)

	var lbl := Label3D.new()
	lbl.text = label_text
	lbl.position = Vector3(0, 1.1, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root_target.add_child(lbl)

	return root_target


func _build_full_right_hand_stats_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# Top-left control guide
	var left_panel := PanelContainer.new()
	left_panel.offset_left = 20.0
	left_panel.offset_top = 20.0
	left_panel.offset_right = 320.0
	left_panel.offset_bottom = 120.0
	canvas.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_panel.add_child(left_vbox)
	var controls_info := Label.new()
	controls_info.text = "RIGHT-DRAG: Orbit • MIDDLE: Pan\nWHEEL: Zoom • LEFT-CLICK: Fire • R: Reload"
	left_vbox.add_child(controls_info)
	_last_hit_label = Label.new()
	_last_hit_label.text = "Last Hit: None"
	_last_hit_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.7))
	left_vbox.add_child(_last_hit_label)

	# Full Right-Hand Stats & Tuning Dock
	_stats_panel = PanelContainer.new()
	_stats_panel.offset_left = -380.0
	_stats_panel.offset_top = 20.0
	_stats_panel.offset_right = -20.0
	_stats_panel.offset_bottom = 540.0
	_stats_panel.anchors_preset = Control.PRESET_TOP_RIGHT
	canvas.add_child(_stats_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_stats_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "WEAPON STATS & TUNING"
	title.add_theme_color_override("font_color", Color(0.4, 0.9, 0.7))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var weapon_menu := OptionButton.new()
	weapon_menu.add_item("M16A2", 0)
	weapon_menu.add_item("Assault Rifle 1", 1)
	weapon_menu.add_item("AK-47", 2)
	weapon_menu.add_item("M4A1", 3)
	weapon_menu.add_item("SR-25", 4)
	weapon_menu.item_selected.connect(func(i: int):
		var ids := ["m16a2", "assaultrifle_1", "ak-47", "m4a1", "sr-25"]
		if i >= 0 and i < ids.size():
			selected_weapon_id = ids[i]
	)
	vbox.add_child(weapon_menu)

	_stats_summary = Label.new()
	vbox.add_child(_stats_summary)

	# RPM Slider
	var lbl_rpm := Label.new()
	lbl_rpm.text = "Fire Rate (RPM):"
	vbox.add_child(lbl_rpm)
	_rpm_slider = HSlider.new()
	_rpm_slider.min_value = 200.0
	_rpm_slider.max_value = 1200.0
	_rpm_slider.step = 25.0
	_rpm_slider.value_changed.connect(func(v: float): _active_config["rpm"] = v; _sync_stats_summary())
	vbox.add_child(_rpm_slider)

	# Damage Slider
	var lbl_dmg := Label.new()
	lbl_dmg.text = "Bullet Damage:"
	vbox.add_child(lbl_dmg)
	_dmg_slider = HSlider.new()
	_dmg_slider.min_value = 10.0
	_dmg_slider.max_value = 100.0
	_dmg_slider.step = 1.0
	_dmg_slider.value_changed.connect(func(v: float): _active_config["damage"] = v; _sync_stats_summary())
	vbox.add_child(_dmg_slider)

	# Recoil Pitch Slider
	var lbl_rec := Label.new()
	lbl_rec.text = "Recoil Pitch Kick (°):"
	vbox.add_child(lbl_rec)
	_recoil_pitch_slider = HSlider.new()
	_recoil_pitch_slider.min_value = 0.2
	_recoil_pitch_slider.max_value = 4.0
	_recoil_pitch_slider.step = 0.1
	_recoil_pitch_slider.value_changed.connect(func(v: float): _active_config["recoil_pitch"] = v; _sync_stats_summary())
	vbox.add_child(_recoil_pitch_slider)

	# Max Bloom Slider
	var lbl_bloom := Label.new()
	lbl_bloom.text = "Max Bloom Spread (°):"
	vbox.add_child(lbl_bloom)
	_bloom_slider = HSlider.new()
	_bloom_slider.min_value = 0.5
	_bloom_slider.max_value = 8.0
	_bloom_slider.step = 0.2
	_bloom_slider.value_changed.connect(func(v: float): _active_config["max_bloom_deg"] = v; _sync_stats_summary())
	vbox.add_child(_bloom_slider)

	var save_btn := Button.new()
	save_btn.text = "Save Tuned Config (JSON)"
	save_btn.pressed.connect(_save_current_config)
	vbox.add_child(save_btn)


func _sync_ui_with_config() -> void:
	if _rpm_slider != null:
		_rpm_slider.value = float(_active_config.get("rpm", 750.0))
	if _dmg_slider != null:
		_dmg_slider.value = float(_active_config.get("damage", 32.0))
	if _recoil_pitch_slider != null:
		_recoil_pitch_slider.value = float(_active_config.get("recoil_pitch", 1.2))
	if _bloom_slider != null:
		_bloom_slider.value = float(_active_config.get("max_bloom_deg", 3.0))
	_sync_stats_summary()


func _sync_stats_summary() -> void:
	if _stats_summary == null:
		return
	var rpm := float(_active_config.get("rpm", 750.0))
	var dmg := float(_active_config.get("damage", 32.0))
	var dps := (rpm / 60.0) * dmg
	_stats_summary.text = "RPM: %d | DMG: %d | DPS: %.0f\nRecoil: %.1f° | Max Bloom: %.1f°" % [
		int(rpm), int(dmg), dps,
		float(_active_config.get("recoil_pitch", 1.2)),
		float(_active_config.get("max_bloom_deg", 3.0))
	]


func _save_current_config() -> void:
	var json_path := WEAPONS_CONFIG_DIR + selected_weapon_id + ".json"
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_active_config, "\t"))
		print("Saved weapon config to: ", json_path)
