class_name SocomCameraCollisionSolver
extends RefCounted

const CameraPassagePolicy := preload("res://scripts/camera/camera_passage_policy.gd")

var passage_policy := CameraPassagePolicy.new()

var rig
var profile:
    get: return rig.profile
var target:
    get: return rig.target
var yaw: float:
    get: return rig.yaw
var overhead_confinement: float:
    get: return rig.overhead_confinement
var camera_collision_shape:
    get: return rig.camera_collision_shape
var collision_cast_count: int:
    get: return rig.collision_cast_count
    set(value): rig.collision_cast_count = value
var current_camera_position: Vector3:
    get: return rig.current_camera_position
var last_readable_post_solve_position: Vector3:
    get: return rig.last_readable_post_solve_position
var near_body_crop_active: bool:
    get: return rig.near_body_crop_active
var current_head_target_x: float:
    get: return rig.current_head_target_x
var current_head_target_y: float:
    get: return rig.current_head_target_y
var surface_slide_active: bool:
    get: return rig.surface_slide_active
var surface_slide_normal: Vector3:
    get: return rig.surface_slide_normal
var surface_slide_candidate_count: int:
    get: return rig.surface_slide_candidate_count
    set(value): rig.surface_slide_candidate_count = value
var surface_slide_clear_count: int:
    get: return rig.surface_slide_clear_count
    set(value): rig.surface_slide_clear_count = value
var surface_slide_readable_count: int:
    get: return rig.surface_slide_readable_count
    set(value): rig.surface_slide_readable_count = value
var surface_slide_target_x: float:
    get: return rig.surface_slide_target_x
    set(value): rig.surface_slide_target_x = value
var surface_slide_target_y: float:
    get: return rig.surface_slide_target_y
    set(value): rig.surface_slide_target_y = value

func configure(camera_rig) -> void:
    rig = camera_rig

func get_world_3d() -> World3D:
    return rig.get_world_3d()

func _subject_projection(candidate: Vector3, force_context: bool = false) -> Dictionary:
    return rig._subject_projection(candidate, force_context)

func _projection_is_reframeable(projection: Dictionary) -> bool:
    return rig._projection_is_reframeable(projection)

func _projection_keeps_horizontal_subject(projection: Dictionary) -> bool:
    return rig._projection_keeps_horizontal_subject(projection)

func _candidate_has_subject_clearance(candidate: Vector3) -> bool:
    return rig._candidate_has_subject_clearance(candidate)

func _post_solve_projection_score(projection: Dictionary) -> float:
    return rig._post_solve_projection_score(projection)

func _solve_framing(candidate: Vector3) -> Vector3:
    return rig._solve_framing(candidate)

