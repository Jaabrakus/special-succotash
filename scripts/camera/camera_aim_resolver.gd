class_name SocomCameraAimResolver
extends RefCounted

const AimIntentScript := preload("res://scripts/network/socom_aim_intent.gd")
const HURTBOX_AIM_DEPTH_M := 0.08

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
    # Damage anatomy is Area3D on the dedicated hurtbox layer. The sight ray
    # must acquire that exact visible region; aiming through the operator to
    # scenery behind it creates third-person parallax and turns head shots into
    # shoulder/arm hits.
    query.collision_mask = 1 | (1 << 2)
    query.collide_with_areas = true
    if rig.target is CollisionObject3D:
        query.exclude = [(rig.target as CollisionObject3D).get_rid()]

    var result: Dictionary = rig.get_world_3d().direct_space_state.intersect_ray(query)
    rig.aim_hit = not result.is_empty()
    rig.aim_collider_name = "OPEN"
    if rig.aim_hit:
        var hit_collider: Object = result.get("collider")
        rig.view_aim_point = result["position"]
        # Keep the point on the exact camera sight ray, but place it just inside
        # damage anatomy. A surface-only endpoint can be missed by the offset
        # muzzle ray because it approaches that capsule from another angle.
        if hit_collider != null and hit_collider.has_method("get_hit_region"):
            rig.view_aim_point += direction * HURTBOX_AIM_DEPTH_M
        rig.aim_collider_name = _collider_name(hit_collider)

    # An acquired visible target is the shared point for sight, pose, muzzle,
    # and ballistics. The range zero is only a fallback for open sky; it must
    # never move an actual head or torso target several metres behind itself.
    if rig.aim_hit:
        rig.weapon_aim_point = rig.view_aim_point
        return

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
    if mannequin != null and mannequin.has_method("get_active_muzzle_position"):
        var muzzle: Vector3 = mannequin.get_active_muzzle_position()
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
    if mannequin == null or not mannequin.has_method("get_active_muzzle_position"):
        return

    var muzzle_position: Vector3 = mannequin.get_active_muzzle_position()
    var query := PhysicsRayQueryParameters3D.create(
        muzzle_position,
        rig.weapon_aim_point
    )
    query.collision_mask = 1 | (1 << 2)
    query.collide_with_areas = true
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
    var mannequin: Node = rig.target.get_node_or_null("Mannequin")
    var presentation_node: Node = mannequin if mannequin != null else rig.target
    if presentation_node == null or not presentation_node.has_method("get_active_muzzle_position"):
        return {}
    var posture_name := StringName(
        rig.target.call("get_posture_name")
        if rig.target.has_method("get_posture_name")
        else &"STANDING"
    )
    var report_height := 1.35
    if posture_name == &"CROUCHED":
        report_height = 0.95
    elif posture_name == &"PRONE":
        report_height = 0.45
    # The rendered muzzle owns shot direction, but animation phase is local
    # presentation and can differ from the server. Report a stable body-relative
    # diagnostic anchor; the server replaces it with its authoritative animated
    # muzzle before tracing the bullet.
    var stable_reported_origin: Vector3 = (
        Vector3(rig.target.global_position) + Vector3.UP * report_height
    )
    var target_point := shared_target()
    var direction := stable_reported_origin.direction_to(target_point)
    if direction.length_squared() < 0.99:
        direction = rig._forward_direction()
    var intent_angles := direction_to_yaw_pitch(direction)
    var convergence_distance := stable_reported_origin.distance_to(target_point)
    rig.aim_intent_sequence += 1
    return AimIntentScript.create(
        rig.aim_intent_sequence,
        Engine.get_physics_frames(),
        intent_angles.x,
        intent_angles.y,
        stable_reported_origin,
        direction,
        convergence_distance
    )

func shared_target() -> Vector3:
    return rig.weapon_aim_point

func shared_direction_from(origin: Vector3) -> Vector3:
    var direction: Vector3 = (shared_target() - origin).normalized()
    if direction.length_squared() < 0.99:
        return rig._forward_direction()
    return direction

func shared_yaw_pitch_from(origin: Vector3) -> Vector2:
    return direction_to_yaw_pitch(shared_direction_from(origin))

func shared_body_yaw_pitch() -> Vector2:
    if rig.target == null:
        return Vector2(rig.aim_yaw, rig.aim_pitch)
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
    return shared_yaw_pitch_from(origin)

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
