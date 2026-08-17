class_name SocomCameraRecoverySolver
extends RefCounted

var rig
var profile:
    get: return rig.profile
var target:
    get: return rig.target
var head_marker:
    get: return rig.head_marker
var current_camera_position: Vector3:
    get: return rig.current_camera_position
var current_head_target_x: float:
    get: return rig.current_head_target_x
var current_head_target_y: float:
    get: return rig.current_head_target_y
var collision_crane_active: bool:
    get: return rig.collision_crane_active
var collision_crane_look_ahead: float:
    get: return rig.collision_crane_look_ahead
var collision_crane_view_amount: float:
    get: return rig.collision_crane_view_amount
var near_body_crop_active: bool:
    get: return rig.near_body_crop_active
var surface_slide_active: bool:
    get: return rig.surface_slide_active
var surface_slide_normal: Vector3:
    get: return rig.surface_slide_normal
var transition_crop_active: bool:
    get: return rig.transition_crop_active
    set(value): rig.transition_crop_active = value
var composition_recovery_active: bool:
    get: return rig.composition_recovery_active
    set(value): rig.composition_recovery_active = value
var composition_hard_rebase: bool:
    get: return rig.composition_hard_rebase
    set(value): rig.composition_hard_rebase = value
var composition_hard_rebase_count: int:
    get: return rig.composition_hard_rebase_count
    set(value): rig.composition_hard_rebase_count = value
var physical_recovery_state: String:
    get: return rig.physical_recovery_state
    set(value): rig.physical_recovery_state = value
var global_position: Vector3:
    get: return rig.global_position
    set(value): rig.global_position = value

func configure(camera_rig) -> void:
    rig = camera_rig

func get_process_delta_time() -> float:
    return rig.get_process_delta_time()

func _subject_projection(candidate: Vector3, force_context: bool = false) -> Dictionary:
    return rig._subject_projection(candidate, force_context)

func _subject_projection_to(candidate: Vector3, look_target: Vector3) -> Dictionary:
    return rig._subject_projection_to(candidate, look_target)

func _projection_is_reframeable(projection: Dictionary) -> bool:
    return rig._projection_is_reframeable(projection)

func _projection_keeps_horizontal_subject(projection: Dictionary) -> bool:
    return rig._projection_keeps_horizontal_subject(projection)

func _candidate_has_subject_clearance(candidate: Vector3) -> bool:
    return rig._candidate_has_subject_clearance(candidate)

func _candidate_is_subject_readable(candidate: Vector3) -> bool:
    return rig._candidate_is_subject_readable(candidate)

func _cast_camera_volume(anchor: Vector3, destination: Vector3, exclude: Array[RID]) -> Dictionary:
    return rig._cast_camera_volume(anchor, destination, exclude)

func _perched_view_direction(camera_position: Vector3, look_ahead: float, correction: float = 1.0) -> Vector3:
    return rig._perched_view_direction(camera_position, look_ahead, correction)

func _enforce_rendered_composition(
    rendered_position: Vector3,
    legal_position: Vector3,
    delta: float
) -> Vector3:
    composition_recovery_active = false
    composition_hard_rebase = false
    physical_recovery_state = "idle"
    var rendered_projection := _subject_projection(rendered_position)
    var rendered_visible: bool = bool(rendered_projection.visible)
    var rendered_error: float = INF
    if rendered_visible:
        rendered_error = absf(
            float(rendered_projection.x) - current_head_target_x
        )
    if rendered_error <= profile.rendered_head_soft_limit_x:
        return rendered_position

    # Recovery may only target the collision solver's physical endpoint. The
    # former virtual endpoint could sit beyond a wall and required hiding that
    # wall to make the shot appear valid.
    var recovery_position := legal_position
    var legal_projection := _subject_projection(recovery_position, true)
    if not bool(legal_projection.visible):
        return rendered_position
    var legal_error: float = absf(
        float(legal_projection.x) - current_head_target_x
    )
    if legal_error >= rendered_error - 0.001:
        return rendered_position

    composition_recovery_active = true
    var exclude: Array[RID] = []
    if target is CollisionObject3D:
        exclude.append((target as CollisionObject3D).get_rid())

    # Once the subject is effectively gone, continuity has failed—but an
    # emergency correction must still travel through local free space. A cut
    # to a distant legal endpoint can cross a wall and is the visible snap the
    # regression test catches. Search one bounded, improving lens step instead.
    if (
        not rendered_visible
        or rendered_error >= profile.rendered_head_hard_limit_x
    ):
        composition_hard_rebase = true
        composition_hard_rebase_count += 1
        var local_recovery := _physical_branch_recovery(
            rendered_position,
            recovery_position,
            profile.wall_branch_max_linear_speed * delta,
            exclude
        )
        if local_recovery != rendered_position:
            return local_recovery
        return recovery_position

    # At the soft guard, take only a volume-validated local step toward the
    # legal physical shot.
    return _physical_branch_recovery(
        rendered_position,
        recovery_position,
        profile.composition_recovery_speed * delta,
        exclude
    )

