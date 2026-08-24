extends RefCounted

const OperatorAnimationStateContract := preload("res://scripts/player/operator_animation_state_contract.gd")
const WEAPON_BASE_PATH := "res://assets/weapons/modular_pack/"

static func _load_silencer(lab: Node,s_name: String) -> void:
	lab.selected_silencer = s_name
	if lab.current_silencer_mesh:
		lab.current_silencer_mesh.queue_free()
		lab.current_silencer_mesh = null

	if s_name == "None" or s_name == "":
		lab.is_silenced = false
		return

	lab.is_silenced = true
	var path := WEAPON_BASE_PATH + "Accessories/" + s_name + ".fbx"
	var scene := load(path) as PackedScene
	if scene:
		lab.current_silencer_mesh = scene.instantiate() as Node3D
		lab.current_silencer_mesh.scale = Vector3.ONE * (lab.auto_normalized_scale * lab.user_scale_multiplier)
		lab.current_silencer_mesh.rotation_degrees = Vector3(0, -90, 0)
		lab.current_silencer_mesh.position = lab.muzzle_marker.position if lab.muzzle_marker else lab.muzzle_local_pos
		lab.weapon_pivot.add_child(lab.current_silencer_mesh)
		lab._apply_camo_skin_to_weapon(lab.current_silencer_mesh, lab.selected_camo_idx)

static func _load_scope(lab: Node,sc_name: String) -> void:
	lab.selected_scope = sc_name
	if lab.current_scope_mesh:
		lab.current_scope_mesh.queue_free()
		lab.current_scope_mesh = null

	if sc_name == "None" or sc_name == "":
		return

	var path := WEAPON_BASE_PATH + "Accessories/" + sc_name + ".fbx"
	var scene := load(path) as PackedScene
	if scene:
		lab.current_scope_mesh = scene.instantiate() as Node3D
		lab.current_scope_mesh.scale = Vector3.ONE * (lab.auto_normalized_scale * lab.user_scale_multiplier)
		lab.current_scope_mesh.rotation_degrees = Vector3(0, -90, 0)
		lab.current_scope_mesh.position = lab.optic_marker.position if lab.optic_marker else lab.optic_local_pos
		lab.weapon_pivot.add_child(lab.current_scope_mesh)
		lab._apply_camo_skin_to_weapon(lab.current_scope_mesh, lab.selected_camo_idx)

static func _sync_weapon_transform(lab: Node,keep_trigger_attached: bool = true) -> void:
	if not lab.weapon_pivot: return
	lab.weapon_pivot.position = lab.auto_grip_center_offset + lab.grip_offset_pos
	lab.weapon_pivot.rotation_degrees = lab.grip_offset_rot
	if lab.geometry_root:
		lab.geometry_root.scale = Vector3.ONE * (lab.auto_normalized_scale * lab.user_scale_multiplier)
	elif lab.current_weapon_mesh:
		lab.current_weapon_mesh.scale = Vector3.ONE * (lab.auto_normalized_scale * lab.user_scale_multiplier)
	# Do not move the weapon to satisfy a hand constraint. The weapon is the
	# master object; right- and left-hand IK consume its saved sockets.


static func _sync_weapon_translation(lab: Node) -> void:
	lab._sync_weapon_transform(false)

static func _sync_ballistic_markers(lab: Node) -> void:
	if lab.socket_root == null:
		return
	if lab.muzzle_marker:
		lab.muzzle_marker.position = lab.muzzle_local_pos
	if lab.barrel_base_marker:
		lab.barrel_base_marker.position = lab.barrel_base_local_pos
	if lab.current_silencer_mesh and lab.muzzle_marker:
		lab.current_silencer_mesh.position = lab.muzzle_marker.position
	lab._update_fire_debug_lines()
	if lab.reticle_canvas:
		lab.reticle_canvas.queue_redraw()


static func _sync_hand_markers(lab: Node) -> void:
	if lab.right_grip_marker:
		lab.right_grip_marker.position = lab.right_grip_local_pos
	if lab.left_grip_marker:
		lab.left_grip_marker.position = lab.left_grip_local_pos


static func _sync_markers(lab: Node) -> void:
	lab._sync_hand_markers()
	lab._sync_ballistic_markers()
	if lab.ejection_marker: lab.ejection_marker.position = lab.ejection_local_pos
	if lab.optic_marker: lab.optic_marker.position = lab.optic_local_pos
	if lab.current_scope_mesh and lab.optic_marker: lab.current_scope_mesh.position = lab.optic_marker.position


