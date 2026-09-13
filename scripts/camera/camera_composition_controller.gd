class_name SocomCameraCompositionController
extends RefCounted

var rig

func configure(camera_rig) -> void:
    rig = camera_rig

func update_terrain_crop_relaxation() -> void:
    rig.terrain_slope_deg = 0.0
    rig.terrain_crop_relaxation = 0.0
    if not rig.target is CharacterBody3D:
        return
    var body := rig.target as CharacterBody3D
    if not body.is_on_floor():
        return
    var floor_normal: Vector3 = body.get_floor_normal()
    rig.terrain_slope_deg = rad_to_deg(floor_normal.angle_to(Vector3.UP))
    var slope_ratio: float = clampf(
        rig.terrain_slope_deg
            / maxf(rig.profile.terrain_full_relaxation_deg, 0.001),
        0.0,
        1.0
    )
    rig.terrain_crop_relaxation = (
        slope_ratio * rig.profile.max_terrain_pelvis_reveal
    )

func update_visual_crop_state() -> void:
    if (
        rig.pelvis_marker == null
        or rig.feet_marker == null
        or rig.camera == null
    ):
        rig.pelvis_crop_state = "UNKNOWN"
        return
    var viewport_height: float = maxf(
        rig.get_viewport().get_visible_rect().size.y,
        1.0
    )
    var final_pelvis_y: float = (
        rig.camera.unproject_position(rig.pelvis_marker.global_position).y
        / viewport_height
    )
    var final_feet_y: float = (
        rig.camera.unproject_position(rig.feet_marker.global_position).y
        / viewport_height
    )
    if final_pelvis_y > 1.02:
        rig.pelvis_crop_state = "UPPER BODY ONLY"
    elif final_feet_y <= 1.0:
        rig.pelvis_crop_state = "LEGS + FEET"
    elif final_feet_y <= 1.16:
        rig.pelvis_crop_state = "LEGS, FEET CROPPED"
    elif final_pelvis_y <= 0.98:
        rig.pelvis_crop_state = "THIGHS / WAIST CROP"
    else:
        rig.pelvis_crop_state = "UPPER BODY ONLY"

func update_tight_space_state(delta: float) -> void:
    var anchor: Vector3 = (
        rig.target.global_position
        + Vector3.UP * rig.profile.collision_anchor_height
    )
    var preferred_boom: float = anchor.distance_to(rig.preferred_camera_position)
    var collision_boom: float = anchor.distance_to(rig.collision_camera_position)
    rig.boom_compression = 0.0
    if rig.collision_active:
        rig.boom_compression = clampf(
            1.0 - collision_boom / maxf(preferred_boom, 0.001),
            0.0,
            1.0
        )
    var compression_range: float = maxf(
        rig.profile.tight_space_full_compression
            - rig.profile.tight_space_compression_start,
        0.001
    )
    var compression_tightness: float = clampf(
        (rig.boom_compression - rig.profile.tight_space_compression_start)
            / compression_range,
        0.0,
        1.0
    )
    if rig.collision_active:
        compression_tightness = maxf(compression_tightness, 0.12)
    if rig.wall_escape_active:
        compression_tightness = maxf(
            compression_tightness,
            rig.profile.wall_escape_min_tightness
        )
    var target_tightness: float = maxf(
        compression_tightness,
        rig.overhead_confinement
    )
    rig.tight_space_amount = lerpf(
        rig.tight_space_amount,
        target_tightness,
        1.0 - exp(-rig.profile.tight_space_response * delta)
    )
    rig.tight_space_pelvis_crop = (
        rig.tight_space_amount * rig.profile.max_tight_space_pelvis_crop
    )
    if rig.tight_space_amount >= 0.55:
        rig.framing_mode = "TIGHT UPPER BODY"
    elif rig.tight_space_amount >= 0.08:
        rig.framing_mode = "CONSTRAINED CROP"
    else:
        rig.framing_mode = "OUTDOOR TACTICAL"