func _solve_collision(desired: Vector3) -> Dictionary:
    var anchor: Vector3 = target.global_position + Vector3.UP * float(profile.collision_anchor_height)
    var space := get_world_3d().direct_space_state
    var exclude: Array[RID] = []
    if target is CollisionObject3D:
        exclude.append((target as CollisionObject3D).get_rid())

    var desired_cast := _cast_camera_volume(anchor, desired, exclude)
    if desired_cast.safe_fraction >= 0.999:
        return {
            "position": desired,
            "collided": false,
            "collider_name": "CLEAR",
            "collider_node": null,
            "escaped": false,
            "escape_angle_deg": 0.0,
            "local_cutout": false,
            "cutout_center": Vector3.ZERO,
            "cutout_node": null
        }

    var collider_name := "CAMERA VOLUME"
    var collider_node: Node3D = null
    var hit_query := PhysicsRayQueryParameters3D.create(anchor, desired)
    hit_query.exclude = desired_cast.get("exclude", exclude)
    hit_query.collide_with_areas = false
    var center_hit: Dictionary = space.intersect_ray(hit_query)
    if not center_hit.is_empty():
        var collider: Variant = center_hit.get("collider")
        if collider is Node:
            collider_name = str((collider as Node).name)
            if collider is Node3D:
                collider_node = collider as Node3D
        elif collider is Object:
            collider_name = (collider as Object).get_class()

    # Classic third-person boom: spend distance on the existing camera ray
    # before considering any lateral movement. This is deterministic, cheap,
    # and keeps input rotation separate from collision response.
    var desired_offset: Vector3 = desired - anchor
    var safe_fraction: float = clampf(float(desired_cast.safe_fraction), 0.0, 1.0)
    var compressed_position: Vector3 = anchor + desired_offset * safe_fraction
    var compressed_projection := _subject_projection(compressed_position, true)
    if profile.hold_rendered_camera_on_obstruction:
        # Classic collision hold: geometry owns the rendered lens immediately.
        # Aim and the virtual camera keep turning, but the visible camera never
        # climbs or switches sides to preserve composition. When this boom is
        # clear again, the ordinary radial release extends it smoothly.
        return {
            "position": compressed_position,
            "collided": true,
            "collider_name": "%s / BOOM HELD" % collider_name,
            "collider_node": collider_node,
            "escaped": false,
            "escape_angle_deg": 0.0,
            "local_cutout": false,
            "cutout_center": Vector3.ZERO,
            "cutout_node": null,
            "hold_lens": true,
            "near_body_crop_active": true,
        }
    if (
        _candidate_has_subject_clearance(compressed_position)
        and _projection_is_reframeable(compressed_projection)
    ):
        return {
            "position": compressed_position,
            "collided": true,
            "collider_name": "%s / BOOM COMPRESSED" % collider_name,
            "collider_node": collider_node,
            "escaped": false,
            "escape_angle_deg": 0.0,
            "local_cutout": false,
            "cutout_center": Vector3.ZERO,
            "cutout_node": null
        }

    # If the direct compressed shot cannot retain the character, test a tiny
    # PS2-style correction set. Outdoor walls get a few deterministic lateral
    # candidates so the lens can remain behind the operator instead of entering
    # the head. Enclosed rooms stay vertical-only, preventing the old shoulder
    # jump and opposite-side flip regression.
    var micro_offsets: Array[Vector3] = [
        Vector3.UP * 0.20,
        Vector3.UP * 0.40,
        Vector3.UP * 0.60,
        Vector3.UP * 0.90,
        Vector3.UP * 1.20,
        Vector3.UP * 1.50,
        Vector3.DOWN * 0.20
    ]
    var camera_right: Vector3 = Basis(Vector3.UP, yaw) * Vector3.RIGHT
    var micro_destinations: Array[Vector3] = []
    for adjustment in micro_offsets:
        micro_destinations.append(compressed_position + adjustment)
    # Outdoor side escape must begin from the desired boom. Offsetting an
    # already-crushed lens leaves it beside the head; offsetting the desired
    # shot lets the volume cast recover the proven ~3 m close-wall position.
    if overhead_confinement < 0.25:
        for side_value in [0.25, 0.45]:
            var side: float = float(side_value)
            micro_destinations.append(desired + camera_right * side)
            micro_destinations.append(desired + camera_right * -side)
            micro_destinations.append(
                desired + Vector3.UP * 0.30 + camera_right * side
            )
            micro_destinations.append(
                desired + Vector3.UP * 0.30 + camera_right * -side
            )
    # If the compressed lens is resting on the blocker, rising from that exact
    # boundary can still graze it. Try progressively shorter versions of the
    # same boom with extra height—the classic closer-and-higher wall response.
    for boom_scale_value in [0.85, 0.70, 0.55]:
        var boom_scale: float = float(boom_scale_value)
        for lift_value in [0.30, 0.60, 0.90, 1.20]:
            var lift: float = float(lift_value)
            micro_destinations.append(
                anchor + (compressed_position - anchor) * boom_scale + Vector3.UP * lift
            )
    var best_candidate := Vector3.ZERO
    var best_score := INF
    var best_side_amount: float = 0.0
    for adjusted_destination in micro_destinations:
        # Every correction is re-cast as a camera volume. Vertical corrections
        # originate at the compressed lens; outdoor side corrections originate
        # at the desired boom so they can recover useful subject distance.
        var adjusted_cast := _cast_camera_volume(anchor, adjusted_destination, exclude)
        var candidate: Vector3 = anchor + (
            adjusted_destination - anchor
        ) * clampf(float(adjusted_cast.safe_fraction), 0.0, 1.0)
        if not _candidate_has_subject_clearance(candidate):
            continue
        var projection := _subject_projection(candidate, true)
        if not _projection_is_reframeable(projection):
            continue
        var composition_cost: float = (
            absf(float(projection.x) - current_head_target_x) * 10.0
            + absf(float(projection.y) - current_head_target_y) * 4.0
        )
        var correction_cost: float = adjusted_destination.distance_to(compressed_position) * 0.75
        var score: float = composition_cost + correction_cost
        if score < best_score:
            best_score = score
            best_candidate = candidate
            best_side_amount = (candidate - compressed_position).dot(camera_right)

    if best_score < INF:
        var escaped_sideways: bool = absf(best_side_amount) > 0.01
        var escape_angle: float = 0.0
        if escaped_sideways:
            var boom_length: float = maxf(
                (compressed_position - anchor).length(),
                0.001
            )
            escape_angle = rad_to_deg(atan2(best_side_amount, boom_length))
        return {
            "position": best_candidate,
            "collided": true,
            "collider_name": "%s / MICRO ADJUST" % collider_name,
            "collider_node": collider_node,
            "escaped": escaped_sideways,
            "escape_angle_deg": escape_angle,
            "local_cutout": false,
            "cutout_center": Vector3.ZERO,
            "cutout_node": null
        }

    # Physical fallback remains on the current requested boom ray. Never reuse
    # a readable position from an older yaw, because that would make collision
    # lag or consume the player's turn input.
    return {
        "position": compressed_position,
        "collided": true,
        "collider_name": "%s / PHYSICAL CLOSE" % collider_name,
        "collider_node": collider_node,
        "escaped": false,
        "escape_angle_deg": 0.0,
        "local_cutout": false,
        "cutout_center": Vector3.ZERO,
        "cutout_node": null
    }

