class_name SocomCameraDebugSnapshot
extends RefCounted

## Builds diagnostics for the lab HUD and recorder. Keeping this read-only
## projection outside the solver prevents telemetry growth from obscuring the
## actual camera state machine and collision code.

static func build(rig) -> Dictionary:
    var viewport_size: Vector2 = rig.get_viewport().get_visible_rect().size
    var head_x := -1.0
    var head_y := -1.0
    var torso_y := -1.0
    var pelvis_y := -1.0
    var feet_y := -1.0
    var aim_screen_x := -1.0
    var aim_screen_y := -1.0
    var camera_weapon_angle_deg := 0.0
    var camera_aim_angle_deg := 0.0
    var subject_visibility: Dictionary = rig._camera_subject_visibility()
    var rendered_view_yaw_deg := rad_to_deg(rig.yaw)

    if rig.head_marker and rig.camera:
        head_x = (
            rig.camera.unproject_position(rig.head_marker.global_position).x
            / maxf(viewport_size.x, 1.0)
        )
        head_y = (
            rig.camera.unproject_position(rig.head_marker.global_position).y
            / maxf(viewport_size.y, 1.0)
        )
    if rig.torso_marker and rig.camera:
        torso_y = (
            rig.camera.unproject_position(rig.torso_marker.global_position).y
            / maxf(viewport_size.y, 1.0)
        )
    if rig.pelvis_marker and rig.camera:
        pelvis_y = (
            rig.camera.unproject_position(rig.pelvis_marker.global_position).y
            / maxf(viewport_size.y, 1.0)
        )
    if rig.feet_marker and rig.camera:
        feet_y = (
            rig.camera.unproject_position(rig.feet_marker.global_position).y
            / maxf(viewport_size.y, 1.0)
        )

    if (
        rig.camera
        and rig.weapon_aim_point != Vector3.ZERO
        and not rig.camera.is_position_behind(rig.weapon_aim_point)
    ):
        var aim_pixels: Vector2 = rig.camera.unproject_position(rig.weapon_aim_point)
        aim_screen_x = aim_pixels.x / maxf(viewport_size.x, 1.0)
        aim_screen_y = aim_pixels.y / maxf(viewport_size.y, 1.0)
        var camera_forward: Vector3 = -rig.camera.global_basis.z.normalized()
        rendered_view_yaw_deg = rad_to_deg(atan2(-camera_forward.x, -camera_forward.z))
        var camera_to_aim: Vector3 = (
            rig.weapon_aim_point - rig.camera.global_position
        ).normalized()
        camera_aim_angle_deg = rad_to_deg(camera_forward.angle_to(camera_to_aim))
        var mannequin = (
            rig.target.get_node_or_null("Mannequin")
            if rig.target
            else null
        )
        if mannequin and mannequin.muzzle_marker:
            var weapon_to_aim: Vector3 = (
                rig.weapon_aim_point - mannequin.muzzle_marker.global_position
            ).normalized()
            camera_weapon_angle_deg = rad_to_deg(
                camera_forward.angle_to(weapon_to_aim)
            )

    var rear_boom_distance := 0.0
    if rig.target:
        var yaw_back: Vector3 = Basis(Vector3.UP, rig.yaw) * Vector3.BACK
        rear_boom_distance = maxf(
            (rig.global_position - rig.target.global_position).dot(yaw_back),
            0.0
        )
    var weapon_obstruction_amount := 0.0
    var debug_mannequin = (
        rig.target.get_node_or_null("Mannequin")
        if rig.target
        else null
    )
    if debug_mannequin and debug_mannequin.has_method("get_aim_debug_data"):
        weapon_obstruction_amount = float(
            debug_mannequin.get_aim_debug_data().weapon_obstruction_amount
        )

    return {
        "fov": rig.camera.fov if rig.camera else rig.profile.vertical_fov,
        "distance": (
            rig.global_position.distance_to(rig.target.global_position)
            if rig.target else 0.0
        ),
        "rear_boom_distance": rear_boom_distance,
        "height_above_player": (
            rig.global_position.y - rig.target.global_position.y
            if rig.target else 0.0
        ),
        "head_x": head_x,
        "head_y": head_y,
        "torso_y": torso_y,
        "pelvis_y": pelvis_y,
        "feet_y": feet_y,
        "head_target_x": rig.current_head_target_x,
        "head_target_y": rig.current_head_target_y,
        "torso_target_y": rig.current_torso_target_y,
        "pelvis_target_y": rig.current_pelvis_target_y,
        "feet_target_y": rig.current_feet_target_y,
        "measured_head_x": rig.measured_head_x,
        "measured_head_y": rig.measured_head_y,
        "measured_torso_y": rig.measured_torso_y,
        "measured_pelvis_y": rig.measured_pelvis_y,
        "measured_feet_y": rig.measured_feet_y,
        "pelvis_crop_state": rig.pelvis_crop_state,
        "framing_correction": rig.framing_correction,
        "framing_side_correction": rig.framing_side_correction,
        "post_collision_reframe": rig.post_collision_reframe,
        "post_initial_score": rig.post_initial_score,
        "post_validated_score": rig.post_validated_score,
        "post_validated_clearance": rig.post_validated_clearance,
        "post_initial_head_distance": rig.post_initial_head_distance,
        "post_validated_head_distance": rig.post_validated_head_distance,
        "collision_crane_active": rig.collision_crane_active,
        "collision_crane_look_ahead": rig.collision_crane_look_ahead,
        "collision_crane_view_amount": rig.collision_crane_view_amount,
        "surface_slide_active": rig.surface_slide_active,
        "near_body_crop_active": rig.near_body_crop_active,
        "near_body_geometry_hidden": rig.near_body_geometry_hidden,
        "transition_crop_active": rig.transition_crop_active,
        "surface_slide_candidates": rig.surface_slide_candidate_count,
        "surface_slide_clear": rig.surface_slide_clear_count,
        "surface_slide_readable": rig.surface_slide_readable_count,
        "surface_slide_target_x": rig.surface_slide_target_x,
        "surface_slide_target_y": rig.surface_slide_target_y,
        "reticle_x": rig.reticle_screen_normalized.x,
        "reticle_y": rig.reticle_screen_normalized.y,
        "reticle_dynamic_amount": rig.reticle_dynamic_amount,
        "mouse_cursor_cage_enabled": rig.mouse_cursor_cage_enabled,
        "mouse_aim_string_enabled": rig.mouse_aim_string_enabled,
        "mouse_string_debug_visible": rig.mouse_string_debug_visible,
        "mouse_string_dot_x": rig.get_mouse_string_screen_normalized().x,
        "mouse_string_dot_y": rig.get_mouse_string_screen_normalized().y,
        "mouse_intent_yaw_deg": rad_to_deg(rig.mouse_intent_yaw),
        "mouse_intent_pitch_deg": rad_to_deg(rig.mouse_intent_pitch),
        "mouse_string_yaw_stretch_deg": rad_to_deg(
            fposmod(rig.mouse_intent_yaw - rig.aim_yaw + PI, TAU) - PI
        ),
        "mouse_string_pitch_stretch_deg": rad_to_deg(
            rig.mouse_intent_pitch - rig.aim_pitch
        ),
        "mouse_cursor_x": rig.mouse_cursor_deflection.x,
        "mouse_cursor_y": rig.mouse_cursor_deflection.y,
        "mouse_edge_turn_x": rig.mouse_edge_turn.x,
        "mouse_edge_turn_y": rig.mouse_edge_turn.y,
        "aim_screen_x": aim_screen_x,
        "aim_screen_y": aim_screen_y,
        "camera_weapon_angle_deg": camera_weapon_angle_deg,
        "camera_aim_angle_deg": camera_aim_angle_deg,
        "camera_head_visible": subject_visibility.head_visible,
        "camera_head_blocker": subject_visibility.head_blocker,
        "camera_torso_visible": subject_visibility.torso_visible,
        "camera_torso_blocker": subject_visibility.torso_blocker,
        "rendered_view_yaw_deg": rendered_view_yaw_deg,
        "collision_cast_count": rig.collision_cast_count,
        "collision_solver_usec": rig.collision_solver_usec,
        "camera_state": rig.get_camera_state_name(),
        "camera_state_age": rig.camera_state_age,
        "camera_state_transitions": rig.camera_state_transition_count,
        "camera_tether_rebased": rig.camera_tether_rebased,
        "composition_recovery_active": rig.composition_recovery_active,
        "composition_hard_rebase": rig.composition_hard_rebase,
        "composition_hard_rebase_count": rig.composition_hard_rebase_count,
        "physical_recovery_state": rig.physical_recovery_state,
        "virtual_wall_occluder": (
            str(rig.virtual_wall_occluder.name)
            if rig.virtual_wall_occluder else "CLEAR"
        ),
        "wall_context_amount": rig.wall_context_amount,
        "terrain_slope_deg": rig.terrain_slope_deg,
        "terrain_crop_relaxation": rig.terrain_crop_relaxation,
        "boom_compression": rig.boom_compression,
        "overhead_confinement": rig.overhead_confinement,
        "tight_space_amount": rig.tight_space_amount,
        "interior_amount": rig.interior_amount,
        "framing_mode": rig.framing_mode,
        "wall_escape_active": rig.wall_escape_active,
        "wall_escape_angle_deg": rig.wall_escape_angle_deg,
        "local_cutout_active": rig.local_cutout_active,
        "local_cutout_center": rig.local_cutout_center,
        "local_cutout_node": (
            str(rig.local_cutout_node.name)
            if rig.local_cutout_node else "CLEAR"
        ),
        "movement_lead": rig.movement_lead,
        "movement_speed_ratio": rig.movement_speed_ratio,
        "movement_lateral_ratio": rig.movement_lateral_ratio,
        "downward_aim_amount": rig.downward_aim_amount,
        "downward_crane_amount": rig.downward_crane_amount,
        "downward_ledge_raise": rig.downward_ledge_raise,
        "aim_hit": rig.aim_hit,
        "aim_collider": rig.aim_collider_name,
        "aim_point": rig.weapon_aim_point,
        "camera_intent_point": rig.aim_point,
        "shot_point": rig.shot_point,
        "shot_blocked": rig.shot_blocked,
        "shot_collider": rig.shot_collider_name,
        "weapon_obstruction_amount": weapon_obstruction_amount,
        "excursion": rig.excursion,
        "virtual_camera_position": rig.virtual_camera_position,
        "collision_camera_position": rig.collision_camera_position,
        "collision": rig.collision_name,
        "collision_active": rig.collision_active,
        "yaw_deg": rad_to_deg(rig.yaw),
        "pitch_deg": rad_to_deg(rig.pitch),
        "aim_yaw_deg": rad_to_deg(rig.aim_yaw),
        "aim_pitch_deg": rad_to_deg(rig.aim_pitch),
        "view_pitch_deg": rad_to_deg(rig._composed_view_pitch())
    }