func _physical_branch_recovery(
    from_position: Vector3,
    destination: Vector3,
    maximum_step: float,
    exclude: Array[RID]
) -> Vector3:
    # A solid wall can separate two otherwise legal orbit endpoints. The
    # physical route is the classic spring-arm route: retract on the current
    # player ray, rotate while close, then let normal release extend the boom.
    # Starting this at the soft composition guard prevents both the stale-wall
    # hold and an emergency opposite-branch cut.
    var anchor: Vector3 = (
        target.global_position
        + Vector3.UP * float(profile.collision_anchor_height)
    )
    var current_offset: Vector3 = from_position - anchor
    var destination_offset: Vector3 = destination - anchor
    var current_length: float = current_offset.length()
    var destination_length: float = destination_offset.length()
    if current_length < 0.001 or destination_length < 0.001:
        return destination

    var current_direction: Vector3 = current_offset / current_length
    var destination_direction: Vector3 = destination_offset / destination_length
    var branch_angle: float = current_direction.angle_to(destination_direction)
    var close_length: float = (
        profile.min_camera_target_distance
        + profile.camera_collision_radius
        + profile.collision_margin
    )
    var candidate := from_position
    if branch_angle > deg_to_rad(8.0) and current_length > close_length + 0.01:
        physical_recovery_state = "RETRACT"
        candidate = anchor + current_direction * maxf(
            close_length,
            current_length - maximum_step
        )
    elif branch_angle > deg_to_rad(0.5):
        physical_recovery_state = "ROTATE"
        var angular_step: float = minf(
            branch_angle,
            deg_to_rad(profile.wall_branch_max_angular_speed_deg)
                * get_process_delta_time()
        )
        var rotated_direction := current_direction.slerp(
            destination_direction,
            angular_step / maxf(branch_angle, 0.0001)
        ).normalized()
        candidate = anchor + rotated_direction * minf(
            current_length,
            close_length
        )
    else:
        return _advance_local_lens_toward(
            from_position,
            destination,
            maximum_step,
            exclude
        )

    var anchor_cast := _cast_camera_volume(anchor, candidate, exclude)
    var local_cast := _cast_camera_volume(from_position, candidate, exclude)
    if (
        float(anchor_cast.safe_fraction) >= 0.999
        and float(local_cast.safe_fraction) >= 0.999
        and _candidate_has_subject_clearance(candidate)
    ):
        return candidate

    var candidate_projection := _subject_projection(candidate)
    var candidate_head_distance: float = candidate.distance_to(
        head_marker.global_position
    )
    if (
        physical_recovery_state == "RETRACT"
        and float(anchor_cast.safe_fraction) >= 0.999
        and float(local_cast.safe_fraction) >= 0.999
        and bool(candidate_projection.visible)
        and float(candidate_projection.x) >= 0.05
        and float(candidate_projection.x) <= 0.95
        and float(candidate_projection.y) >= 0.02
        and float(candidate_projection.y) <= 1.02
        and candidate_head_distance >= 0.70
    ):
        physical_recovery_state = "RETRACT CLOSE"
        return candidate

    # The current wall shot can already be inside the nominal head-clearance
    # radius. Retracting farther would make that worse. First rotate at the
    # current radius; this often increases clearance without changing zoom.
    var recovery_angle_step: float = minf(
        branch_angle,
        maximum_step / maxf(current_length, 0.001)
    )
    var recovery_direction := current_direction.slerp(
        destination_direction,
        recovery_angle_step / maxf(branch_angle, 0.0001)
    ).normalized()
    var rotate_candidate := anchor + recovery_direction * current_length
    var rotate_anchor_cast := _cast_camera_volume(
        anchor,
        rotate_candidate,
        exclude
    )
    var rotate_local_cast := _cast_camera_volume(
        from_position,
        rotate_candidate,
        exclude
    )
    var current_head_distance: float = from_position.distance_to(
        head_marker.global_position
    )
    var current_projection := _subject_projection(from_position)
    var rotate_projection := _subject_projection(rotate_candidate)
    var current_projection_error: float = (
        absf(float(current_projection.x) - current_head_target_x)
        if bool(current_projection.visible)
        else INF
    )
    var rotate_projection_error: float = (
        absf(float(rotate_projection.x) - current_head_target_x)
        if bool(rotate_projection.visible)
        else INF
    )
    if (
        float(rotate_anchor_cast.safe_fraction) >= 0.999
        and float(rotate_local_cast.safe_fraction) >= 0.999
        and bool(rotate_projection.visible)
        and float(rotate_projection.x) >= 0.05
        and float(rotate_projection.x) <= 0.95
        and float(rotate_projection.y) >= 0.02
        and float(rotate_projection.y) <= 1.02
        and (
            _candidate_has_subject_clearance(rotate_candidate)
            or rotate_projection_error
                < current_projection_error - 0.0001
        )
    ):
        physical_recovery_state = "ROTATE WIDE"
        return rotate_candidate

    # If the arc is blocked, rise locally on the same player side until the
    # clearance opens. Never spend vertical composition past the frame guard.
    var maximum_height: float = (
        target.global_position.y + profile.close_wall_crane_max_height
    )
    var lift_candidate := from_position + Vector3.UP * maximum_step
    lift_candidate.y = minf(lift_candidate.y, maximum_height)
    var lift_anchor_cast := _cast_camera_volume(anchor, lift_candidate, exclude)
    var lift_local_cast := _cast_camera_volume(
        from_position,
        lift_candidate,
        exclude
    )
    var lift_head_distance: float = lift_candidate.distance_to(
        head_marker.global_position
    )
    var lift_projection := _subject_projection(lift_candidate)
    if (
        lift_candidate != from_position
        and float(lift_anchor_cast.safe_fraction) >= 0.999
        and float(lift_local_cast.safe_fraction) >= 0.999
        and _projection_is_reframeable(lift_projection)
        and (
            _candidate_has_subject_clearance(lift_candidate)
            or lift_head_distance > current_head_distance + 0.001
        )
    ):
        physical_recovery_state = "LIFT"
        return lift_candidate
    physical_recovery_state = "BLOCKED rotcast %.2f/%.2f rot %.2f,%.2f err %.2f>%.2f" % [
        float(rotate_anchor_cast.safe_fraction),
        float(rotate_local_cast.safe_fraction),
        float(rotate_projection.x),
        float(rotate_projection.y),
        rotate_projection_error,
        current_projection_error
    ]
    return _advance_local_lens_toward(
        from_position,
        destination,
        maximum_step,
        exclude
    )


