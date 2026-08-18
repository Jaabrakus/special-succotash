class_name SocomCameraPreferredShotSolver
extends RefCounted

var rig

func configure(camera_rig) -> void:
    rig = camera_rig

func preferred_position() -> Vector3:
    var prone_amount := prone_stance_amount()
    var peek_amount: float = 0.0
    if rig.target != null and rig.target.has_method("get_peek_amount"):
        peek_amount = clampf(float(rig.target.call("get_peek_amount")), -1.0, 1.0)
    var anchor: Vector3 = (
        rig.target.global_position
        + rig.movement_lead
        + Vector3.UP * 1.05
    )
    var yaw_basis := Basis(Vector3.UP, rig.yaw)
    var back: Vector3 = yaw_basis * Vector3.BACK
    var side: Vector3 = yaw_basis * Vector3.RIGHT
    var forward: Vector3 = yaw_basis * Vector3.FORWARD
    var base_distance: float = lerpf(
        rig.profile.distance,
        rig.profile.interior_distance,
        rig.interior_amount
    )
    var base_height: float = lerpf(
        rig.profile.height,
        rig.profile.interior_height,
        rig.interior_amount
    )
    var base_shoulder: float = lerpf(
        rig.profile.shoulder_offset,
        rig.profile.interior_shoulder_offset,
        rig.interior_amount
    )
    var shot_distance: float = lerpf(
        base_distance,
        rig.profile.downward_distance,
        rig.downward_crane_amount
    )
    var shot_height: float = lerpf(
        base_height,
        rig.profile.downward_height,
        rig.downward_crane_amount
    )
    var shot_shoulder: float = lerpf(
        base_shoulder,
        rig.profile.downward_shoulder_offset,
        rig.downward_crane_amount
    )
    return (
        anchor
        + back * shot_distance
        + Vector3.UP * (
            shot_height
            - prone_amount * rig.profile.prone_preferred_camera_drop
            + rig.downward_crane_amount * rig.profile.max_downward_camera_raise
            + rig.downward_ledge_raise
        )
        + forward * (
            rig.downward_crane_amount * rig.profile.max_downward_camera_forward
        )
        + side * (
            shot_shoulder
            + rig.downward_crane_amount * rig.profile.max_downward_camera_side
            + peek_amount * rig.profile.peek_camera_lateral_offset
        )
    )

func low_stance_amount() -> float:
    if rig.target == null or rig.head_marker == null:
        return 0.0
    var head_height: float = (
        rig.head_marker.global_position.y - rig.target.global_position.y
    )
    var stance_range: float = maxf(
        rig.profile.low_stance_head_height_start
            - rig.profile.low_stance_head_height_full,
        0.001
    )
    return clampf(
        (rig.profile.low_stance_head_height_start - head_height) / stance_range,
        0.0,
        1.0
    )

func prone_stance_amount() -> float:
    if rig.target == null or rig.head_marker == null:
        return 0.0
    var head_height: float = (
        rig.head_marker.global_position.y - rig.target.global_position.y
    )
    var stance_range: float = maxf(
        rig.profile.prone_camera_head_height_start
            - rig.profile.prone_camera_head_height_full,
        0.001
    )
    return smoothstep(
        0.0,
        1.0,
        clampf(
            (rig.profile.prone_camera_head_height_start - head_height)
                / stance_range,
            0.0,
            1.0
        )
    )

func update_environment_state(delta: float) -> void:
    rig.overhead_confinement = rig._measure_overhead_confinement()
    var target_interior: float = smoothstep(
        0.08,
        0.62,
        rig.overhead_confinement
    )
    rig.interior_amount = lerpf(
        rig.interior_amount,
        target_interior,
        1.0 - exp(-rig.profile.interior_state_response * delta)
    )

func downward_aim_amount() -> float:
    var pitch_deg: float = rad_to_deg(rig.pitch)
    var pitch_range: float = maxf(
        absf(
            rig.profile.downward_aim_full_deg
            - rig.profile.downward_aim_start_deg
        ),
        0.001
    )
    return clampf(
        (rig.profile.downward_aim_start_deg - pitch_deg) / pitch_range,
        0.0,
        1.0
    )

func forward_direction() -> Vector3:
    var target_yaw: float = rig.aim_yaw if rig.orbit_drag_enabled else rig.yaw
    var target_pitch: float = (
        rig.aim_pitch if rig.orbit_drag_enabled else rig.pitch
    )
    var yaw_basis := Basis(Vector3.UP, target_yaw)
    var yaw_forward: Vector3 = yaw_basis * Vector3.FORWARD
    var right: Vector3 = yaw_basis * Vector3.RIGHT
    return (Basis(right, target_pitch) * yaw_forward).normalized()

func composed_view_pitch() -> float:
    return clampf(
        rig.pitch,
        deg_to_rad(rig.profile.pitch_min_deg),
        deg_to_rad(rig.profile.pitch_max_deg)
    )

func look_target_from(camera_position: Vector3) -> Vector3:
    if (
        rig.aim_point != Vector3.ZERO
        and camera_position.distance_to(rig.aim_point) > 0.1
    ):
        return rig.aim_point
    return camera_position + forward_direction() * rig.profile.look_ahead_distance

func close_wall_aim_point(look_ahead: float) -> Vector3:
    return (
        rig.target.global_position
        + rig.movement_lead
        + Vector3.UP * rig.profile.look_height
        + forward_direction() * look_ahead
    )

func perched_view_direction(
    camera_position: Vector3,
    look_ahead: float,
    horizontal_correction: float = 1.0
) -> Vector3:
    var raw_direction := forward_direction()
    var raw_flat := Vector3(raw_direction.x, 0.0, raw_direction.z).normalized()
    var convergence_delta: Vector3 = (
        close_wall_aim_point(look_ahead) - camera_position
    )
    var convergence_flat := Vector3(
        convergence_delta.x,
        0.0,
        convergence_delta.z
    ).normalized()
    if convergence_flat.length_squared() < 0.0001:
        convergence_flat = raw_flat
    var corrected_flat: Vector3 = raw_flat.slerp(
        convergence_flat,
        clampf(horizontal_correction, 0.0, 1.0)
    ).normalized()
    var horizontal_length := sqrt(
        maxf(1.0 - raw_direction.y * raw_direction.y, 0.0)
    )
    return (
        corrected_flat * horizontal_length
        + Vector3.UP * raw_direction.y
    ).normalized()