func _solve_better_post_collision(
    initial_result: Dictionary,
    requested_position: Vector3
) -> Dictionary:
    var anchor: Vector3 = target.global_position + Vector3.UP * float(profile.collision_anchor_height)
    var exclude: Array[RID] = []
    if target is CollisionObject3D:
        exclude.append((target as CollisionObject3D).get_rid())

    var initial_position: Vector3 = initial_result.position
    var best_position: Vector3 = initial_position
    var best_projection := _subject_projection(initial_position, true)
    var best_score: float = _post_solve_projection_score(best_projection)
    var best_is_readable: bool = (
        _candidate_has_subject_clearance(initial_position)
        and _projection_is_reframeable(best_projection)
        and _projection_keeps_horizontal_subject(best_projection)
    )
    var best_escape_angle: float = float(initial_result.escape_angle_deg)
    var surface_slide_solved: bool = false
    var near_body_crop_solved: bool = false
    var solved_surface_normal := Vector3.ZERO

    # Low rooms keep the established centerline-only behavior. Their regular
    # post-pass normally succeeds; these vertical candidates are a final legal
    # refinement without reintroducing corner-to-corner shoulder jumps.
    var desired_offset: Vector3 = requested_position - anchor
    var orbit_angles: Array[float] = [0.0]
    if overhead_confinement < 0.25:
        orbit_angles = [
            0.0,
            18.0, -18.0,
            36.0, -36.0,
            60.0, -60.0,
            78.0, -78.0,
            90.0, -90.0
        ]
    var radius_scales: Array[float] = [1.0, 0.82, 0.66]
    var lift_offsets: Array[float] = [0.0, 0.35, 0.70, 1.05]
    for angle_deg in orbit_angles:
        var rotated_offset: Vector3 = (
            Basis(Vector3.UP, deg_to_rad(angle_deg)) * desired_offset
        )
        for radius_scale in radius_scales:
            for lift in lift_offsets:
                var destination: Vector3 = (
                    anchor
                    + rotated_offset * radius_scale
                    + Vector3.UP * lift
                )
                var candidate_cast := _cast_camera_volume(anchor, destination, exclude)
                if candidate_cast.safe_fraction < 0.999:
                    continue
                if not _candidate_has_subject_clearance(destination):
                    continue
                var projection := _subject_projection(destination, true)
                if not _projection_is_reframeable(projection):
                    continue
                if not _projection_keeps_horizontal_subject(projection):
                    continue
                var score: float = _post_solve_projection_score(projection)
                score += absf(angle_deg) * 0.012
                score += absf(1.0 - radius_scale) * 0.35
                score += lift * 0.12
                if current_camera_position != Vector3.ZERO:
                    score += destination.distance_to(current_camera_position) * (
                        profile.post_solve_position_continuity_weight
                    )
                if not best_is_readable or score < best_score:
                    best_is_readable = true
                    best_score = score
                    best_position = destination
                    best_escape_angle = angle_deg

    # The coarse post-solve establishes a legal boom. Compose once more from
    # that position and probe a small local neighborhood, accepting only fully
    # volume-clear improvements. This is the "better post-solve" stage.
    if best_is_readable:
        var camera_right: Vector3 = Basis(Vector3.UP, yaw) * Vector3.RIGHT
        var refinement_destinations: Array[Vector3] = [
            _solve_framing(best_position),
            best_position + Vector3.UP * 0.15,
            best_position + Vector3.DOWN * 0.15,
            best_position + camera_right * 0.15,
            best_position + camera_right * -0.15,
            best_position + camera_right * 0.30,
            best_position + camera_right * -0.30,
            best_position + Vector3.UP * 0.15 + camera_right * 0.15,
            best_position + Vector3.UP * 0.15 + camera_right * -0.15
        ]
        for destination in refinement_destinations:
            var candidate_cast := _cast_camera_volume(anchor, destination, exclude)
            if candidate_cast.safe_fraction < 0.999:
                continue
            if not _candidate_has_subject_clearance(destination):
                continue
            var projection := _subject_projection(destination, true)
            if not _projection_is_reframeable(projection):
                continue
            if not _projection_keeps_horizontal_subject(projection):
                continue
            var score: float = _post_solve_projection_score(projection)
            score += destination.distance_to(best_position) * 0.08
            if current_camera_position != Vector3.ZERO:
                score += destination.distance_to(current_camera_position) * (
                    profile.post_solve_position_continuity_weight
                )
            if score < best_score:
                best_score = score
                best_position = destination

    # The endpoint may sit on a different orbit branch, but it remains useful:
    # presentation now reaches it with a physical retract-rotate-extend move.
    # Rejecting it here was what forced the old virtual wall crossing.

    # At a side-on corner, the direct orbit arc may be blocked even though a
    # legal tangent route exists along the player-facing wall plane. Reuse the
    # surface solver only when it produces a fully readable physical endpoint;
    # unlike the former virtual-wall mode, the blocker remains rendered.
    if not best_is_readable and overhead_confinement < 0.25:
        var continuity_seed: Vector3 = current_camera_position
        if continuity_seed == Vector3.ZERO:
            continuity_seed = last_readable_post_solve_position
        var surface_result := _solve_virtual_camera_surface(
            anchor,
            requested_position,
            continuity_seed,
            exclude
        )
        if bool(surface_result.get("found", false)):
            var surface_position: Vector3 = surface_result.position
            var surface_projection := _subject_projection(surface_position, true)
            if (
                _candidate_has_subject_clearance(surface_position)
                and _projection_is_reframeable(surface_projection)
                and _projection_keeps_horizontal_subject(surface_projection)
            ):
                best_position = surface_position
                best_projection = surface_projection
                best_score = _post_solve_projection_score(surface_projection)
                best_is_readable = true
                surface_slide_solved = true
                solved_surface_normal = surface_result.normal

    # If the preferred-side search is completely enclosed, search higher on
    # the currently rendered player-side ray before accepting a near-body
    # fallback. These candidates remain volume-clear and keep solid geometry
    # visible while buying enough subject distance for a readable close shot.
    if not best_is_readable and current_camera_position != Vector3.ZERO:
        var current_offset: Vector3 = current_camera_position - anchor
        var current_length: float = current_offset.length()
        if current_length > 0.001:
            var current_direction: Vector3 = current_offset / current_length
            for radius_scale in [1.0, 0.85, 0.70, 0.55]:
                for lift in [0.25, 0.50, 0.75, 1.00, 1.25]:
                    var destination := (
                        anchor
                        + current_direction * current_length * float(radius_scale)
                        + Vector3.UP * float(lift)
                    )
                    var candidate_cast := _cast_camera_volume(
                        anchor,
                        destination,
                        exclude
                    )
                    if float(candidate_cast.safe_fraction) < 0.999:
                        continue
                    if not _candidate_has_subject_clearance(destination):
                        continue
                    var projection := _subject_projection(destination, true)
                    if (
                        not _projection_is_reframeable(projection)
                        or not _projection_keeps_horizontal_subject(projection)
                    ):
                        continue
                    var score: float = _post_solve_projection_score(projection)
                    score += destination.distance_to(current_camera_position) * 0.12
                    if not best_is_readable or score < best_score:
                        best_is_readable = true
                        best_score = score
                        best_position = destination
                        best_projection = projection

    # A wall-surface or orbit endpoint is not a valid tactical shot when raw
    # aim leaves the operator outside the horizontal composition guard. Fall
    # back to the collision-safe point on the current virtual boom instead of
    # preserving an old wall-side lens while the player orbits away from it.
    if not best_is_readable:
        best_position = initial_position
        best_projection = _subject_projection(initial_position, true)
        best_is_readable = true
        near_body_crop_solved = true

    var solved_result: Dictionary = initial_result.duplicate()
    solved_result.position = best_position
    solved_result.collided = true
    solved_result.escaped = absf(best_escape_angle) > 0.01
    solved_result.escape_angle_deg = best_escape_angle
    solved_result.crane_active = false
    solved_result.crane_look_ahead = profile.close_wall_crane_default_look_ahead
    solved_result.surface_slide_active = surface_slide_solved
    solved_result.surface_slide_normal = solved_surface_normal
    solved_result.near_body_crop_active = near_body_crop_solved
    var collision_base_name: String = str(initial_result.collider_name)
    collision_base_name = collision_base_name.replace(" / PHYSICAL CLOSE", "")
    if near_body_crop_solved:
        solved_result.collider_name = "%s / VIRTUAL BOOM CLOSE" % collision_base_name
    elif surface_slide_solved:
        solved_result.collider_name = "%s / VIRTUAL SURFACE SLIDE" % collision_base_name
    elif best_is_readable:
        solved_result.collider_name = "%s / BETTER POST-SOLVED" % collision_base_name
    else:
        # Geometry still owns the boundary, but the result remains inside the
        # post-solve pipeline and is reconsidered next frame rather than entering
        # a separate forced fallback mode.
        solved_result.collider_name = "%s / POST-SOLVED CONSTRAINED" % collision_base_name
    return solved_result