static func _preview_screen_rect(lab: Node) -> Rect2:
	var viewport_rect := lab.get_viewport().get_visible_rect()
	var preview_left := viewport_rect.position.x
	if lab.sidebar_panel and is_instance_valid(lab.sidebar_panel):
		preview_left = clampf(
			lab.sidebar_panel.get_global_rect().end.x + 8.0,
			viewport_rect.position.x,
			viewport_rect.end.x - 1.0
		)
	return Rect2(
		Vector2(preview_left, viewport_rect.position.y),
		Vector2(viewport_rect.end.x - preview_left, viewport_rect.size.y)
	)


static func _reticle_screen_position(lab: Node) -> Vector2:
	# Match gameplay: the center reticle is stable screen-space aim authority.
	# The blue placement line and rendered weapon converge toward it.
	return lab._preview_screen_rect().get_center()


static func _camera_aim_sample(lab: Node) -> Dictionary:
	if lab.cam == null:
		return {"position": Vector3.ZERO, "target_locked": false}
	# Kept as a separate reference layer so the calibration view can compare the
	# gameplay camera center with the physical weapon bore without coupling them.
	var screen_center: Vector2 = lab._preview_screen_rect().get_center()
	var ray_origin: Vector3 = lab.cam.project_ray_origin(screen_center)
	var ray_direction: Vector3 = lab.cam.project_ray_normal(screen_center).normalized()
	var ray_end: Vector3 = ray_origin + ray_direction * 120.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1
	query.collide_with_areas = true
	var hit: Dictionary = lab.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"position": ray_end, "target_locked": false}
	var collider: Object = hit.get("collider")
	return {
		"position": hit.position,
		"target_locked": collider != null and collider.has_meta("gun_lab_target"),
	}


static func _muzzle_axis_sample(lab: Node) -> Dictionary:
	if lab.muzzle_marker == null or lab.current_weapon_mesh == null:
		return lab._camera_aim_sample()
	var ray_origin: Vector3 = lab.muzzle_marker.global_position
	var ray_direction: Vector3 = lab._barrel_direction_world()
	var ray_end: Vector3 = ray_origin + ray_direction * 120.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1
	query.collide_with_areas = true
	var hit: Dictionary = lab.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"position": ray_end, "target_locked": false}
	var collider: Object = hit.get("collider")
	return {
		"position": hit.position,
		"target_locked": collider != null and collider.has_meta("gun_lab_target"),
	}


static func _stance_spread_multiplier(lab: Node) -> float:
	match lab.preview_posture:
		&"PRONE": return 0.22
		&"CROUCHED": return lab.crouch_spread_multiplier
		_: return 1.0


static func _current_total_spread_deg(lab: Node) -> float:
	var composure_bloom: float = lab.composure.get_visual_bloom() * lab.max_recoil_bloom_deg
	return (
		lab.base_spread_deg * lab._stance_spread_multiplier()
		+ maxf(lab.current_bloom, composure_bloom)
	)


static func _composure_stance(lab: Node) -> OperatorComposure.Stance:
	match lab.preview_posture:
		&"PRONE": return OperatorComposure.Stance.PRONE
		&"CROUCHED": return OperatorComposure.Stance.CROUCHED
		_: return OperatorComposure.Stance.STANDING


static func _update_composure_readout(lab: Node) -> void:
	if lab.composure_readout == null:
		return
	lab.composure_readout.text = (
		"COMPOSURE  %5.1f%%\n"
		+ "AUTHORITATIVE STRESS  %5.1f%%\n"
		+ "VISIBLE BLOOM  %5.1f%%\n"
		+ "PRECISION CORE  %5.1f%%\n"
		+ "SHOT IMPULSE  %5.1f%%"
	) % [
		lab.composure.get_composure() * 100.0,
		lab.composure.stress * 100.0,
		lab.composure.get_visual_bloom() * 100.0,
		lab.composure.get_precision_core_scale() * 100.0,
		lab.composure.get_shot_bounce() * 100.0,
	]

static func _align_trigger_socket_to_right_hand(lab: Node,update_controls: bool = true) -> void:
	if not lab.weapon_pivot or not lab.right_grip_marker or not lab.right_hand_dot:
		return
	var parent_node: Node3D = lab.weapon_pivot.get_parent_node_3d()
	if parent_node == null:
		return
	var correction: Vector3 = lab.right_hand_dot.global_position - lab.right_grip_marker.global_position
	var new_world: Vector3 = lab.weapon_pivot.global_position + correction
	var local_pos: Vector3 = parent_node.global_transform.affine_inverse() * new_world
	lab.grip_offset_pos = local_pos - lab.auto_grip_center_offset
	lab._sync_weapon_transform(false)
	lab._sync_markers()
	if update_controls:
		lab._update_slider_value("grip_x", lab.grip_offset_pos.x)
		lab._update_slider_value("grip_y", lab.grip_offset_pos.y)
		lab._update_slider_value("grip_z", lab.grip_offset_pos.z)