func update_dynamic_fov(delta: float) -> void:
    var target_fov: float = lerpf(
        rig.profile.vertical_fov,
        rig.profile.downward_fov,
        rig.downward_crane_amount
    )
    var steep_lens_amount: float = smoothstep(
        0.82,
        1.0,
        rig.downward_aim_amount
    )
    target_fov = lerpf(
        target_fov,
        rig.profile.steep_downward_fov,
        steep_lens_amount
    )
    # Looking down is aim, not a zoom command. Preserve obstacle recovery and
    # its close-lens widening independently of this optional authored zoom.
    if not rig.profile.pitch_zoom_enabled:
        target_fov = rig.profile.vertical_fov
    var close_lens_amount: float = smoothstep(
        rig.profile.close_fov_start_compression,
        rig.profile.close_fov_full_compression,
        rig.boom_compression
    ) * (1.0 - rig.downward_aim_amount)
    target_fov = lerpf(
        target_fov,
        maxf(target_fov, rig.profile.close_level_fov),
        close_lens_amount
    )
    var lens_response: float = maxf(
        rig.profile.downward_fov_response,
        rig.profile.close_fov_response * close_lens_amount
    )
    rig.current_fov = lerpf(
        rig.current_fov,
        target_fov,
        1.0 - exp(-lens_response * delta)
    )
    rig.camera.fov = rig.current_fov

func update_movement_follow(delta: float) -> void:
    if not rig.target is CharacterBody3D:
        rig.movement_lead = Vector3.ZERO
        rig.movement_speed_ratio = 0.0
        rig.movement_lateral_ratio = 0.0
        return
    var body := rig.target as CharacterBody3D
    var horizontal_velocity := Vector3(body.velocity.x, 0.0, body.velocity.z)
    var horizontal_speed: float = horizontal_velocity.length()
    rig.movement_speed_ratio = clampf(
        horizontal_speed / maxf(rig.profile.movement_full_speed, 0.001),
        0.0,
        1.0
    )
    var camera_right: Vector3 = Basis(Vector3.UP, rig.yaw) * Vector3.RIGHT
    rig.movement_lateral_ratio = clampf(
        horizontal_velocity.dot(camera_right)
            / maxf(rig.profile.movement_full_speed, 0.001),
        -1.0,
        1.0
    )
    var desired_lead: Vector3 = (
        horizontal_velocity * rig.profile.movement_lead_time
    )
    if desired_lead.length() > rig.profile.max_movement_lead:
        desired_lead = desired_lead.normalized() * rig.profile.max_movement_lead
    var response: float = (
        rig.profile.movement_lead_response
        if horizontal_speed > 0.05
        else rig.profile.movement_return_response
    )
    rig.movement_lead = rig.movement_lead.lerp(
        desired_lead,
        1.0 - exp(-response * delta)
    )

func measure_overhead_confinement() -> float:
    if rig.head_marker == null:
        return 0.0
    var origin: Vector3 = rig.head_marker.global_position + Vector3.UP * 0.08
    var destination: Vector3 = (
        origin + Vector3.UP * rig.profile.ceiling_probe_distance
    )
    var query := PhysicsRayQueryParameters3D.create(origin, destination)
    query.collide_with_areas = false
    if rig.target is CollisionObject3D:
        query.exclude = [(rig.target as CollisionObject3D).get_rid()]
    var hit: Dictionary = rig.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return 0.0
    var clearance: float = origin.distance_to(hit["position"])
    return clampf(
        1.0 - clearance / maxf(rig.profile.ceiling_probe_distance, 0.001),
        0.0,
        1.0
    )

func limit_excursion(candidate: Vector3) -> Vector3:
    var offset: Vector3 = candidate - rig.preferred_camera_position
    var allowed_drop: float = (
        rig.profile.max_drop
        + rig.tight_space_amount * rig.profile.max_tight_space_extra_drop
        + rig._low_stance_amount() * rig.profile.max_low_stance_camera_drop
    )
    var allowed_raise: float = lerpf(
        rig.profile.max_raise,
        rig.profile.downward_max_framing_height_correction,
        rig.downward_aim_amount
    )
    offset.y = clampf(offset.y, -allowed_drop, allowed_raise)
    var yaw_basis := Basis(Vector3.UP, rig.yaw)
    var right: Vector3 = yaw_basis * Vector3.RIGHT
    var back: Vector3 = yaw_basis * Vector3.BACK
    var local_side: float = offset.dot(right)
    var local_depth: float = offset.dot(back)
    var allowed_side: float = lerpf(
        rig.profile.max_side_excursion,
        rig.profile.max_wall_escape_side_excursion,
        maxf(rig.tight_space_amount, rig.wall_context_amount)
    )
    local_side = clampf(local_side, -allowed_side, allowed_side)
    local_depth = clampf(local_depth, -(rig.profile.distance - 0.15), 0.5)
    return (
        rig.preferred_camera_position
        + right * local_side
        + back * local_depth
        + Vector3.UP * offset.y
    )
