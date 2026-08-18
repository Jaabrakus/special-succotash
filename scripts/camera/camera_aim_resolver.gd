class_name SocomCameraAimResolver
extends RefCounted

const AimIntentScript := preload("res://scripts/network/socom_aim_intent.gd")

var rig

func configure(camera_rig) -> void:
    rig = camera_rig

func update_aim_point() -> void:
    # Raw yaw/pitch owns this camera-independent intent point. A nearby camera
    # collision must never feed back into view orientation.
    var aim_height: float = lerpf(
        rig.profile.look_height,
        rig.profile.prone_aim_origin_height,
        rig._prone_stance_amount()
    )
    var origin: Vector3 = (
        rig.target.global_position
        + rig.movement_lead
        + Vector3.UP * aim_height
    )
    rig.aim_point = origin + rig._forward_direction() * rig.profile.aim_distance

func update_weapon_aim_point() -> void:
    # Acquire through the rendered cursor, beginning beyond player depth so a
    # wall behind the operator cannot become the forward aim target.
    var viewport_size: Vector2 = rig.get_viewport().get_visible_rect().size
    var cursor_pixels := Vector2(
        rig.reticle_screen_normalized.x * viewport_size.x,
        rig.reticle_screen_normalized.y * viewport_size.y
    )
    var lens_origin: Vector3 = rig.camera.project_ray_origin(cursor_pixels)
    var direction: Vector3 = rig.camera.project_ray_normal(cursor_pixels).normalized()
    var aim_height: float = lerpf(
        rig.profile.look_height,
        rig.profile.prone_aim_origin_height,
        rig._prone_stance_amount()
    )
    var player_aim_origin: Vector3 = (
        rig.target.global_position
        + rig.movement_lead
        + Vector3.UP * aim_height
    )
    var player_depth: float = maxf(
        (player_aim_origin - lens_origin).dot(direction),
        0.0
    )
    var acquisition_depth: float = minf(
        player_depth + maxf(rig.camera.near, 0.05),
        rig.profile.aim_distance - 0.10
    )
    var origin: Vector3 = lens_origin + direction * acquisition_depth
    var destination: Vector3 = lens_origin + direction * rig.profile.aim_distance
    rig.view_aim_point = destination
    var query := PhysicsRayQueryParameters3D.create(origin, destination)
    query.collide_with_areas = false
    if rig.target is CollisionObject3D:
        query.exclude = [(rig.target as CollisionObject3D).get_rid()]

    var result: Dictionary = rig.get_world_3d().direct_space_state.intersect_ray(query)
    rig.aim_hit = not result.is_empty()
    rig.aim_collider_name = "OPEN"
    if rig.aim_hit:
        rig.view_aim_point = result["position"]
        rig.aim_collider_name = _collider_name(result.get("collider"))

    # Keep the ballistic/pose target on the exact reticle ray, but do not force
    # the muzzle to converge on a point inches in front of the lens. This
    # preserves close-wall obstruction while removing the exaggerated upward
    # third-person shot angle.
    var acquired_depth: float = clampf(
        (rig.view_aim_point - lens_origin).dot(direction),
        acquisition_depth,
        rig.profile.aim_distance
    )
    var stabilized_depth: float = maxf(
        acquired_depth,
        rig.profile.minimum_ballistic_convergence_distance
    )
    var mannequin = rig.target.get_node_or_null("Mannequin") if rig.target != null else null
    if mannequin != null and mannequin.muzzle_marker != null:
        var muzzle: Vector3 = mannequin.muzzle_marker.global_position
        var muzzle_depth: float = (muzzle - lens_origin).dot(direction)
        var view_axis_point: Vector3 = lens_origin + direction * muzzle_depth
        var lateral_parallax: float = muzzle.distance_to(view_axis_point)
        var max_angle: float = deg_to_rad(
            maxf(rig.profile.maximum_convergence_angle_deg, 0.25)
        )
        stabilized_depth = maxf(
            stabilized_depth,
            muzzle_depth + lateral_parallax / maxf(tan(max_angle), 0.001)
        )
    stabilized_depth = minf(stabilized_depth, rig.profile.aim_distance)
    rig.weapon_aim_point = lens_origin + direction * stabilized_depth

func update_shot_validation() -> void:
    rig.shot_point = rig.weapon_aim_point
    rig.shot_blocked = false
    rig.shot_collider_name = rig.aim_collider_name
    if rig.target == null or rig.weapon_aim_point == Vector3.ZERO:
        return

    var mannequin = rig.target.get_node_or_null("Mannequin")
    if mannequin == null or mannequin.muzzle_marker == null:
        return

    var muzzle_position: Vector3 = mannequin.muzzle_marker.global_position
    var query := PhysicsRayQueryParameters3D.create(
        muzzle_position,
        rig.weapon_aim_point
    )
    query.collide_with_areas = false
    if rig.target is CollisionObject3D:
        query.exclude = [(rig.target as CollisionObject3D).get_rid()]

    var result: Dictionary = rig.get_world_3d().direct_space_state.intersect_ray(query)
    if result.is_empty():
        return

    rig.shot_point = result["position"]
    rig.shot_blocked = rig.shot_point.distance_to(rig.weapon_aim_point) > 0.08
    rig.shot_collider_name = _collider_name(result.get("collider"))

func build_local_aim_intent() -> Dictionary:
    # Only sequenced aim intent crosses the multiplayer boundary. Camera
    # placement and collision state remain entirely local.
    if rig.target == null:
        return {}
    var mannequin = rig.target.get_node_or_null("Mannequin")
    if mannequin == null or mannequin.muzzle_marker == null:
        return {}
    var muzzle: Vector3 = mannequin.muzzle_marker.global_position
    var direction: Vector3 = (rig.weapon_aim_point - muzzle).normalized()
    if direction.length_squared() < 0.99:
        direction = rig._forward_direction()
    var intent_angles := direction_to_yaw_pitch(direction)
    rig.aim_intent_sequence += 1
    return AimIntentScript.create(
        rig.aim_intent_sequence,
        Engine.get_physics_frames(),
        intent_angles.x,
        intent_angles.y,
        muzzle,
        direction
    )

func direction_to_yaw_pitch(direction: Vector3) -> Vector2:
    var normalized := direction.normalized()
    return Vector2(
        wrapf(atan2(-normalized.x, -normalized.z), -PI, PI),
        asin(clampf(normalized.y, -1.0, 1.0))
    )

func _collider_name(collider: Variant) -> String:
    if collider is Node:
        return str((collider as Node).name)
    if collider is Object:
        return (collider as Object).get_class()
    return "GEOMETRY"
