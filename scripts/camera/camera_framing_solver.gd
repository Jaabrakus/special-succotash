class_name SocomCameraFramingSolver
extends RefCounted

var rig

func configure(camera_rig) -> void:
    rig = camera_rig

func solve(candidate: Vector3) -> Vector3:
    var head_marker = rig.head_marker
    var torso_marker = rig.torso_marker
    var pelvis_marker = rig.pelvis_marker
    var feet_marker = rig.feet_marker
    var camera = rig.camera
    var profile = rig.profile
    if (
        head_marker == null
        or torso_marker == null
        or pelvis_marker == null
        or feet_marker == null
    ):
        return candidate

    var old_pos: Vector3 = rig.global_position
    var old_basis: Basis = rig.global_basis
    rig.global_position = candidate
    rig._snap_orientation()
    var viewport_size: Vector2 = rig.get_viewport().get_visible_rect().size
    var head_screen: Vector2 = camera.unproject_position(head_marker.global_position)
    var torso_screen: Vector2 = camera.unproject_position(torso_marker.global_position)
    var pelvis_screen: Vector2 = camera.unproject_position(pelvis_marker.global_position)
    var feet_screen: Vector2 = camera.unproject_position(feet_marker.global_position)
    var head_x: float = head_screen.x / maxf(viewport_size.x, 1.0)
    var head_y: float = head_screen.y / maxf(viewport_size.y, 1.0)
    var torso_y: float = torso_screen.y / maxf(viewport_size.y, 1.0)
    var pelvis_y: float = pelvis_screen.y / maxf(viewport_size.y, 1.0)
    var feet_y: float = feet_screen.y / maxf(viewport_size.y, 1.0)
    rig.measured_head_x = head_x
    rig.measured_head_y = head_y
    rig.measured_torso_y = torso_y
    rig.measured_pelvis_y = pelvis_y
    rig.measured_feet_y = feet_y

    var probe_height: float = maxf(profile.framing_probe_height, 0.01)
    rig.global_position = candidate + Vector3.UP * probe_height
    rig._snap_orientation()
    var probe_head_y: float = (
        camera.unproject_position(head_marker.global_position).y
        / maxf(viewport_size.y, 1.0)
    )
    var probe_torso_y: float = (
        camera.unproject_position(torso_marker.global_position).y
        / maxf(viewport_size.y, 1.0)
    )
    var probe_pelvis_y: float = (
        camera.unproject_position(pelvis_marker.global_position).y
        / maxf(viewport_size.y, 1.0)
    )
    var probe_feet_y: float = (
        camera.unproject_position(feet_marker.global_position).y
        / maxf(viewport_size.y, 1.0)
    )
    var head_height_response: float = (probe_head_y - head_y) / probe_height
    var torso_height_response: float = (probe_torso_y - torso_y) / probe_height
    var pelvis_height_response: float = (probe_pelvis_y - pelvis_y) / probe_height
    var feet_height_response: float = (probe_feet_y - feet_y) / probe_height

    rig.global_position = candidate
    rig._snap_orientation()
    var camera_right: Vector3 = rig.global_basis.x.normalized()
    var probe_side: float = maxf(profile.framing_probe_side, 0.01)
    rig.global_position = candidate + camera_right * probe_side
    rig._snap_orientation()
    var probe_head_x: float = (
        camera.unproject_position(head_marker.global_position).x
        / maxf(viewport_size.x, 1.0)
    )
    var head_side_response: float = (probe_head_x - head_x) / probe_side
    rig.global_position = old_pos
    rig.global_basis = old_basis

    rig._update_terrain_crop_relaxation()
    rig.current_head_target_y = lerpf(
        profile.desired_head_y,
        profile.downward_aim_head_y,
        rig.downward_aim_amount
    )
    var steep_head_drop: float = smoothstep(0.82, 1.0, rig.downward_aim_amount)
    rig.current_head_target_y = lerpf(
        rig.current_head_target_y,
        profile.steep_downward_head_y,
        steep_head_drop
    )
    rig.current_head_target_x = profile.desired_head_x
    rig.current_head_target_x -= (
        rig.movement_lateral_ratio * profile.movement_head_x_shift
    )
    rig.current_head_target_y = lerpf(
        rig.current_head_target_y,
        profile.tight_space_head_y,
        rig.tight_space_amount
    )
    rig.current_head_target_y = lerpf(
        rig.current_head_target_y,
        profile.interior_head_y,
        rig.interior_amount
    )
    rig.current_torso_target_y = lerpf(
        profile.desired_torso_y,
        profile.interior_torso_y,
        rig.interior_amount
    )
    var wall_head_weight: float = (
        (1.0 - rig.overhead_confinement) * rig.wall_context_amount
    )
    rig.current_head_target_x = lerpf(
        rig.current_head_target_x,
        profile.wall_escape_head_x,
        wall_head_weight
    )
    rig.current_head_target_y = lerpf(
        rig.current_head_target_y,
        profile.wall_escape_head_y,
        wall_head_weight
    )
    var base_pelvis_target: float = lerpf(
        profile.desired_pelvis_y,
        profile.downward_aim_pelvis_y,
        rig.downward_aim_amount
    )
    base_pelvis_target = lerpf(
        base_pelvis_target,
        profile.interior_pelvis_y,
        rig.interior_amount
    )
    rig.current_pelvis_target_y = (
        base_pelvis_target
        - rig.terrain_crop_relaxation
        + rig.tight_space_pelvis_crop
    )
    rig.current_feet_target_y = (
        profile.desired_feet_y - rig.terrain_crop_relaxation
    )
    var pelvis_min: float = (
        rig.current_pelvis_target_y - profile.pelvis_crop_tolerance_above
    )
    var pelvis_max: float = (
        rig.current_pelvis_target_y + profile.pelvis_crop_tolerance_below
    )
    var feet_min: float = (
        rig.current_feet_target_y - profile.feet_crop_tolerance_above
    )
    var feet_max: float = (
        rig.current_feet_target_y + profile.feet_crop_tolerance_below
    )
    var head_x_error: float = head_x - rig.current_head_target_x
    var head_error: float = head_y - rig.current_head_target_y
    var torso_error: float = torso_y - rig.current_torso_target_y
    var pelvis_error := _range_error(pelvis_y, pelvis_min, pelvis_max)
    var feet_error := _range_error(feet_y, feet_min, feet_max)

    var visual_pelvis_min: float = (
        lerpf(0.88, 0.78, rig.downward_aim_amount)
        - rig.terrain_crop_relaxation
    )
    var visual_pelvis_max: float = lerpf(1.08, 0.94, rig.downward_aim_amount)
    rig.pelvis_crop_state = "CROPPED"
    if pelvis_y < visual_pelvis_min:
        rig.pelvis_crop_state = "TOO MUCH LEG"
    elif pelvis_y > visual_pelvis_max:
        rig.pelvis_crop_state = "UPPER BODY ONLY"
    if absf(head_error) < profile.framing_deadzone:
        head_error = 0.0
    if absf(head_x_error) < profile.framing_deadzone:
        head_x_error = 0.0

    var low_stance_amount: float = rig._low_stance_amount()
    var pelvis_weight: float = lerpf(
        profile.pelvis_framing_weight,
        profile.pelvis_framing_weight * profile.tight_space_pelvis_weight_scale,
        rig.tight_space_amount
    )
    var feet_weight: float = lerpf(
        profile.feet_framing_weight,
        profile.feet_framing_weight * profile.tight_space_feet_weight_scale,
        rig.tight_space_amount
    )
    pelvis_weight *= lerpf(
        1.0,
        profile.low_stance_pelvis_weight_scale,
        low_stance_amount
    )
    feet_weight *= lerpf(
        1.0,
        profile.low_stance_feet_weight_scale,
        low_stance_amount
    )
    pelvis_weight *= lerpf(1.0, 0.20, rig.downward_aim_amount)
    feet_weight *= 1.0 - rig.downward_aim_amount
    var torso_weight: float = (
        profile.torso_framing_weight
        * lerpf(1.0, 0.15, rig.downward_crane_amount)
    )
    var combined_error: float = (
        head_error * profile.head_framing_weight
        + torso_error * torso_weight
        + pelvis_error * pelvis_weight
        + feet_error * feet_weight
    )
    var combined_height_response: float = (
        head_height_response * profile.head_framing_weight
        + torso_height_response * torso_weight
        + (pelvis_height_response * pelvis_weight if pelvis_error != 0.0 else 0.0)
        + (feet_height_response * feet_weight if feet_error != 0.0 else 0.0)
    )
    var max_height_correction: float = lerpf(
        profile.max_framing_height_correction,
        profile.downward_max_framing_height_correction,
        rig.downward_aim_amount
    )
    max_height_correction = lerpf(
        max_height_correction,
        profile.interior_max_framing_height_correction,
        rig.interior_amount
    )
    max_height_correction = lerpf(
        max_height_correction,
        maxf(
            max_height_correction,
            profile.wall_escape_max_framing_height_correction
        ),
        rig.wall_context_amount
    )
    max_height_correction = maxf(
        max_height_correction,
        low_stance_amount * profile.max_low_stance_camera_drop
    )
    if absf(combined_height_response) > 0.0001:
        rig.framing_correction = clampf(
            -combined_error / combined_height_response,
            -max_height_correction,
            max_height_correction
        )
    else:
        rig.framing_correction = clampf(
            -combined_error * profile.framing_gain,
            -max_height_correction,
            max_height_correction
        )
    var max_side_correction: float = lerpf(
        profile.max_framing_side_correction,
        profile.wall_escape_max_framing_side_correction,
        rig.wall_context_amount
    )
    if absf(head_side_response) > 0.0001:
        rig.framing_side_correction = clampf(
            -head_x_error / head_side_response,
            -max_side_correction,
            max_side_correction
        )
    else:
        rig.framing_side_correction = 0.0
    return (
        candidate
        + camera_right * rig.framing_side_correction
        + Vector3.UP * rig.framing_correction
    )

func _range_error(value: float, minimum: float, maximum: float) -> float:
    if value < minimum:
        return value - minimum
    if value > maximum:
        return value - maximum
    return 0.0