static func _fire_shot(lab: Node) -> void:
	var interval := 60.0 / float(maxi(100, lab.fire_rate_rpm))
	lab.fire_cooldown = interval
	lab.burst_shot_count += 1
	var presentation: Dictionary = lab._fire_event_presentation()
	var effects: Array = presentation.get("effects", [])
	if OperatorAnimationStateContract.RAIL_TO_BLUE_LINE in effects:
		lab._match_weapon_rail_to_blue_line()
	lab._preview_fire_animation(presentation)
	var dispersion_multiplier: float = lab.composure.get_shot_dispersion_multiplier(
		lab.burst_shot_count,
		lab.composure_preview_movement,
		lab.composure_preview_turning
	)
	var stress_multiplier: float = (
		lab.composure_opening_stress_multiplier
		if lab.burst_shot_count <= 2
		else 1.0
	)
	lab.composure.notify_shot(1.0, stress_multiplier)

	if lab.burst_shot_count > 2:
		var bloom_increment: float = (
			lab.crouch_bloom_per_shot_deg
			if lab.preview_posture == &"CROUCHED"
			else lab.bloom_per_shot_deg
		)
		var bloom_cap: float = (
			lab.crouch_max_recoil_bloom_deg
			if lab.preview_posture == &"CROUCHED"
			else lab.max_recoil_bloom_deg
		)
		lab.current_bloom = minf(
			bloom_cap,
			lab.current_bloom + bloom_increment
		)
	if lab.dynamic_reticle:
		lab.dynamic_reticle.notify_shot(
			lab.burst_shot_count,
			1.0 + lab.current_bloom / maxf(lab.max_recoil_bloom_deg, 0.001)
		)

	if lab.muzzle_marker:
		var flash := OmniLight3D.new()
		flash.light_color = Color(1.0, 0.85, 0.3) if not lab.is_silenced else Color(0.3, 0.6, 1.0)
		flash.omni_range = 3.5
		flash.light_energy = 3.0
		lab.muzzle_marker.add_child(flash)
		lab.get_tree().create_timer(0.04).timeout.connect(flash.queue_free)

		var tracer := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.008
		cyl.bottom_radius = 0.008
		cyl.height = 1.2
		tracer.mesh = cyl
		var t_mat := StandardMaterial3D.new()
		t_mat.albedo_color = Color(1.0, 0.9, 0.4) if not lab.is_silenced else Color(0.4, 0.8, 1.0)
		t_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tracer.material_override = t_mat

		lab.last_shot_origin = lab.muzzle_marker.global_position
		var aim_sample: Dictionary = lab._muzzle_axis_sample()
		lab.current_aim_target = aim_sample.position
		var forward_dir: Vector3 = lab._barrel_direction_world()
		var spread_rad: float = deg_to_rad(lab._current_total_spread_deg()) * dispersion_multiplier
		var random := RandomNumberGenerator.new()
		random.seed = lab.burst_shot_count
		var random_angle := random.randf() * TAU
		var random_radius: float = sqrt(random.randf()) * spread_rad
		var spread_offset := Vector3(
			cos(random_angle) * random_radius,
			sin(random_angle) * random_radius,
			0.0
		)
		var shot_basis := Basis.looking_at(forward_dir, Vector3.UP)
		var shot_direction := (shot_basis * (Vector3.FORWARD + spread_offset)).normalized()
		var shot_target: Vector3 = lab.last_shot_origin + shot_direction * 120.0
		var shot_query := PhysicsRayQueryParameters3D.create(lab.last_shot_origin, shot_target)
		shot_query.collision_mask = 1
		shot_query.collide_with_areas = true
		var shot_hit: Dictionary = lab.get_world_3d().direct_space_state.intersect_ray(shot_query)
		if not shot_hit.is_empty():
			shot_target = shot_hit.position
		lab.last_shot_end = shot_target
		lab.bullet_tracers.add_child(tracer)
		tracer.global_position = lab.last_shot_origin
		tracer.look_at(shot_target)
		tracer.rotation_degrees.x += 90.0

		var tween: Tween = lab.create_tween()
		tween.tween_property(tracer, "global_position", shot_target, 0.07)
		tween.tween_callback(tracer.queue_free)

	if lab.hud_status:
		lab.hud_status.text = "💥 BANG! RPM: %d | Burst: #%d | Bloom: %.2f° | Silenced: %s" % [
			lab.fire_rate_rpm, lab.burst_shot_count, lab.current_bloom, "YES" if lab.is_silenced else "NO"
		]
