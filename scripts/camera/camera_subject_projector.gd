class_name SocomCameraSubjectProjector
extends RefCounted

var rig

func configure(camera_rig) -> void:
    rig = camera_rig

func subject_projection(
    candidate: Vector3,
    force_collision_context: bool = false
) -> Dictionary:
    return subject_projection_to(
        candidate,
        rig._look_target_from(candidate, force_collision_context)
    )

func subject_projection_to(candidate: Vector3, look_target: Vector3) -> Dictionary:
    if rig.head_marker == null or rig.camera == null:
        return {
            "visible": true,
            "x": rig.current_head_target_x,
            "y": rig.current_head_target_y,
            "distance": 99.0
        }
    # Evaluate candidates analytically rather than moving the live camera.
    # Collision search can inspect hundreds of candidates in one frame.
    var direction: Vector3 = (look_target - candidate).normalized()
    if direction.length_squared() < 0.0001:
        return {"visible": false, "x": -99.0, "y": -99.0, "distance": 0.0}
    var candidate_basis := Basis.looking_at(direction, Vector3.UP, false)
    var local_head: Vector3 = (
        candidate_basis.transposed()
        * (rig.head_marker.global_position - candidate)
    )
    var depth: float = -local_head.z
    var visible: bool = depth > rig.camera.near
    var head_x := -99.0
    var head_y := -99.0
    if visible:
        var viewport_size: Vector2 = rig.get_viewport().get_visible_rect().size
        var aspect: float = maxf(viewport_size.x, 1.0) / maxf(viewport_size.y, 1.0)
        var half_height: float = depth * tan(deg_to_rad(rig.camera.fov) * 0.5)
        var half_width: float = half_height * aspect
        head_x = 0.5 + local_head.x / maxf(half_width * 2.0, 0.0001)
        head_y = 0.5 - local_head.y / maxf(half_height * 2.0, 0.0001)
    return {
        "visible": visible,
        "x": head_x,
        "y": head_y,
        "distance": candidate.distance_to(rig.head_marker.global_position)
    }

func projection_keeps_subject(projection: Dictionary) -> bool:
    if not bool(projection.visible):
        return false
    var head_tolerance_above: float = lerpf(0.22, 0.16, rig.interior_amount)
    return (
        float(projection.distance) >= rig.profile.min_subject_camera_distance
        and float(projection.x) >= rig.current_head_target_x - 0.09
        and float(projection.x) <= rig.current_head_target_x + 0.09
        and float(projection.y) >= rig.current_head_target_y - head_tolerance_above
        and float(projection.y) <= rig.current_head_target_y + 0.14
    )

func projection_is_reframeable(projection: Dictionary) -> bool:
    return (
        bool(projection.visible)
        and float(projection.distance) >= rig.profile.min_subject_camera_distance
        and float(projection.x) >= 0.05
        and float(projection.x) <= 0.95
        and float(projection.y) >= 0.05
        and float(projection.y) <= 0.98
    )

func projection_keeps_horizontal_subject(projection: Dictionary) -> bool:
    return (
        bool(projection.visible)
        and float(projection.x) >= rig.current_head_target_x - 0.12
        and float(projection.x) <= rig.current_head_target_x + 0.12
    )

func candidate_is_reframeable(candidate: Vector3) -> bool:
    return projection_is_reframeable(subject_projection(candidate))

func post_solve_projection_score(projection: Dictionary) -> float:
    if not bool(projection.visible):
        return INF
    var distance: float = float(projection.distance)
    var score: float = (
        absf(float(projection.x) - rig.current_head_target_x) * 10.0
        + absf(float(projection.y) - rig.current_head_target_y) * 4.0
    )
    if distance < rig.profile.min_subject_camera_distance:
        score += (rig.profile.min_subject_camera_distance - distance) * 20.0
    return score

func candidate_has_subject_clearance(candidate: Vector3) -> bool:
    if rig.target == null or rig.head_marker == null:
        return true
    return (
        candidate.distance_to(rig.target.global_position)
            >= rig.profile.min_camera_target_distance
        and candidate.distance_to(rig.head_marker.global_position)
            >= rig.profile.min_subject_camera_distance
    )

func shares_current_camera_branch(candidate: Vector3) -> bool:
    if rig.target == null or rig.current_camera_position == Vector3.ZERO:
        return true
    var anchor: Vector3 = (
        rig.target.global_position
        + Vector3.UP * float(rig.profile.collision_anchor_height)
    )
    var current_offset: Vector3 = rig.current_camera_position - anchor
    var candidate_offset: Vector3 = candidate - anchor
    if current_offset.length_squared() < 0.001 or candidate_offset.length_squared() < 0.001:
        return true
    var branch_angle: float = current_offset.normalized().angle_to(
        candidate_offset.normalized()
    )
    return (
        branch_angle <= deg_to_rad(8.0)
        or rig.current_camera_position.distance_to(candidate)
            <= rig.profile.wall_branch_transition_distance
    )

func camera_marker_visibility(marker: Node3D) -> Dictionary:
    if marker == null or rig.target == null:
        return {"visible": true, "blocker": "CLEAR"}
    var query := PhysicsRayQueryParameters3D.create(
        rig.global_position,
        marker.global_position
    )
    query.collide_with_areas = false
    query.hit_from_inside = true
    if rig.target is CollisionObject3D:
        query.exclude = [(rig.target as CollisionObject3D).get_rid()]
    var hit: Dictionary = rig.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return {"visible": true, "blocker": "CLEAR"}
    var collider: Variant = hit.get("collider")
    var blocker := "GEOMETRY"
    if collider is Node:
        blocker = str((collider as Node).name)
    elif collider is Object:
        blocker = (collider as Object).get_class()
    return {"visible": false, "blocker": blocker}

func camera_subject_visibility() -> Dictionary:
    var head_result := camera_marker_visibility(rig.head_marker)
    var torso_result := camera_marker_visibility(rig.torso_marker)
    return {
        "head_visible": bool(head_result.visible),
        "head_blocker": str(head_result.blocker),
        "torso_visible": bool(torso_result.visible),
        "torso_blocker": str(torso_result.blocker),
    }

func candidate_is_subject_readable(candidate: Vector3) -> bool:
    if not candidate_has_subject_clearance(candidate):
        return false
    var projection := subject_projection(candidate)
    return (
        bool(projection.visible)
        and projection_keeps_horizontal_subject(projection)
        and float(projection.y) >= 0.05
        and float(projection.y) <= 0.98
    )