func _solve_virtual_camera_surface(
    anchor: Vector3,
    virtual_position: Vector3,
    continuity_seed: Vector3,
    exclude: Array[RID]
) -> Dictionary:
    surface_slide_candidate_count = 0
    surface_slide_clear_count = 0
    surface_slide_readable_count = 0
    surface_slide_target_x = -99.0
    surface_slide_target_y = -99.0
    var hit_query := PhysicsRayQueryParameters3D.create(anchor, virtual_position)
    hit_query.exclude = exclude
    hit_query.collide_with_areas = false
    var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(hit_query)
    if hit.is_empty():
        return {"found": false}

    var hit_position: Vector3 = hit.position
    var normal: Vector3 = hit.normal.normalized()
    if (anchor - hit_position).dot(normal) < 0.0:
        normal = -normal
    var skin: float = (
        profile.camera_collision_radius
        + profile.collision_margin
        + 0.015
    )
    var signed_distance: float = (virtual_position - hit_position).dot(normal)
    var projected_virtual := (
        virtual_position
        + normal * maxf(skin - signed_distance, 0.0)
    )

    # The primary point is the exact wall-plane projection. Retractions and a
    # small vertical assist handle corners and low cover without switching to a
    # separate orbit branch or changing view direction.
    var candidates: Array[Vector3] = [projected_virtual]
    var wall_tangent := Vector3.UP.cross(normal).normalized()
    if wall_tangent.length_squared() > 0.5:
        for tangent_value in [
            -3.00, -1.80, -0.60,
            0.60, 1.80, 3.00
        ]:
            var tangent_point := (
                projected_virtual
                + wall_tangent * float(tangent_value)
            )
            candidates.append(tangent_point)
            candidates.append(tangent_point + Vector3.DOWN * 0.25)
            candidates.append(tangent_point + Vector3.UP * 0.35)
    for scale_value in [0.90, 0.70, 0.54]:
        var scale: float = float(scale_value)
        var retracted := anchor + (projected_virtual - anchor) * scale
        candidates.append(retracted)
        candidates.append(retracted + Vector3.UP * 0.25)
        candidates.append(retracted + Vector3.UP * 0.75)

    var best := Vector3.ZERO
    var best_score := INF
    for candidate in candidates:
        surface_slide_candidate_count += 1
        var candidate_cast := _cast_camera_volume(anchor, candidate, exclude)
        if candidate_cast.safe_fraction < 0.999:
            continue
        surface_slide_clear_count += 1
        if not _candidate_has_subject_clearance(candidate):
            continue
        var projection := _subject_projection(candidate, true)
        var readable := _projection_is_reframeable(projection)
        if readable:
            surface_slide_readable_count += 1
        # A readable surface shot wins. If the wall makes that impossible, a
        # physically valid position that still tracks the virtual camera beats
        # freezing the lens indefinitely; the character may crop temporarily.
        var score: float = (
            _post_solve_projection_score(projection)
            if bool(projection.visible)
            else 100.0
        )
        if not readable:
            score += 25.0
        score += candidate.distance_to(projected_virtual) * 0.30
        if continuity_seed != Vector3.ZERO:
            score += candidate.distance_to(continuity_seed) * 0.08
        if score < best_score:
            best_score = score
            best = candidate
            surface_slide_target_x = float(projection.x)
            surface_slide_target_y = float(projection.y)

    return {
        "found": best_score < INF,
        "position": best,
        "normal": normal
    }

func _cast_camera_volume(anchor: Vector3, destination: Vector3, exclude: Array[RID]) -> Dictionary:
    collision_cast_count += 1
    return passage_policy.cast_camera_motion(
        get_world_3d(),
        camera_collision_shape,
        anchor,
        destination,
        profile.collision_margin,
        exclude
    )