func _smooth_legal_camera_position(
    desired: Vector3,
    delta: float,
    close_context: bool,
    open_response: float
) -> Vector3:
    if target == null or current_camera_position == Vector3.ZERO:
        return desired

    var anchor: Vector3 = target.global_position + Vector3.UP * float(profile.collision_anchor_height)
    var current_offset: Vector3 = current_camera_position - anchor
    var desired_offset: Vector3 = desired - anchor
    var desired_length: float = desired_offset.length()
    if desired_length < 0.001:
        return desired

    if surface_slide_active:
        return _smooth_surface_slide_position(
            anchor,
            desired,
            delta,
            surface_slide_normal
        )

    # The perched-wall solve can move from the last ordinary legal shot to a
    # slightly higher continuity shot. Interpolate that short legal-side move
    # directly before applying the radial boom release below; otherwise the
    # direction change can turn a 30 cm rise into a one-frame position pop.
    if collision_crane_active:
        var transition_weight: float = 1.0 - exp(
            -profile.close_wall_crane_enter_response * delta
        )
        var transition_candidate := current_camera_position
        if current_camera_position.y < desired.y - 0.02:
            # Rise on the known legal side first. The direct diagonal between
            # two legal endpoints can still clip the wall's top corner.
            transition_candidate.y = lerpf(
                current_camera_position.y,
                desired.y,
                transition_weight
            )
        else:
            transition_candidate = current_camera_position.lerp(
                desired,
                transition_weight
            )
        var transition_exclude: Array[RID] = []
        if target is CollisionObject3D:
            transition_exclude.append((target as CollisionObject3D).get_rid())
        var transition_cast := _cast_camera_volume(
            current_camera_position,
            transition_candidate,
            transition_exclude
        )
        if (
            transition_cast.safe_fraction >= 0.999
            and _candidate_has_subject_clearance(transition_candidate)
        ):
            return transition_candidate

    # Raw aim follows input immediately. The visible lens normally follows the
    # requested boom, but a close-wall branch change slews between fully legal
    # rays while the gun/reticle keep the player's yaw and pitch authoritative.
    # Outward release remains damped to prevent a wall-exit pop.
    var current_length: float = current_offset.length()
    var current_direction: Vector3 = (
        current_offset / current_length
        if current_length > 0.001
        else desired_offset.normalized()
    )
    var desired_direction: Vector3 = desired_offset.normalized()
    var next_direction := desired_direction
    var branch_angle: float = acos(clampf(
        current_direction.dot(desired_direction),
        -1.0,
        1.0
    ))
    var branch_transition: bool = (
        close_context and branch_angle > deg_to_rad(0.5)
    )
    if (
        branch_transition
        and not near_body_crop_active
        and not _projection_is_reframeable(
            _subject_projection(current_camera_position)
        )
    ):
        # Keep traversing toward the current readable endpoint. Rejecting every
        # intermediate cropped frame is what converted a short transition into
        # a permanent wall hold.
        transition_crop_active = true
    if branch_transition:
        var maximum_angle_step: float = (
            deg_to_rad(float(profile.wall_branch_max_angular_speed_deg)) * delta
        )
        next_direction = current_direction.slerp(
            desired_direction,
            minf(1.0, maximum_angle_step / maxf(branch_angle, 0.0001))
        ).normalized()
    var next_length: float = desired_length
    if desired_length > current_length:
        var release_response: float = (
            profile.collision_release_radial_response
            if close_context
            else open_response
        )
        var release_speed: float = (
            profile.collision_release_max_radial_speed
            if close_context
            else profile.collision_max_radial_speed
        )
        var release_step: float = (desired_length - current_length) * (
            1.0 - exp(-release_response * delta)
        )
        release_step = minf(release_step, release_speed * delta)
        next_length = minf(current_length + release_step, desired_length)

    var candidate: Vector3 = anchor + next_direction * next_length
    # Constrained outward/sideways recovery is speed-limited here. The final
    # presentation invariant below also catches any emergency solver branch
    # that would otherwise bypass this local slew.
    if (
        branch_transition
        or (close_context and desired_length >= current_length - 0.001)
    ):
        var candidate_motion := candidate - current_camera_position
        var maximum_linear_step: float = (
            profile.wall_branch_max_linear_speed * delta
        )
        if candidate_motion.length() > maximum_linear_step:
            candidate = (
                current_camera_position
                + candidate_motion.normalized() * maximum_linear_step
            )
    var exclude: Array[RID] = []
    if target is CollisionObject3D:
        exclude.append((target as CollisionObject3D).get_rid())
    var candidate_cast := _cast_camera_volume(anchor, candidate, exclude)
    var candidate_projection := _subject_projection(candidate)
    var candidate_readable: bool = _candidate_is_subject_readable(candidate)
    # Close shots may intentionally crop the lower body, but they may never
    # use that crop permission to lose the operator horizontally. That stale
    # branch was what left the lens parked on a wall while the player moved on.
    if near_body_crop_active or transition_crop_active:
        candidate_readable = (
            bool(candidate_projection.visible)
            and _projection_keeps_horizontal_subject(candidate_projection)
        )
    if branch_transition and not near_body_crop_active and not transition_crop_active:
        candidate_readable = _projection_is_reframeable(
            _subject_projection(candidate)
        )
    if (
        not near_body_crop_active
        and (collision_crane_active or collision_crane_view_amount > 0.01)
    ):
        candidate_readable = _projection_is_reframeable(
            _subject_projection_to(
                candidate,
                candidate + _perched_view_direction(
                    candidate,
                    collision_crane_look_ahead,
                    smoothstep(0.0, 1.0, collision_crane_view_amount)
                ) * profile.look_ahead_distance
            )
        )
    if (
        candidate_cast.safe_fraction >= 0.999
        and candidate_readable
    ):
        return candidate

    # A blocked intermediate angle does not make the solver's distant legal
    # endpoint safe to render this frame. Returning `desired` here used to
    # bypass the branch slew entirely and teleport the lens to the opposite
    # side of the operator. Retract on the currently rendered legal ray until
    # a continuous angular route opens. Aim remains authoritative through the
    # independent gun ray and bounded reticle while the camera clears the wall.
    if branch_transition:
        var continuity_length: float = maxf(
            profile.min_camera_target_distance + profile.camera_collision_radius,
            current_length - profile.wall_branch_max_linear_speed * delta
        )
        var continuity_candidate: Vector3 = anchor + current_direction * continuity_length
        var continuity_cast := _cast_camera_volume(
            anchor,
            continuity_candidate,
            exclude
        )
        var continuity_projection := _subject_projection(continuity_candidate)
        var continuity_readable := _projection_is_reframeable(
            continuity_projection
        )
        if near_body_crop_active:
            continuity_readable = (
                bool(continuity_projection.visible)
                and _projection_keeps_horizontal_subject(continuity_projection)
            )
        if not near_body_crop_active and collision_crane_view_amount > 0.01:
            continuity_readable = _projection_is_reframeable(
                _subject_projection_to(
                    continuity_candidate,
                    continuity_candidate + _perched_view_direction(
                        continuity_candidate,
                        collision_crane_look_ahead,
                        smoothstep(0.0, 1.0, collision_crane_view_amount)
                    ) * profile.look_ahead_distance
                )
            )
        if (
            continuity_cast.safe_fraction >= 0.999
            and continuity_readable
        ):
            return continuity_candidate

        # The current world-space lens is the last known rendered shot. It is
        # preferable to hold one frame than cross geometry or snap branches.
        # This check is repeated against the live player anchor, so movement
        # cannot preserve a stale position after it ceases to be legal.
        var hold_cast := _cast_camera_volume(
            anchor,
            current_camera_position,
            exclude
        )
        var hold_readable := _projection_is_reframeable(
            _subject_projection(current_camera_position)
        )
        if collision_crane_view_amount > 0.01:
            hold_readable = _projection_is_reframeable(
                _subject_projection_to(
                    current_camera_position,
                    current_camera_position + _perched_view_direction(
                        current_camera_position,
                        collision_crane_look_ahead,
                        smoothstep(0.0, 1.0, collision_crane_view_amount)
                    ) * profile.look_ahead_distance
                )
            )
        if hold_cast.safe_fraction >= 0.999 and hold_readable:
            return current_camera_position
        # Never teleport to a distant solver branch merely because the
        # intermediate projection is cropped. The raw view still follows input
        # and the next frame recomputes a close virtual-boom or surface target.
        return current_camera_position
    return desired

func _smooth_surface_slide_position(
    anchor: Vector3,
    desired: Vector3,
    delta: float,
    wall_normal: Vector3
) -> Vector3:
    var exclude: Array[RID] = []
    if target is CollisionObject3D:
        exclude.append((target as CollisionObject3D).get_rid())

    var normal := wall_normal.normalized()
    var requested_motion: Vector3 = desired - current_camera_position
    if normal.length_squared() > 0.5:
        # Follow the virtual lens along the wall. Keep only the small normal
        # correction needed to settle on the constraint surface; never drive
        # farther into the blocker.
        var tangent_motion: Vector3 = requested_motion.slide(normal)
        var normal_motion: Vector3 = normal * maxf(
            requested_motion.dot(normal),
            0.0
        )
        requested_motion = tangent_motion + normal_motion

    var maximum_step: float = profile.wall_branch_max_linear_speed * delta
    if requested_motion.length() > maximum_step:
        requested_motion = requested_motion.normalized() * maximum_step
    var candidate := current_camera_position + requested_motion

    var local_cast := _cast_camera_volume(
        current_camera_position,
        candidate,
        exclude
    )
    var anchor_cast := _cast_camera_volume(anchor, candidate, exclude)
    if (
        local_cast.safe_fraction >= 0.999
        and anchor_cast.safe_fraction >= 0.999
        and _candidate_has_subject_clearance(candidate)
    ):
        return candidate

    # A corner may briefly block the tangent. Retract on the already legal
    # player-to-camera segment so the next frame can continue sliding. This is
    # bounded movement, not a world-space hold or opposite-side teleport.
    var current_offset: Vector3 = current_camera_position - anchor
    var current_length := current_offset.length()
    var minimum_length: float = (
        profile.min_camera_target_distance
        + profile.camera_collision_radius
    )
    if current_length > minimum_length + 0.001:
        var retracted_length := maxf(
            minimum_length,
            current_length - maximum_step
        )
        var retracted := anchor + current_offset.normalized() * retracted_length
        var retract_cast := _cast_camera_volume(anchor, retracted, exclude)
        if (
            retract_cast.safe_fraction >= 0.999
            and _candidate_has_subject_clearance(retracted)
        ):
            return retracted

    return current_camera_position

func _advance_local_lens_toward(
    from_position: Vector3,
    destination: Vector3,
    maximum_step: float,
    exclude: Array[RID]
) -> Vector3:
    var requested: Vector3 = destination - from_position
    var requested_length: float = requested.length()
    if requested_length < 0.001:
        return destination

    var step: float = minf(maximum_step, requested_length)
    var directions: Array[Vector3] = [requested.normalized()]
    var horizontal := Vector3(requested.x, 0.0, requested.z)
    if horizontal.length_squared() > 0.0001:
        var horizontal_direction := horizontal.normalized()
        for angle in [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]:
            directions.append(
                horizontal_direction.rotated(Vector3.UP, deg_to_rad(float(angle)))
            )
    if absf(requested.y) > 0.001:
        directions.append(Vector3.UP * signf(requested.y))
    if absf(requested.x) > 0.001:
        directions.append(Vector3.RIGHT * signf(requested.x))
    if absf(requested.z) > 0.001:
        directions.append(Vector3.BACK * signf(requested.z))

    var from_projection := _subject_projection(from_position)
    var from_error := INF
    if bool(from_projection.visible):
        from_error = absf(float(from_projection.x) - current_head_target_x)
    var best_position := from_position
    var best_distance: float = requested_length
    var best_error: float = from_error
    for direction in directions:
        var candidate: Vector3 = from_position + direction.normalized() * step
        var local_cast := _cast_camera_volume(
            from_position,
            candidate,
            exclude
        )
        if local_cast.safe_fraction < 0.999:
            continue
        var candidate_clearance: bool = _candidate_has_subject_clearance(candidate)
        if not candidate_clearance:
            candidate_clearance = (
                near_body_crop_active
                and candidate.distance_to(target.global_position)
                    >= profile.camera_collision_radius + profile.collision_margin
            )
        if not candidate_clearance:
            continue
        var candidate_projection := _subject_projection(candidate)
        if not bool(candidate_projection.visible):
            continue
        var candidate_x: float = float(candidate_projection.x)
        var candidate_error: float = absf(candidate_x - current_head_target_x)
        # Inside the normal ownership guard, prefer progress toward the legal
        # endpoint. Outside it, every accepted micro-step must actively recover
        # the operator toward screen center.
        if (
            (candidate_x < 0.18 or candidate_x > 0.82)
            and candidate_error >= from_error - 0.0001
        ):
            continue
        var remaining: float = candidate.distance_to(destination)
        var recovering_horizontal: bool = (
            from_error > profile.rendered_head_soft_limit_x
        )
        if (
            (recovering_horizontal and candidate_error < best_error - 0.0001)
            or (
                not recovering_horizontal
                and remaining < best_distance - 0.0001
            )
        ):
            best_distance = remaining
            best_error = candidate_error
            best_position = candidate
    return best_position
